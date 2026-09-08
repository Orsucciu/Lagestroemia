# Setup notes for future AI sessions

These are the manual one-time setup steps that this AI session had to do
on the host machine to make `flutter build linux` work. Future sessions
inheriting the same workspace should not need to repeat them, but if the
workspace is wiped, here is what to redo.

## TL;DR

```sh
# 1. Flutter SDK
mkdir -p ~/.local/opt && cd ~/.local/opt
wget -q https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.4-stable.tar.xz -O flutter.tar.xz
tar xf flutter.tar.xz && rm flutter.tar.xz
echo 'export PATH="$HOME/.local/opt/flutter/bin:$PATH"' >> ~/.bashrc

# 2. cmake + ninja
pip install --user --break-system-packages cmake ninja
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# 3. clang (minimal extract — see PROGRESS.md for the full story)
# 4. sysroot from .deb files (see PROGRESS.md)
# 5. PKG_CONFIG_PATH + LD_LIBRARY_PATH (see ~/.bashrc)

source ~/.bashrc
flutter doctor
```

## What already exists in this workspace

- `~/.local/opt/flutter` — Flutter 3.27.4 stable
- `~/.local/opt/clang` — clang 18.1.8 (minimal extract, with
  libtinfo.so.5 from a downloaded deb)
- `~/.local/opt/sysroot` — GTK3 + deps dev headers + a few runtime
  libs (libsecret-1)
- `~/.local/opt/pkgconfig-overrides` — stubs for `cloudproviders`,
  `atspi-2`, `dbus-1`
- `~/.bashrc` has the right env vars

## What to do if `flutter build linux` fails

1. `clang++: error: ... cannot find -lgtk-3` — recreate `.so` symlinks
   in the sysroot:
   ```sh
   for lib in gtk-3 gdk-3 atk-1.0; do
     src=$(find /usr/lib/x86_64-linux-gnu -maxdepth 1 -name "lib${lib}.so.0*" | head -1)
     [ -n "$src" ] && ln -sf "$src" ~/.local/opt/sysroot/usr/lib/x86_64-linux-gnu/lib${lib}.so
   done
   ```

2. `fatal error: 'stdlib.h' file not found` — make sure
   `C_INCLUDE_PATH` / `CPLUS_INCLUDE_PATH` / `LIBRARY_PATH` are NOT
   exported. When set, clang stops adding its default system include
   search paths, and `cstdlib:79: #include_next <stdlib.h>` fails
   because `/usr/include/stdlib.h` is no longer in the search list.

3. `cannot find -lsecret-1` — install the libsecret-1-0 runtime into
   the sysroot (see PROGRESS.md for the wget URL).

## What to do if `flutter pub get` fails

Check that you `cd` into `/home/z/my-project/lagestroemia` before
running pub get — the persistent shell keeps cwd between commands.

## Where the project lives

- Repo: `/home/z/my-project/lagestroemia`
- Remote: `https://github.com/Orsucciu/Lagestroemia`
- Branch: `main`

## Authenticating to GitHub

The PAT provided by the user is in the original task brief. The PAT
has these scopes: `repo` (read+write) and `read:org`. **It does NOT
have the `workflow` scope**, so commits that touch
`.github/workflows/*.yml` will be rejected by GitHub. Workflow files
are kept under `docs/workflows/` until a workflow-scoped PAT is
available — see `docs/workflows/README.md` for instructions.
