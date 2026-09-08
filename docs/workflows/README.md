# GitHub Actions workflows

These workflow files are *not* installed under `.github/workflows/`
because the PAT used to commit the initial MVP did not have the
`workflow` scope, so GitHub refused to accept commits touching that
directory.

To activate the workflows, copy them into place:

```sh
cd /path/to/Lagestroemia
mkdir -p .github/workflows
cp docs/workflows/*.yml .github/workflows/
git add .github/workflows/
git commit -m "ci: install GitHub Actions workflows"
git push
```

(Or just commit + push from an account that has the `workflow` scope
on its PAT.)

## Files

- `ci.yml`             — runs `flutter analyze` + `flutter test` on every
  push / PR. No artifact upload.
- `build-linux.yml`    — builds the Linux desktop bundle and uploads it
  as a build artifact + (on tag push) as a release asset.
- `build-windows.yml` — same for Windows.
- `build-android.yml`  — same for Android (split-per-ABI APKs).
- `build-web.yml`      — builds the Web WASM bundle and (on push to
  `main`) deploys it to GitHub Pages.
