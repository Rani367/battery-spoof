# battery-spoof

experimenting with spoofing the battery health percentage on a macbook air m2 running macos tahoe (26.3). purely software, no hardware mods.

this was done on a macbook that's about to be thrown out, so the whole point was to poke around and see what's possible. turns out, it's possible — but apple made it *really* annoying to get there.

## the working solution

there are two versions — a quick Frida-based approach and a permanent native daemon.

### option A: native daemon (persistent, survives updates)

a tiny native arm64e binary (`batteryd`) that runs as a LaunchDaemon. it monitors for the `PowerPreferences` extension process, freezes it with `SIGSTOP` before it can render the UI, patches `+[PLBatteryUIBackendModel getMaximumCapacity]` in memory using Mach VM remap (to bypass Apple Silicon's W^X enforcement), then resumes it. zero dependencies — no Python, no Frida. dynamically finds the method offset by parsing the binary's symbol table, so it works across macOS updates.

#### one-liner install

disable SIP first (Recovery Mode → Terminal → `csrutil disable && csrutil authenticated-root disable` → reboot), then:

```bash
curl -sL https://raw.githubusercontent.com/Rani367/battery-spoof/refs/heads/main/install-remote.sh | sudo bash
```

that's it. downloads, compiles, installs, and starts the daemon. survives reboots and macOS updates automatically.

after a factory reset, SIP gets re-enabled — just disable it again in Recovery and re-run the one-liner.

to change the percentage (default 100):

```bash
curl -sL https://raw.githubusercontent.com/Rani367/battery-spoof/refs/heads/main/install-remote.sh | sudo bash -s 65
```

### option B: frida one-shot (quick, temporary)

uses [Frida](https://frida.re) to hook into `PowerPreferences` at runtime:

1. hooks `PLBatteryUIBackendModel.getMaximumCapacity` to return a fake value
2. patches the `BatteryHealthViewModel`'s cached percentage at memory offset `0x68`
3. fires KVO (Key-Value Observing) notifications to trick SwiftUI into re-rendering

```bash
pip3 install frida-tools
./spoof.sh 65     # show 65% health
./spoof.sh 100    # look brand new
./spoof.sh 42     # the answer to everything
./spoof.sh 1      # pain
```

after it attaches, close the Battery Health info popup (click Done) and reopen it by clicking the (i) icon. the new percentage should appear. press Ctrl+C to detach. the real value comes back next time you open Settings.

#### requirements (both options)

- macOS on Apple Silicon (tested on macOS 26.3 Tahoe, MacBook Air M2)
- SIP disabled (`csrutil disable` from Recovery Mode)
- `arm64e_preview_abi` boot arg set (`sudo nvram boot-args="-arm64e_preview_abi"`)

## how the native daemon works

the daemon (`batteryd.m`) does the following every 50ms:

1. polls `proc_listpids` for a process named `PowerPreferences`
2. when found, immediately sends `SIGSTOP` to freeze it before the UI renders
3. uses `task_for_pid` to get the Mach task port
4. reads `TASK_DYLD_INFO` to find the binary's base address in the target process
5. computes the method address: `base + 0x46c4` (offset of `getMaximumCapacity` in the PowerPreferences binary)
6. uses the **remap technique** to patch executable memory on Apple Silicon:
   - allocates a temporary RW page in the target
   - copies the original code page to it
   - writes `movz x0, #65; ret` (two arm64 instructions) over the method
   - remaps the patched page over the original with `mach_vm_remap`
   - sets the page back to RX
7. sends `SIGCONT` to resume the process — it continues initializing with our patched method

the remap technique is necessary because Apple Silicon enforces W^X (write XOR execute) at the hardware level via APRR. you can't simply `mach_vm_protect` a code page to be writable.

## the journey (everything we tried)

this wasn't a clean "i knew exactly what to do" situation. it was hours of trying things, watching them fail, and trying the next thing. here's the full story.

### attempt 1: IOKit registry writes

the battery data lives in the IOKit registry under `AppleSmartBattery`. the idea was simple — just write new values to the registry.

wrote a C program (`failed-attempts/set_battery.c`) that calls `IORegistryEntrySetCFProperty` to set `NominalChargeCapacity` and `MaxCapacity`.

**result:** the driver straight up rejects all writes. `kIOReturnUnsupported` (0xe00002c1). on apple silicon, the battery data comes from the Secure Enclave / PMU hardware and the kernel driver won't let userspace touch it. this approach is dead on M-series macs (it works on old intel macs with SMBus batteries).

### attempt 2: DYLD_INSERT_LIBRARIES interposing

the classic macOS hooking technique — compile a dylib that interposes IOKit functions, inject it via `DYLD_INSERT_LIBRARIES`.

wrote `failed-attempts/interpose.c` with interpositions for `IORegistryEntryCreateCFProperty`, `IOPSGetPowerSourceDescription`, etc.

**problems:**
- System Settings is an `arm64e` binary. our dylib needs to be compiled as `arm64e` too (not just `arm64`)
- the System Volume is read-only (Signed System Volume) even with SIP off, so we can't re-sign the binary in place
- copying System Settings and re-signing it strips entitlements, so it launches without a window
- injecting into the real System Settings via `launchctl setenv` kept crashing it — arm64e pointer authentication (PAC) doesn't play nice with interposing

**result:** every variation either crashed the app or loaded but didn't hook the right process.

### attempt 3: hooking powerd (the battery daemon)

`powerd` is the daemon that reads battery data from the kernel and serves it to all clients. if we could modify what powerd serves, every app would see fake data.

attached Frida to powerd (`failed-attempts/hook_powerd.js`), hooked `IORegistryEntryCreateCFProperty` and `IOPSSetPowerSourceDetails`.

**result:** zero hooks fired. powerd reads battery data once at boot and caches it. by the time we attach, it's already done reading. the cache lives in memory but we searched for the wrong byte pattern initially (searched for `FD 0F` instead of `DD 0F` — 4093 vs 4061. facepalm).

also tried patching powerd's memory directly (`failed-attempts/patch_powerd.js`). found and replaced `AppleRawMaxCapacity` (3934) but `NominalChargeCapacity` (4061, the actual value used for health %) wasn't in writable memory. and even patching the raw capacity didn't change what Settings displayed.

### attempt 4: modifying the PowerLog sqlite database

discovered that battery data is logged in `/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL`. the `PLBatteryAgent_EventBackward_Battery` table has columns for `NominalChargeCapacity`, `AppleRawMaxCapacity`, `DesignCapacity`, etc.

updated all rows: `UPDATE PLBatteryAgent_EventBackward_Battery SET NominalChargeCapacity = 2966`.

**result:** nope. this database is historical logs for analytics, not the live data source. Settings doesn't read from here.

### attempt 5: Frida on the wrong process (GeneralSettings)

spent a while hooking `GeneralSettings.appex` thinking that's where the Battery pane lived. hooked every IOKit and IOPowerSources function, installed comprehensive tracers.

**result:** zero hooks fired. not a single battery-related function call. turns out Battery isn't under General — it's its own section in the sidebar with its own extension process.

### attempt 6: finding the right process (PowerPreferences)

wrote `failed-attempts/find_battery_process.sh` to diff running processes before and after clicking Battery. found the culprit:

```
/System/Library/ExtensionKit/Extensions/PowerPreferences.appex/Contents/MacOS/PowerPreferences
```

this is the ExtensionKit extension that handles the Battery settings pane. it only spawns when you click Battery.

### attempt 7: racing Frida attachment

since `PowerPreferences` spawns fresh when you click Battery, we tried to attach Frida faster than it could read data:

- bash `pgrep` loop (`failed-attempts/race.sh`) — way too slow
- python tight loop (`failed-attempts/race.py`) — attached after 1514 attempts, still too late

**result:** the extension reads `PLBatteryUIBackendModel.getMaximumCapacity()` during initialization, before any external tool can attach. we confirmed the hook works (calling `getMaximumCapacity()` after hooking returns 65) but the UI already cached 89%.

### attempt 8: memory scanning + patching (almost there)

attached to `PowerPreferences`, scanned the heap (`failed-attempts/patch.js`). found 83 battery-related ObjC classes, including the key ones:

- `PowerPreferences.BatteryHealthViewModel` — the SwiftUI view model (1 instance)
- `PLBatteryUIBackendModel` — has `+getMaximumCapacity` class method that returns 89
- `BUIPowerSource` — has `maxCapacity`, `currentCapacity`, etc.

dumped the `BatteryHealthViewModel` instance's raw memory and found:
- offset `0x50`: the string `"Normal"` (battery condition)
- offset `0x68`: the byte `0x59` = **89** (the health percentage!)

patched it to 65 in memory. but the UI didn't update — SwiftUI only re-renders when state changes are signaled through Combine/KVO, not when underlying memory changes silently.

### attempt 9: KVO notifications (Frida solution)

the final piece for the Frida approach: after patching the memory, fire KVO (Key-Value Observing) notifications on the view model. this tells SwiftUI "hey, a property changed, re-render please":

```javascript
vm.willChangeValueForKey_("maximumCapacity");
vm.didChangeValueForKey_("maximumCapacity");
```

we don't know the exact property names (they're Swift-only, not visible to the ObjC runtime), so we just fire notifications for a bunch of likely names. one of them hits and SwiftUI re-renders with the patched value.

**result: it works.** close and reopen the Battery Health popup and it shows 65% (or whatever you set).

### attempt 10: native daemon with SIGSTOP + mach_vm_remap (permanent solution)

the Frida approach works but requires running a script. for a fully automatic solution, we wrote a native arm64e daemon that:

1. monitors for `PowerPreferences` via `proc_listpids`
2. freezes it with `SIGSTOP` before the UI renders
3. uses `task_for_pid` + `TASK_DYLD_INFO` to find the binary base
4. patches the method at offset `0x46c4` using the remap technique (allocate RW page → copy code → patch → `mach_vm_remap` over original → set RX)
5. resumes with `SIGCONT`

installed as a LaunchDaemon on the system volume, it starts at boot and patches every time you open Battery settings. survives factory reset.

**result: fully automatic, zero dependencies, persistent.**

## key discoveries

- **battery health on apple silicon is hardware-enforced.** the value comes from the Secure Enclave / PMU, flows through a kernel driver that rejects all writes, through `powerd` which caches it, through `IOPowerSources` XPC, into the UI. you can't change it at the source.

- **macOS System Settings is split into dozens of ExtensionKit extension processes.** each sidebar item is a separate `.appex` process. Battery is handled by `PowerPreferences.appex`, not `GeneralSettings.appex`.

- **the health percentage comes from `NominalChargeCapacity / DesignCapacity`.** on our machine: 4061 / 4563 = 89%. not from `MaxCapacity` (which is just current charge level = 100) and not from `AppleRawMaxCapacity` (which is 3934).

- **`PLBatteryUIBackendModel.getMaximumCapacity`** is the single class method that returns the health percentage to the UI. it lives inside the `PowerPreferences` binary itself (not a shared framework).

- **SwiftUI views won't update from raw memory patches.** you need to trigger the Combine/KVO pipeline. firing `willChangeValueForKey:` / `didChangeValueForKey:` on the view model does the trick (Frida approach), or just patch before the UI loads (native daemon approach).

- **DYLD interposing is basically dead on arm64e.** pointer authentication makes it nearly impossible to inject dylibs into system processes, even with SIP disabled.

- **Apple Silicon enforces W^X at the hardware level.** you can't `mach_vm_protect` a code page to be writable. the workaround is the remap technique: allocate a new RW page, copy + patch, then `mach_vm_remap` it over the original and set RX.

- **PAC (Pointer Authentication) hides real addresses.** Frida returns PAC-signed pointers like `0xc349000102...` — you need `.strip()` to get the actual address (`0x102...`).

## files

```
batteryd.m               — native daemon source (the permanent solution)
batteryd.c               — earlier C version (couldn't load the ObjC class)
com.battery.spoof.plist  — LaunchDaemon plist
before-reboot.sh         — install daemon to /Library/LaunchDaemons
after-reboot.sh          — install to system volume (factory reset survival)
spoof.sh                 — frida one-shot script
spoof.js                 — frida hook script
daemon.py                — python/frida daemon (replaced by native)
failed-attempts/         — everything that didn't work (see above)
  set_battery.c          — IOKit registry write attempt
  interpose.c            — DYLD_INSERT_LIBRARIES attempt
  trace_dylib.c          — tracing dylib attempt
  hook_powerd.js         — powerd hooking attempt
  patch_powerd.js        — powerd memory patching attempt
  race.py                — frida race condition attempt
  patch.js               — heap scanning attempt
  find_battery_process.sh — process discovery script
  ...and more
```

## disclaimer

this is a cosmetic-only change. it only affects what System Settings displays. it doesn't change `ioreg` output, doesn't affect actual battery behavior, and doesn't fool third-party tools like coconutBattery. it was done for fun on a machine that's being recycled.
