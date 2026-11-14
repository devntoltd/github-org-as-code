# Release workflow

Date: 2026-11-14
Status: implemented

Builds on [github-org-bootstrap](2026-11-13-github-org-bootstrap-design.md): configs run a pinned release, a tag
`vX.Y.Z` and its commit. Until now the maintainer made each release by hand after merging the release pull request: a
tag on `main` and a GitHub Release with the section of `CHANGELOG.md`.

## Decision

The merge of the release pull request is the last manual step. The pull request stays what it was: it moves the
`[Unreleased]` entries of `CHANGELOG.md` under `## [X.Y.Z] - <date>` and raises `ModuleVersion` of
`engine/GitHubOrg.psd1` to `X.Y.Z` (a test keeps the two equal). After the merge, CI tags the merge commit and
publishes the release.

- **Where:** a job `release` at the end of `ci.yml`, on runs of `main` that are not pull requests (the push of the
  merge; re-running the jobs of its run retries), after every other job of the same run passed (a test keeps `needs`
  equal to the other jobs). A commit whose checks fail is never tagged. A separate workflow on `workflow_run` was the
  alternative; it is harder to follow and zizmor reports that trigger as dangerous.
- **Which commit:** only a commit of `main` whose first parent has another `ModuleVersion`, the merge of the release
  pull request, publishes; the job checks out that commit and its parent (`fetch-depth: 2`). Runs of `main` can finish
  out of order, and GitHub replaces a pending run with a newer one in the same concurrency group, so a later commit
  would otherwise take the place of the release merge for good. For the same reason every run of `main` has a
  concurrency group of its own commit. A later run without the release publishes nothing and warns in its annotations;
  when the release commit fails a check for good, the fix raises the version again.
- **What:** `tools/Publish-Release.ps1` reads `ModuleVersion`. Without a release `vX.Y.Z` it publishes one at the
  commit of the run: title `vX.Y.Z`, the body of the changelog section without the link definitions that end the file,
  never a draft, marked Latest unless a published release has a higher version.
- **Rights:** only that job has `contents: write`; the workflow and every other job keep `contents: read`.
- **Checks before writing:** the repository has immutable releases (enforced by the organization), so a published
  release, its notes and its tag cannot be changed or moved afterwards. The script stops before any write when the
  changelog has no section for the version or the section has no entry (only headings), when a tag `vX.Y.Z` without a
  release exists at another commit, or when a draft release of the tag exists. A tag at the same commit without a
  release (a run that stopped between the two) gets its release. A published release is never checked against the
  commit: after it, every commit of `main` has the same `ModuleVersion` and an earlier tag. Since the notes cannot be
  fixed either, `CHANGELOG.md` links only to absolute URLs (a test): a relative link breaks on the release page.
- **The tag:** `gh release create --target` creates a lightweight tag. v1.0.0 has an annotated one;
  `engine/examples/run.ps1` reads both (it peels an annotated tag), so a config repository sees no difference.

## Not in scope

Release assets (configs check out the tagged commit), signed tags, and a check of the release pull request itself
beyond the tests that already keep the changelog and `ModuleVersion` equal.
