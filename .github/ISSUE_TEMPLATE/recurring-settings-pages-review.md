---
name: "Recurring: Settings pages review"
about: Walk the settings pages of the GitHub organization against engine/settings.md.
title: "[Recurring] Review the GitHub organization settings pages"
labels: [recurring, "recurring:settings-pages-review"]
assignees: [rodchenkov]
---

Why: the pages have no API, so a page or control that GitHub adds or moves is found only by a person. The values of an organization's settings, the manual ones included, are checked in its config repository (`./run.ps1 -WhatIf -PageWalk`), not here. Details: [settings reference](https://github.com/devntoltd/github-org-as-code/blob/main/engine/settings.md)

- [ ] Compare the settings menu of `https://github.com/organizations/<org>/settings/` with the pages of `engine/settings.md` (UI coverage, in menu order): a page in the menu and not in the file is new or was missed; a page in the file and not in the menu was removed or renamed.
- [ ] Open each page and compare its controls with its section of `engine/settings.md`: a control that is neither a row nor a "not managed" entry is new.
- [ ] Each finding is a pull request: a page in `$script:SettingPages`, a row of `$script:SettingDefinitions` with its key in `engine/examples/github.json`, or an `Unmanaged` entry with the reason.
- [ ] For each page compared, in one pull request: fix the rows and the `Order` of a page whose controls moved or were renamed, and set its `ReviewedOn` in `engine/src/Config.Catalog.ps1` to the day of the review.
- [ ] Comment on this issue: the findings and their pull requests, or "no change".

A closed issue records that the pages were compared with `engine/settings.md` on that date; it says nothing about the value of any setting of an organization.

Close as **completed** with that comment; the closing date starts the next interval. Close as **not planned** if it was not done.
