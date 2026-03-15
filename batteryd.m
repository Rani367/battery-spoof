// batteryd - Native battery health spoofer daemon
// Dynamically finds +[PLBatteryUIBackendModel getMaximumCapacity] by parsing
// the PowerPreferences binary's symbol table. Works across macOS updates.
//
// Compile: xcrun -sdk macosx clang -arch arm64e -framework Foundation -o batteryd batteryd.m
// Usage:   sudo ./batteryd [percentage]

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld_images.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <libproc.h>
#import <signal.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <mach-o/fat.h>

#define PP_PATH "/System/Library/ExtensionKit/Extensions/PowerPreferences.appex/Contents/MacOS/PowerPreferences"
#define TARGET_SYMBOL "+[PLBatteryUIBackendModel getMaximumCapacity]"

// Find method offset by running nm on the binary (handles fat binaries, arm64e, chained fixups)
static uint64_t find_method_offset(void) {
    FILE *f = popen(
        "nm -arch arm64e '" PP_PATH "' 2>/dev/null"
        " | grep '\\+\\[PLBatteryUIBackendModel getMaximumCapacity\\]$'",
        "r"
    );
    if (!f) { perror("[!] popen nm"); return 0; }

    char line[512];
    uint64_t offset = 0;
    if (fgets(line, sizeof(line), f)) {
        uint64_t addr = 0;
        if (sscanf(line, "%llx", &addr) == 1 && addr > 0x100000000) {
            offset = addr - 0x100000000; // subtract standard __TEXT base
            fprintf(stderr, "[*] Found getMaximumCapacity at vmaddr=0x%llx offset=0x%llx\n",
                    addr, offset);
        }
    }
    pclose(f);

    if (offset == 0) fprintf(stderr, "[!] Symbol not found via nm\n");
    return offset;
}

static pid_t find_process(const char *name) {
    int pids[4096];
    int count = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    if (count <= 0) return 0;
    int n = count / (int)sizeof(int);
    for (int i = 0; i < n; i++) {
        if (pids[i] == 0) continue;
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], path, sizeof(path)) > 0) {
            char *base = strrchr(path, '/');
            if (base && strcmp(base + 1, name) == 0) return pids[i];
        }
    }
    return 0;
}

static mach_vm_address_t find_base(mach_port_t task) {
    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (kr != KERN_SUCCESS) return 0;

    vm_offset_t data = 0;
    mach_msg_type_number_t data_sz = 0;
    kr = mach_vm_read(task, dyld_info.all_image_info_addr,
                      sizeof(struct dyld_all_image_infos), &data, &data_sz);
    if (kr != KERN_SUCCESS) return 0;

    struct dyld_all_image_infos *aii = (struct dyld_all_image_infos *)data;
    mach_vm_address_t array_addr = (mach_vm_address_t)aii->infoArray;
    vm_deallocate(mach_task_self(), data, data_sz);
    if (array_addr == 0) return 0;

    kr = mach_vm_read(task, array_addr, sizeof(struct dyld_image_info), &data, &data_sz);
    if (kr != KERN_SUCCESS) return 0;

    struct dyld_image_info *img = (struct dyld_image_info *)data;
    mach_vm_address_t base = (mach_vm_address_t)img->imageLoadAddress;
    vm_deallocate(mach_task_self(), data, data_sz);
    return base;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        int pct = (argc > 1) ? atoi(argv[1]) : 65;
        if (pct < 1 || pct > 100) {
            fprintf(stderr, "Usage: %s [1-100]\n", argv[0]);
            return 1;
        }

        fprintf(stderr, "[*] batteryd (target: %d%%)\n", pct);

        // Find method offset dynamically from the binary on disk
        uint64_t method_offset = find_method_offset();
        if (method_offset == 0) {
            fprintf(stderr, "[!] Cannot find method offset. Exiting.\n");
            return 1;
        }

        // arm64: movz x0, #pct; ret
        uint32_t movz = 0xD2800000 | ((uint32_t)pct << 5);
        uint32_t ret_insn = 0xD65F03C0;
        uint8_t patch[8];
        memcpy(patch, &movz, 4);
        memcpy(patch + 4, &ret_insn, 4);

        fprintf(stderr, "[*] Watching for PowerPreferences...\n");

        pid_t last_pid = 0;

        while (1) {
            pid_t pid = find_process("PowerPreferences");

            if (pid > 0 && pid != last_pid) {
                fprintf(stderr, "[*] PowerPreferences PID %d\n", pid);
                kill(pid, SIGSTOP);
                usleep(50000);

                mach_port_t task;
                kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
                if (kr != KERN_SUCCESS) {
                    fprintf(stderr, "[!] task_for_pid: %s\n", mach_error_string(kr));
                    kill(pid, SIGCONT);
                    last_pid = pid;
                    continue;
                }

                mach_vm_address_t base = find_base(task);
                if (base == 0) {
                    fprintf(stderr, "[!] Could not find base address\n");
                    mach_port_deallocate(mach_task_self(), task);
                    kill(pid, SIGCONT);
                    last_pid = pid;
                    continue;
                }

                mach_vm_address_t target = base + method_offset;
                fprintf(stderr, "[*] Base=0x%llx Target=0x%llx\n", base, target);

                // Remap technique to patch code on Apple Silicon (W^X)
                mach_vm_size_t page_size = 0x4000;
                mach_vm_address_t page = target & ~(page_size - 1);
                mach_vm_offset_t offset_in_page = target - page;

                mach_vm_address_t tmp = 0;
                kr = mach_vm_allocate(task, &tmp, page_size, VM_FLAGS_ANYWHERE);
                if (kr != KERN_SUCCESS) {
                    fprintf(stderr, "[!] vm_allocate: %s\n", mach_error_string(kr));
                    mach_port_deallocate(mach_task_self(), task);
                    kill(pid, SIGCONT);
                    last_pid = pid;
                    continue;
                }

                kr = mach_vm_copy(task, page, page_size, tmp);
                if (kr == KERN_SUCCESS)
                    kr = mach_vm_write(task, tmp + offset_in_page, (vm_offset_t)patch, 8);

                if (kr == KERN_SUCCESS) {
                    vm_prot_t cur_prot, max_prot;
                    mach_vm_address_t remap_dest = page;
                    kr = mach_vm_remap(task, &remap_dest, page_size, 0,
                                       VM_FLAGS_OVERWRITE | VM_FLAGS_FIXED,
                                       task, tmp, TRUE,
                                       &cur_prot, &max_prot, VM_INHERIT_COPY);
                    if (kr == KERN_SUCCESS) {
                        kr = mach_vm_protect(task, remap_dest, page_size, FALSE,
                                             VM_PROT_READ | VM_PROT_EXECUTE);
                        if (kr == KERN_SUCCESS)
                            fprintf(stderr, "[+] Patched! Battery health -> %d%%\n", pct);
                        else
                            fprintf(stderr, "[!] vm_protect RX: %s\n", mach_error_string(kr));
                    } else {
                        fprintf(stderr, "[!] vm_remap: %s\n", mach_error_string(kr));
                    }
                } else {
                    fprintf(stderr, "[!] copy/write failed: %s\n", mach_error_string(kr));
                }

                mach_vm_deallocate(task, tmp, page_size);
                mach_port_deallocate(mach_task_self(), task);
                kill(pid, SIGCONT);
                last_pid = pid;
            } else if (pid == 0) {
                last_pid = 0;
            }
            usleep(50000);
        }
    }
    return 0;
}
