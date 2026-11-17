---
name: "Dependency update review"
about: Review module and tool versions newer than the lock, then raise the lock or stay.
title: "Review dependency updates"
labels: [dependency-update, enhancement]
assignees: [rodchenkov]
---

Opened by `tools/Invoke-DependencyUpdateCheck.ps1` (weekly workflow `.github/workflows/recurring.yml`) for the versions above, each published at least 7 days ago; the workflow updates this issue while it is open. The locked versions are in `dev-tools.psd1` (modules and command-line tools of the checks) and `modules.lock.psd1` (runtime modules of the engine, none now).

## Steps

- [ ] Read the release notes of each version above
- [ ] Raise the version in `modules.lock.psd1` or `dev-tools.psd1`; a command-line tool with `./tools/Update-DevTool.ps1 -Name <tool> -Version <version>` (its files and SHA-256 of every platform), and also `VERSION` and `SHA256` of its step in `.github/workflows/ci.yml`
- [ ] Install it with `./tools/Install-DevTools.ps1` (the signature is checked on Windows) and run `./build.ps1 all`

Close this issue with the pull request that raises the versions, or without one to stay on the locked versions; the check does not read whether it was closed as completed or not planned. While a closed issue lists every version above, no other issue opens; a newer version, or one that leaves quarantine, opens a new one.
