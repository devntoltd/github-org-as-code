# Code security configurations by repository visibility

Date: 2026-11-15
Status: approved

Builds on [github-org-bootstrap](2026-11-13-github-org-bootstrap-design.md), which gave the engine one code security
configuration for every repository (issue #7).

On GitHub Team, secret scanning, push protection and code scanning default setup are free for public repositories
but need paid licenses (Secret Protection, Code Security) for private and internal ones. A single configuration
applied to every repository can therefore hold only what is free everywhere, and public repositories go without
secret scanning. This decision gives the engine two configurations, one per visibility.

## Decision

- **Config format:** `codeSecurity` holds two required sections, `codeSecurity.private` (private and internal
  repositories, as GitHub's `private_and_internal`) and `codeSecurity.public`, each with `name`, `description`
  (nullable), `enforcement` and `settings`. Both are required, also in an organization without public repositories:
  the public one covers the public repositories created later. This is a major change of `configVersion` (`2.0`):
  a config moves its `codeSecurity` fields into `codeSecurity.private`, drops `default_for_new_repos` and adds
  `codeSecurity.public`; the changelog's **Config format** section says so.
- **Defaults for new repositories are fixed by the engine:** `private` is the default for `private_and_internal`,
  `public` for `public`. `default_for_new_repos` leaves the config, so the two cannot claim the same repositories,
  and "no default" is no longer possible: covering new repositories is the point of the section.
- **Settings:** both sections have the same rows: the existing `dependency_graph`, `dependabot_alerts`,
  `dependabot_security_updates`, `private_vulnerability_reporting`, and new `secret_scanning`,
  `secret_scanning_push_protection` and `code_scanning_default_setup` (`enabled`, `disabled`, `not_set`). Only the
  recommendations differ: `enabled` for the new rows in `public` (free there), `disabled` in `private` (paid there,
  and kept off explicitly; an organization with the licenses enables them without a new format). The existing rows keep their recommendations in
  both.
- **Names:** the two `name`s must differ, compared without case (GitHub keeps configuration names unique whatever
  their case); a config error otherwise. Each is matched exactly against the organization configurations, with the
  case and built-in/enterprise name errors of today, worded with the field path of its section.
- **Attach without switching:** each configuration is attached only to the non-archived repositories of its
  visibility that have no configuration (`private` and `internal` for `private`, `public` for `public`), with scope
  `selected` and their repository ids: `all_without_configurations` would attach `private` to public repositories
  too, and scopes `public`/`private_or_internal` would switch repositories already on a configuration. The engine
  never moves a repository from one configuration to another, its own two included. The repository list read once
  per run (`Read-OrgRepository`) gains `Id`.
- **Warnings:** a repository on the configuration of the other visibility (one whose visibility changed, or attached
  before this format) is a warning that names the configuration it should be on and the page to apply it; a
  repository on a configuration that is neither is the warning of today, naming the configuration of its visibility.
  The failed and not-in-effect warnings stay per repository, naming the configuration it is on.
- **Actions:** the existing four actions per configuration, `private` first, then `public`:
  `CreateCodeSecurityConfiguration`, `UpdateCodeSecurityConfiguration`, `SetCodeSecurityDefault`,
  `AttachCodeSecurityConfiguration`, each with `Target` the configuration's name. The id a create returns fills only
  the endpoints of the later actions of the same configuration.
- **State:** `CodeSecurity` becomes `{Private, Public, Repositories, SkippedRepositories}`, where `Private` and
  `Public` are each `{Configuration, Default}` as read today, and `OtherDefaults` (the defaults of configurations
  that are neither) stays beside them. The repository entries are read once for both, as today, and gain `Id` and
  `Visibility` (from `Read-OrgRepository`), which the plan needs to choose the configuration and to send the ids.
- **Release:** the version that brings this format is released only after a maintainer's run on a real
  organization has checked the product dependencies below.

## Approaches considered

- **An optional `codeSecurity.public`** next to today's fields: no change for existing configs (minor
  `configVersion`), but a rule between fields (`default_for_new_repos` of the main one must not be `all` or
  `public`) and two shapes of the section. Rejected by the owner: both visibilities are always configured, whether
  the organization has public repositories yet or not.
- **A list `codeSecurity.configurations[]`** with a visibility per entry: general, but more code and validation
  (coverage, overlap) for exactly two cases GitHub's own defaults already name.
- **A top-level `publicCodeSecurity`:** the same as the optional section, with the two halves of one settings page
  apart in the config.
- **Switching public repositories from the main configuration to the public one:** gives existing public
  repositories secret scanning on the first run, but breaks "never switches a configuration". Rejected by the owner:
  existing repositories get a warning and are moved by hand.

## Left to the implementation

- Whether `secret_scanning`/`secret_scanning_push_protection` need `secret_protection` (and
  `code_scanning_default_setup` needs `code_security`) set in the same configuration: GitHub's reference names
  those fields and answers 400 or 422 on a missing product or dependency, without listing the pairs. Verify on a real
  organization (a maintainer's run against a test configuration) before the release; if they are needed, they are
  rows of both sections like the others, with the same recommendations.
- How the create's id reaches the endpoints of its own configuration (a token per section, for example).
- Chunking of `selected_repository_ids` if GitHub limits it (the reference documents 250 only for detach).

## Not in scope

Paid features beyond the three rows (validity checks, non-provider patterns, generic secrets, delegated bypass and
dismissal), enterprise configurations, and moving repositories between configurations.
