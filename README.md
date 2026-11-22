# Ubuntu 24.04 Mutter Wayland HDMI Hotplug Crash Fix (LP: #2117277)

Forensic root-cause analysis, Ubuntu 24.04 LTS (*Noble Numbat*) **SRU (Stable Release Update) C backport patch** for `mutter` (`46.2`), and local mitigation script for the `gnome-shell` (`libmutter-14.so.0`) `SIGSEGV` / `SIGABRT` crash when unplugging an external HDMI/DisplayPort monitor under Wayland.

- **Launchpad Bug:** [LP: #2117277](https://bugs.launchpad.net/ubuntu/+source/mutter/+bug/2117277)
- **Upstream GNOME Reference:** [GNOME/mutter!4549](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/4549) (`commit 785a83ae3c4b39398bf8bf83519468941be44564`)
- **Affected Package:** `mutter` / `libmutter-14-0` (`<= 46.2-1ubuntu0.24.04.19`) on Ubuntu 24.04 LTS

---

## 1. Root Cause & Forensic Disassembly

When unplugging an external monitor under Wayland while multiple windows are open and the mouse pointer rests on the external display:

1. **Kernel `i915` Hotplug Delay:** On Intel integrated GPUs (e.g., Tiger Lake / Iris Xe), Panel Self-Refresh (PSR) and EDID transitions can stall the hotplug workqueue:
   ```text
   kernel: workqueue: i915_hotplug_work_func [i915] hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND
   ```
2. **Orphaned Pointer Coordinates:** The external `MetaLogicalMonitor` is removed from `monitor_manager->logical_monitors`, while pointer coordinates momentarily remain outside the remaining monitor's bounding box. Consequently, `meta_backend_get_current_logical_monitor(backend)` returns **`NULL`**.
3. **Unguarded `NULL` Dereference in `src/core/place.c`:** While windows are being re-placed or cascaded across monitors (heavily triggered by `tiling-assistant@ubuntu.com`), Mutter 46 calls `meta_backend_get_current_logical_monitor(backend)` at **three call sites** in `src/core/place.c` (lines 158, 896, and 939) without checking for `NULL`.

### GDB & `objdump` Evidence (`libmutter-14-0` `46.2-1ubuntu0.24.04.18`)

From `/var/crash/_usr_bin_gnome-shell.1000.crash` (`Signal 11 / SIGSEGV` at offset `0xf1d92` in `libmutter-14.so.0.0.0`):

```x86asm
   f1d73: 4c 89 e7             mov    %r12,%rdi
   f1d76: e8 d5 71 f8 ff       call   78f50 <meta_backend_get_current_logical_monitor@@Base>
   f1d7b: 49 89 c4             mov    %rax,%r12          ; %r12 = logical_monitor (0x0 / NULL)
   f1d7e: 41 0f b7 87 a0 02 00 movzwl 0x2a0(%r15),%eax
   f1d85: 00 
   f1d86: f7 d0                not    %eax
   f1d88: 66 a9 20 04          test   $0x420,%ax         ; window->has_maximize_func && window->decorated
   f1d8c: 0f 84 ec 05 00 00    je     f237e
   f1d92: 41 8b 44 24 1c       mov    0x1c(%r12),%eax    ; <-- SIGSEGV! Reads logical_monitor->rect.x (0x1c) from NULL
```

In `src/core/place.c`:
- If `window->has_maximize_func && window->decorated && !window->fullscreen` is **true**, it calls `meta_window_get_work_area_for_logical_monitor(window, NULL, &workarea)` and crashes with `SIGABRT` (`assertion failed: (logical_monitor)`).
- If **false** (e.g., CSD/undecorated client windows), it immediately executes `x = logical_monitor->rect.x;` at offset `0x1c` of `NULL`, crashing with **`SIGSEGV`** and killing the entire Wayland session.

---

## 2. The C Backport Patch for Ubuntu 24.04 (`mutter 46.2`)

Upstream commit `785a83ae` only patched a single call site in Mutter 49 (`main`). In Mutter 46.2, `src/core/place.c` has **three** unguarded call sites (`find_next_cascade` at line 158, centered placement at line 896, and default placement at line 939).

Our backport patch ([`patches/core-place-Guarantee-we-never-get-work-area-for-a-NULL-lo.patch`](patches/core-place-Guarantee-we-never-get-work-area-for-a-NULL-lo.patch) and [`patches/mutter_46.2-1ubuntu0.24.04.20_lp2117277.debdiff`](patches/mutter_46.2-1ubuntu0.24.04.20_lp2117277.debdiff)) guards all three locations by falling back to `meta_monitor_manager_get_primary_logical_monitor(monitor_manager)` or returning cleanly if no logical monitor is active.

---

## 3. Immediate Local Mitigation (No Recompile Required)

If you are experiencing this crash on Ubuntu 24.04 LTS right now, run the included mitigation script to eliminate the `tiling-assistant` placement storm and optionally disable Intel `i915` Panel Self-Refresh (PSR) hotplug stalls:

```bash
git clone https://github.com/jpferraz-git/ubuntu-mutter-wayland-hotplug-fix.git
cd ubuntu-mutter-wayland-hotplug-fix
./mitigate-hotplug-crash.sh
```

## License

MIT
