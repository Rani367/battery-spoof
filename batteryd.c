// batteryd - Native battery health spoofer daemon
// Monitors for PowerPreferences, freezes it, patches getMaximumCapacity to return
// a fake value, then resumes it. No dependencies (no Python, no Frida).
//
// Compile: clang -framework Foundation -framework IOKit -o batteryd batteryd.c
// Usage:   sudo ./batteryd [percentage]  (default: 65)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>

// arm64 instructions: mov x0, #N; ret
// movz x0, #imm16 = 0xD2800000 | (imm16 << 5)
// ret              = 0xD65F03C0
static void make_patch(uint8_t *buf, int value) {
    uint32_t movz = 0xD2800000 | ((uint32_t)value << 5);
    uint32_t ret  = 0xD65F03C0;
    memcpy(buf, &movz, 4);
    memcpy(buf + 4, &ret, 4);
}

// Find PID of a process by name
static pid_t find_process(const char *name) {
    int pids[4096];
    int count = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    if (count <= 0) return 0;
    int n = count / sizeof(int);
    for (int i = 0; i < n; i++) {
        if (pids[i] == 0) continue;
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], path, sizeof(path)) > 0) {
            char *base = strrchr(path, '/');
            if (base && strcmp(base + 1, name) == 0) {
                return pids[i];
            }
        }
    }
    return 0;
}

// Get the implementation address of +[PLBatteryUIBackendModel getMaximumCapacity]
// by loading the framework in our own process (shared cache = same address everywhere)
static void *get_method_impl(void) {
    // Use NSBundle to properly load the framework (dlopen alone doesn't register ObjC classes)
    id path = ((id(*)(Class, SEL, const char *))objc_msgSend)(
        objc_getClass("NSString"),
        sel_registerName("stringWithUTF8String:"),
        "/System/Library/PrivateFrameworks/PowerLog.framework"
    );
    id bundle = ((id(*)(Class, SEL, id))objc_msgSend)(
        objc_getClass("NSBundle"),
        sel_registerName("bundleWithPath:"),
        path
    );
    BOOL loaded = ((BOOL(*)(id, SEL))objc_msgSend)(bundle, sel_registerName("load"));
    if (!loaded) {
        fprintf(stderr, "[!] Failed to load PowerLog.framework via NSBundle\n");
        // Try dlopen as fallback
        dlopen("/System/Library/PrivateFrameworks/PowerLog.framework/PowerLog", RTLD_LAZY);
    }

    Class cls = objc_getClass("PLBatteryUIBackendModel");
    if (!cls) {
        fprintf(stderr, "[!] PLBatteryUIBackendModel class not found\n");
        return NULL;
    }

    Method m = class_getClassMethod(cls, sel_registerName("getMaximumCapacity"));
    if (!m) {
        fprintf(stderr, "[!] getMaximumCapacity method not found\n");
        return NULL;
    }

    IMP imp = method_getImplementation(m);
    fprintf(stderr, "[*] getMaximumCapacity @ %p\n", (void *)imp);
    return (void *)imp;
}

// Patch the method in a remote process
static int patch_process(pid_t pid, void *target_addr, uint8_t *patch, size_t patch_size) {
    mach_port_t task;
    kern_return_t kr;

    kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[!] task_for_pid(%d) failed: %s\n", pid, mach_error_string(kr));
        return -1;
    }

    // Make the page writable
    mach_vm_address_t addr = (mach_vm_address_t)target_addr;
    mach_vm_address_t page = addr & ~((mach_vm_address_t)0xFFF); // page-align

    kr = mach_vm_protect(task, page, 0x4000, FALSE,
                         VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        // Try copy-on-write approach
        kr = mach_vm_protect(task, page, 0x4000, FALSE,
                             VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "[!] mach_vm_protect failed: %s\n", mach_error_string(kr));
            mach_port_deallocate(mach_task_self(), task);
            return -1;
        }
    }

    // Write the patch
    kr = mach_vm_write(task, addr, (vm_offset_t)patch, (mach_msg_type_number_t)patch_size);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[!] mach_vm_write failed: %s\n", mach_error_string(kr));
        mach_port_deallocate(mach_task_self(), task);
        return -1;
    }

    mach_port_deallocate(mach_task_self(), task);
    return 0;
}

int main(int argc, char *argv[]) {
    int fake_pct = 65;
    if (argc > 1) fake_pct = atoi(argv[1]);
    if (fake_pct < 1 || fake_pct > 100) {
        fprintf(stderr, "Usage: %s [1-100]\n", argv[0]);
        return 1;
    }

    fprintf(stderr, "[*] Battery Health Spoofer Daemon\n");
    fprintf(stderr, "[*] Target: %d%%\n", fake_pct);

    // Get the method address (from our own shared cache mapping)
    void *impl = get_method_impl();
    if (!impl) {
        fprintf(stderr, "[!] Could not find method. Exiting.\n");
        return 1;
    }

    // Build the patch: mov x0, #fake_pct; ret
    uint8_t patch[8];
    make_patch(patch, fake_pct);
    fprintf(stderr, "[*] Patch bytes: %02x %02x %02x %02x %02x %02x %02x %02x\n",
            patch[0], patch[1], patch[2], patch[3],
            patch[4], patch[5], patch[6], patch[7]);

    fprintf(stderr, "[*] Watching for PowerPreferences...\n");

    pid_t last_pid = 0;

    while (1) {
        pid_t pid = find_process("PowerPreferences");

        if (pid > 0 && pid != last_pid) {
            fprintf(stderr, "[*] PowerPreferences detected (PID %d)\n", pid);

            // Freeze the process immediately
            kill(pid, SIGSTOP);

            // Patch the method
            if (patch_process(pid, impl, patch, sizeof(patch)) == 0) {
                fprintf(stderr, "[+] Patched! getMaximumCapacity will return %d\n", fake_pct);
            }

            // Resume the process
            kill(pid, SIGCONT);
            last_pid = pid;
        } else if (pid == 0 && last_pid != 0) {
            // Process exited, reset
            last_pid = 0;
        }

        usleep(50000); // 50ms poll
    }

    return 0;
}
