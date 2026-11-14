# Changelog

All notable changes are listed here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A release that changes the config format has a
**Config format** section with the edit a config needs; a release without one reads the configs of the previous
release unchanged.

## [Unreleased]

### Added

- `engine/examples/run.ps1` warns when it differs from the wrapper of the engine it pins (line endings apart), with the
  file to copy over it: raising `Tag` and `Commit` never updated the copy in a config repository. Copy this release's
  `run.ps1` once to get the warning; later wrappers then announce themselves.

## [1.0.1] - 2026-11-14

### Changed

- `engine/examples/run.ps1` stops when `.engine/` has local changes (an edited or added file), instead of running
  them, or deleting them when the pin changed; remove `.engine/` to check out the pinned engine again. It also stops,
  instead of deleting it, when `.engine/` is not a checkout of the engine and holds other files than `.git`. A config
  repository gets this by copying the new `engine/examples/run.ps1` over its own: raising `Tag` and `Commit` alone
  keeps the old wrapper.
- `engine/bootstrap.ps1` without `-ConfigPath` stops with an error that names the parameter and
  `engine/examples/github.json`, instead of PowerShell's prompt for the value.
- The `Manual:` line of a run says to rerun with `-WhatIf -ManualChecklist`, which holds however the engine was
  started (`./run.ps1` included), instead of naming `./engine/bootstrap.ps1`.

## [1.0.0] - 2026-11-13

### Added

- The first public release of the engine: organization settings, Actions policies, code security, the organization
  ruleset, budgets, Copilot settings and seats, the inventory, the manual checklist and the settings page walk.
- `engine/examples/run.ps1` and `engine.psd1` to run a pinned release against a config kept in another repository.

### Config format

`1.0`: the first format. A config sets `"configVersion": "1.0"`.

[Unreleased]: https://github.com/devntoltd/github-org-bootstrap/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/devntoltd/github-org-bootstrap/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/devntoltd/github-org-bootstrap/releases/tag/v1.0.0
