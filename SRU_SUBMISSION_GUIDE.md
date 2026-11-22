# SRU (Stable Release Update) Submission Guide — LP: #2117277 (Ubuntu 24.04 Noble)

## 1. Template Oficial de SRU (Para colar no comentário/descrição do Launchpad Bug #2117277)

Link do Bug: https://bugs.launchpad.net/ubuntu/+source/mutter/+bug/2117277

```text
[ Impact ]

On Ubuntu 24.04 LTS (Mutter 46.2) under Wayland, unplugging an external monitor (HDMI/DisplayPort) while the pointer rests on the disconnected display and windows are being placed or re-allocated triggers an immediate `gnome-shell` crash (`SIGSEGV` or `SIGABRT` assertion failure in `meta_window_get_work_area_for_logical_monitor`), terminating the entire user session and returning to GDM.

In Mutter 46 (`src/core/place.c`), `meta_backend_get_current_logical_monitor (backend)` is called in three places without checking for a `NULL` return value:
1. `find_next_cascade()` (line 158): passes `current` (`NULL`) directly to `meta_window_get_work_area_for_logical_monitor()`.
2. `meta_window_place()` centered path (line 896): passes `logical_monitor` (`NULL`) to `meta_window_get_work_area_for_logical_monitor()` and dereferences `logical_monitor->number`.
3. `meta_window_place()` origin/default path (line 939): when `!(window->has_maximize_func && window->decorated && !window->fullscreen)`, skips `meta_window_get_work_area_for_logical_monitor()` and directly dereferences `logical_monitor->rect.x` (offset `0x1c`), causing a fatal `SIGSEGV` (`mov 0x1c(%r12), %eax` with `%r12 = 0x0`).

While upstream commit `785a83ae3c4b39398bf8bf83519468941be44564` ("core/place: Guarantee we never get work area for a NULL logical monitor") fixed the single call site in Mutter 49+, Mutter 46 in Noble still contains all three unguarded call sites.

[ Test Plan ]

1. Boot Ubuntu 24.04 LTS (Wayland session) on a laptop with an external HDMI monitor connected in Join Displays (extended) mode.
2. Open multiple windows across both displays (including undecorated/CSD client windows and video playback) and keep `tiling-assistant@ubuntu.com` enabled.
3. Position the mouse cursor on the external HDMI monitor.
4. Unplug the HDMI cable while windows are active.
5. Verify that `gnome-shell` does not crash (instead logging `g_warn_if_fail` and cleanly falling back to `meta_monitor_manager_get_primary_logical_monitor()`), preserving the active Wayland session.

[ Where problems could occur ]

The patch only alters the code path in `src/core/place.c` where `meta_backend_get_current_logical_monitor()` returns `NULL` (which previously guaranteed an immediate crash via `g_assert (logical_monitor)` or a `NULL` pointer dereference on `logical_monitor->rect.x`).
In the fallback case, windows being placed during the hotplug race condition will be placed on the primary logical monitor (or keep their initial coordinates if no primary logical monitor exists yet). No normal window placement behavior is changed when a valid logical monitor is returned.

[ Other Info ]

Forensic disassembly from a production Noble crash dump (`libmutter-14-0` `46.2-1ubuntu0.24.04.18`, `/usr/bin/gnome-shell` `SIGSEGV`):
  f1d76: call 78f50 <meta_backend_get_current_logical_monitor@@Base>
  f1d7b: mov  %rax,%r12
  f1d7e: movzwl 0x2a0(%r15),%eax
  f1d86: not  %eax
  f1d88: test $0x420,%ax
  f1d8c: je   f237e
  f1d92: mov  0x1c(%r12),%eax  <-- SIGSEGV (%r12 == NULL, accessing logical_monitor->rect.x)
```

---

## 2. Como Submeter no Launchpad (2 Opções Oficiais)

### Opção A: Anexar o `.debdiff` direto no Bug #2117277 (Mais rápido para chamar o `ubuntu-sponsors`)
1. Acesse: https://bugs.launchpad.net/ubuntu/+source/mutter/+bug/2117277
2. Cole o texto do template `[ Impact ] / [ Test Plan ] / [ Where problems could occur ]` acima na caixa de comentário.
3. Clique em **"Add attachment or patch"**:
   * Selecione o arquivo: `/home/joao/Documentos/Projetos/mutter-ubuntu-sru/mutter_46.2-1ubuntu0.24.04.20_lp2117277.debdiff`
   * Marque a checkbox **"This file is a patch (diff)"**.
4. No menu lateral direito do Launchpad, clique em **"Subscribe someone else"** e inscreva o time **`ubuntu-sponsors`** (isso coloca o seu patch na fila oficial de revisão e upload da Canonical para o `noble-proposed`).

### Opção B: Abrir um Merge Proposal (PR do Git no Launchpad)
1. Configure sua chave SSH (`~/.ssh/id_ed25519.pub`) na sua conta do Launchpad (`https://launchpad.net/~SEU-USUARIO/+editsshkeys`).
2. Dentro de `/home/joao/Documentos/Projetos/mutter-ubuntu-sru/mutter-noble`, envie sua branch para o seu namespace pessoal no Launchpad:
   ```bash
   git push git+ssh://SEU_USUARIO@git.launchpad.net/~SEU_USUARIO/ubuntu/+source/mutter lp2117277-noble-null-logical-monitor
   ```
3. Abra a URL da sua branch no Launchpad e clique em **"Propose for merging"**:
   * **Target repository:** `~ubuntu-desktop/ubuntu/+source/mutter` (ou `ubuntu/+source/mutter`)
   * **Target branch:** `ubuntu/noble-updates` (ou `ubuntu/noble-proposed`)
   * **Commit message / Description:** Cole o template de SRU acima.
