# Developer tools from pinned release files

Date: 2026-11-14
Status: implemented

`tools/Install-DevTools.ps1` installed the command-line tools of the checks (actionlint, Betterleaks,
editorconfig-checker, lychee, shellcheck, zizmor) through winget only: on Linux and macOS it listed what to install,
and on Windows it installed them globally, on a `PATH` that only new terminals see (issue #4). CI already downloads
the same tools as pinned release files with their SHA-256. This decision gives contributors on every platform that
setup.

## Decision

- **Source:** each tool's GitHub release at the version `dev-tools.psd1` pins: the release file of the platform,
  checked against the SHA-256 that `dev-tools.psd1` holds for that file before anything is extracted. A file whose
  hash differs stops the install; nothing is taken from the GitHub API at install time, so a release file replaced
  on GitHub is caught, as in CI. winget is no longer used, on Windows either: one path for every platform.
- **Platforms:** `windows-x64`, `linux-x64`, `linux-arm64`, `macos-x64`, `macos-arm64`, chosen from the running
  system. Windows on arm64 takes the x64 files, which it runs through emulation. Another platform stops with the list
  of the supported ones.
- **Data:** per tool in `dev-tools.psd1`: `Version`, `Repository`, the release `Tag` and, per platform, the file
  `Name` and its `Sha256`. A test keeps the `linux-x64` hashes equal to the `SHA256` of the matching `ci.yml` steps,
  as it keeps the versions equal today. `WinGetId` goes.
- **Where:** `.tools/bin/` in the repository (git-ignored), never a global location. The executable named after the
  command (`<command>` or `<command>.exe`) is taken from the archive wherever it sits in it. A tool counts as installed
  when `.tools/bin/` holds it and it reports the pinned version; otherwise it is installed again.
- **`PATH`:** `build.ps1` puts `.tools/bin/` first on `PATH` for the checks it runs, so `./build.ps1 <check>` and
  the VS Code tasks use the pinned tools whatever else is installed; the pre-commit hook prefers
  `.tools/bin/betterleaks`. Running a tool by hand outside `build.ps1` needs `.tools/bin/` on `PATH`, which
  CONTRIBUTING says.
- **Raising a version:** `tools/Update-DevTool.ps1 -Name <tool> -Version <version>` reads the release files of the new
  version from GitHub, matches each platform's file by the name pattern of the current version, and writes the
  version, tag, names and hashes into `dev-tools.psd1` for review in the pull request; the `ci.yml` step is raised in
  the same pull request, as today (a test fails while they differ). The weekly dependency check still opens the
  issue.

## Not in scope

CI on Windows or macOS (decided against); the PowerShell modules, which `Install-PSResource` keeps installing as
before; tools of other platforms than the five above.
