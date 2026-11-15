# Security policy

## Reporting a vulnerability

Report a vulnerability privately at
<https://github.com/devntoltd/github-org-as-code/security/advisories/new> (the **Security** tab of this
repository, *Report a vulnerability*): it opens a draft advisory that only you, the repository's admins and the
organization's security managers see. Please do not open a public issue for it.

Include what is affected, how to reproduce it and what an attacker could do. Examples of what counts: a run that
changes more than its plan shows or than the config says, a run with `-WhatIf` that changes anything, a token or
secret written to the output or to a file, a way for a config or a GitHub response to run code, a way for `run.ps1` to
run anything but the pinned commit of the engine, or a way around the confirmation.

## What happens next

- Within 7 days: the maintainers acknowledge the report, and say what they need to reproduce it if anything is
  missing.
- Within 90 days of the report: a fixed release, and the advisory published with it (coordinated disclosure). If a fix
  needs longer, the maintainers agree a date with you; the advisory credits you unless you prefer not to be named.
- A report the maintainers find not to be a vulnerability is closed with the reason, in the draft advisory.

## Supported versions

Only the latest release gets fixes. The tool runs with an organization owner's token, so keep your pinned version
current: the published advisories of this repository (the **Security** tab) name the release that fixes each one.
