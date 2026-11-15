# Changelog

All notable changes are listed here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A release that changes the config format has a
**Config format** section with the edit a config needs; a release without one reads the configs of the previous
release unchanged.

## [Unreleased]

### Changed

- The repository is renamed from `devntoltd/github-org-bootstrap` to `devntoltd/github-org-as-code`, and the first
  line of every run and the schema title carry the new name. GitHub redirects the old URLs; set `Repository` of
  `engine.psd1` to `devntoltd/github-org-as-code` with the next upgrade.
- The description of `actions.selected.patterns_allowed` in the schema gives `example-owner/example-action@*` as its
  example instead of a real vendor's action.

## [2.0.0] - 2026-11-15

### Config format

- `configVersion` `2.0`: move the fields of `codeSecurity` into `codeSecurity.private` and drop
  `default_for_new_repos` (the engine makes that configuration the default for new private and internal
  repositories); add `codeSecurity.public` with `name`, `description`, `enforcement` and `settings`, and the
  `settings` `advanced_security`, `secret_scanning`, `secret_scanning_push_protection` and
  `code_scanning_default_setup` to both sections (a feature `enabled` needs `advanced_security` `enabled`),
  as in `engine/examples/github.json`. The two names must differ, also ignoring case. `engine/examples/run.ps1` is
  unchanged since 1.1.0: raise `Tag` and `Commit` and edit `github.json` in one pull request.

### Changed

- The engine keeps two code security configurations: `codeSecurity.private` for private and internal repositories
  and `codeSecurity.public` for public ones, where secret scanning, push protection and code scanning default setup
  are free. Each is the default for new repositories of its visibility and is attached only to the repositories of
  its visibility without a configuration. A public repository already on the private configuration keeps it and
  gets a warning: apply the public one on the security products page if you want it. The engine still never
  switches a repository's configuration.
- When gh is missing or older than the minimum, the error names how to install or update it on Windows (winget),
  macOS (Homebrew) and Linux (GitHub's package repository), instead of the winget command alone; the engine
  reference shows the install commands of each.

## [1.1.0] - 2026-11-14

### Added

- `engine/examples/run.ps1` warns, after the engine's output (also when the engine fails), when it differs from the
  wrapper of the engine it pins, with the file to copy over it: raising `Tag` and `Commit` never updates the copy in a
  config repository. Line endings, newlines at the end and a signature block do not count, and the run goes on either
  way. Copy this release's `run.ps1` once, in the same change that raises `Tag` and `Commit` to `v1.1.0`: with an
  older pin, the new copy would be told to make way for the older wrapper. Later wrappers then announce themselves.

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

[Unreleased]: https://github.com/devntoltd/github-org-as-code/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/devntoltd/github-org-as-code/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/devntoltd/github-org-as-code/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/devntoltd/github-org-as-code/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/devntoltd/github-org-as-code/releases/tag/v1.0.0
