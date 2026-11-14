<#
.SYNOPSIS
Publishes the GitHub Release of ModuleVersion of engine/GitHubOrg.psd1 when it has none, and prints the status.
.DESCRIPTION
The release is vX.Y.Z at the commit checked out (HEAD), from which the manifest and the changelog are read, so the
script stops when either differs from it: title vX.Y.Z, the notes of the section ## [X.Y.Z] of CHANGELOG.md, never a
draft, Latest unless a published release has a higher version; gh release create also creates the tag when it is
missing. A version that has its release already is left alone, so every push to main runs this and only the merge of a
release pull request publishes: the release belongs to the commit that raised ModuleVersion (its first parent has
another ModuleVersion), and a run of any other commit leaves it to that commit's run, however the runs are ordered.

The repository has immutable releases: a published release and its tag never change afterwards. So the script stops
before any write when the changelog has no entries for the version, when the tag is at another commit, or when a draft
release of the tag exists. A tag at the commit without a release (a run that stopped in between) gets its release.

The job release of .github/workflows/ci.yml runs it on the commit of the run after every check passed (decision
docs/decisions/2026-11-14-release-workflow.md). Uses gh, signed in (GH_TOKEN in Actions) and pointed at the repository
(GH_REPO in Actions, the git remote of the current directory otherwise).
.EXAMPLE
./tools/Publish-Release.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The manifest whose ModuleVersion is the version of the release.
    [string]$ManifestPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'engine/GitHubOrg.psd1'),
    # The changelog with the section of the version.
    [string]$ChangelogPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'CHANGELOG.md'),
    # The module that pins the REST API version the gh api calls send.
    [string]$ModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'shared/GitHubOrg.Common.psm1')
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

function Invoke-Git {
    # Runs git in the folder of the manifest and throws on a failure; returns its output.
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & git -C (Split-Path -Path (Resolve-Path -Path $ManifestPath) -Parent) @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments[0]) failed with exit code $LASTEXITCODE."
    }
    $output
}

# The release points at HEAD, and its version and notes come from the files: they must be those of HEAD.
$Commit = [string](Invoke-Git -Arguments @('rev-parse', '--verify', '--quiet', 'HEAD^{commit}'))
& git -C (Split-Path -Path (Resolve-Path -Path $ManifestPath) -Parent) diff --quiet HEAD -- (Resolve-Path -Path $ManifestPath) (Resolve-Path -Path $ChangelogPath)
if ($LASTEXITCODE -ne 0) {
    throw "$(Split-Path -Path $ManifestPath -Leaf) or $(Split-Path -Path $ChangelogPath -Leaf) differ from the commit checked out ($Commit); release from a clean checkout of the commit."
}

$version = [string](Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion
$tag = "v$version"

# The notes: the lines under '## [X.Y.Z]' up to the next heading of that level, without the link definitions that end
# the file. A section needs an entry, a line that is not a heading.
$notes = [System.Collections.Generic.List[string]]::new()
$inSection = $false
foreach ($line in Get-Content -Path $ChangelogPath) {
    if ($line -match '^## ') {
        if ($inSection) { break }
        $inSection = $line -match ('^## \[' + [regex]::Escape($version) + '\]')
        continue
    }
    if ($inSection) {
        $notes.Add($line)
    }
}
while ($notes.Count -gt 0 -and ($notes[-1] -match '^\s*$' -or $notes[-1] -match '^\[[^\]]+\]: ')) {
    $notes.RemoveAt($notes.Count - 1)
}
$notesText = ($notes -join "`n").Trim()
if (-not ($notes | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })) {
    throw "$(Split-Path -Path $ChangelogPath -Leaf) has no entries under ## [$version]: move the entries of the release under it first."
}

$pinned = Get-PinnedGitHubApiVersion -Path $ModulePath
$header = @('--header', "X-GitHub-Api-Version: $pinned")

# A published release: every commit of main after the release pull request, the tag at an earlier commit.
$releases = @(Invoke-Gh release list --json 'tagName,isDraft' --limit 1000 | ConvertFrom-Json)
$release = $releases | Where-Object { $_.tagName -ceq $tag } | Select-Object -First 1
if ($release -and $release.isDraft) {
    throw "A draft release $tag exists; publish or delete it by hand, then run this again."
}

# The release belongs to the commit that raised ModuleVersion against its first parent: the merge of the release pull
# request. A run of a later commit without a release leaves it to the run of that commit, however the runs are ordered.
$raises = $false
if (-not $release) {
    $parentManifest = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "$([guid]::NewGuid()).psd1"
    try {
        # A temporary local file, read back below: written under -WhatIf too.
        Invoke-Git -Arguments @('show', "$Commit^1:./$(Split-Path -Path $ManifestPath -Leaf)") | Set-Content -Path $parentManifest -WhatIf:$false
        $raises = [string](Import-PowerShellDataFile -Path $parentManifest).ModuleVersion -ne $version
    }
    finally {
        Remove-Item -LiteralPath $parentManifest -ErrorAction Ignore
    }
}

if ($raises) {
    # A tag without a release must be at this commit, peeled when it is annotated. matching-refs lists every tag the
    # name starts, so only the exact ref counts.
    $ref = @(Invoke-Gh api @header "repos/{owner}/{repo}/git/matching-refs/tags/$tag" | ConvertFrom-Json) |
        Where-Object { $_.ref -ceq "refs/tags/$tag" } | Select-Object -First 1
    if ($ref) {
        $tagCommit = [string]$ref.object.sha
        if ($ref.object.type -eq 'tag') {
            $tagCommit = [string](Invoke-Gh api @header "repos/{owner}/{repo}/git/tags/$tagCommit" | ConvertFrom-Json).object.sha
        }
        if ($tagCommit -cne $Commit) {
            throw "Tag $tag is at $tagCommit, not at $Commit, the commit of this run, and has no release; move the tag or raise ModuleVersion."
        }
    }
}

# Latest unless a published release has a higher version (a release of a lower version that publishes after it).
$higher = @($releases | Where-Object { -not $_.isDraft -and $_.tagName -match '^v(\d+\.\d+\.\d+)$' -and [version]$Matches[1] -gt [version]$version })
$latest = if ($higher) { '--latest=false' } else { '--latest' }

$status = if ($release) {
    'released'
}
elseif (-not $raises) {
    # Visible in the annotations of every later run until someone acts: re-run the jobs of the release commit's run, or
    # raise the version again when that commit fails its checks for good.
    Write-Host "::warning::Release $tag is not published: only the run of the commit that raised ModuleVersion to $version publishes it. Re-run the jobs of that run, or raise the version again."
    'waits for the commit that raised it'
}
elseif ($PSCmdlet.ShouldProcess("$tag at $Commit", 'gh release create')) {
    Invoke-Gh release create $tag --target $Commit --title $tag --notes $notesText $latest | Out-Null
    'published'
}
else {
    'new'
}

Write-Host "Release ${tag}: $status"
Add-StepSummary -Line '## Release', '', '| Version | Tag | Release |', '|---|---|---|', "| $version | $tag | $status |"
