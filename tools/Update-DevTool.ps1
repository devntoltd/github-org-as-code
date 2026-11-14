<#
.SYNOPSIS
Checks the pinned release files of the developer tools in dev-tools.psd1 against GitHub, or raises one tool to a new
version.
.DESCRIPTION
Without -Name: reads the release of every tool at its pinned Tag and compares, for every platform, the file Name and
Sha256 of dev-tools.psd1 with the release's file of that name and its digest; prints them and throws when one differs
or is missing (a release file replaced on GitHub, or a mistyped pin).

With -Name and -Version: the new release's tag and file names are those of the current version with the version
replaced; their digests become the new Sha256. Every platform must have its file before anything is written, so a
file the upstream renamed stops the raise, naming the platform and the name it looked for. The step of the tool in
.github/workflows/ci.yml is raised in the same pull request (a test fails while the two differ). See
docs/decisions/2026-11-14-dev-tools-download.md.

Uses gh, signed in and able to read public repositories.
.EXAMPLE
./tools/Update-DevTool.ps1
.EXAMPLE
./tools/Update-DevTool.ps1 -Name actionlint -Version 1.7.13
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The tool to raise, a key of Tools in dev-tools.psd1; without it every pin is checked.
    [string]$Name,
    # The version to raise it to (x.y.z).
    [string]$Version,
    # The file that pins the tools.
    [string]$Path = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'dev-tools.psd1'),
    # The module that pins the REST API version the gh api calls send.
    [string]$ModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'shared/GitHubOrg.Common.psm1')
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

$header = @('--header', "X-GitHub-Api-Version: $(Get-PinnedGitHubApiVersion -Path $ModulePath)")
# The full path: the .NET write below resolves a relative one against the process, not the PowerShell location.
$Path = (Resolve-Path -LiteralPath $Path).ProviderPath
$tools = (Import-PowerShellDataFile -Path $Path).Tools

function Get-ReleaseFile {
    # File name -> SHA-256 (lowercase hex) of the release of $Repository at $Tag.
    param([string]$Repository, [string]$Tag)

    $release = Invoke-Gh api @header "repos/$Repository/releases/tags/$Tag" | ConvertFrom-Json
    $files = @{}
    foreach ($asset in @($release.assets)) {
        if ([string]$asset.digest -match '^sha256:(?<hash>[0-9a-f]{64})$') {
            $files[[string]$asset.name] = $Matches.hash
        }
    }
    $files
}

if (-not $Name) {
    $differences = [System.Collections.Generic.List[string]]::new()
    foreach ($toolName in $tools.Keys | Sort-Object) {
        $tool = $tools[$toolName]
        $files = Get-ReleaseFile -Repository $tool.Repository -Tag $tool.Tag
        foreach ($platform in $tool.Assets.Keys | Sort-Object) {
            $asset = $tool.Assets[$platform]
            $status = if (-not $files.ContainsKey($asset.Name)) { 'missing' } elseif ($files[$asset.Name] -cne $asset.Sha256) { 'differs' } else { 'ok' }
            Write-Host ('{0,-22} {1,-12} {2,-48} {3}' -f $toolName, $platform, $asset.Name, $status)
            if ($status -ne 'ok') {
                $differences.Add("$toolName $platform $($asset.Name): $status in the release $($tool.Tag) of $($tool.Repository)")
            }
        }
    }
    if ($differences.Count -gt 0) {
        throw "Pinned tool files that do not match their release:`n$(($differences | ForEach-Object { " - $_" }) -join "`n")"
    }
    return
}

if (-not $tools.ContainsKey($Name)) {
    throw "dev-tools.psd1 pins no tool '$Name'; the tools are $(($tools.Keys | Sort-Object) -join ', ')."
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "-Version must be x.y.z, not '$Version'."
}
$tool = $tools[$Name]
$old = [string]$tool.Version
$tag = ([string]$tool.Tag).Replace($old, $Version)
$files = Get-ReleaseFile -Repository $tool.Repository -Tag $tag

# Every platform's new file, before anything is written.
$assets = [ordered]@{}
$missing = [System.Collections.Generic.List[string]]::new()
foreach ($platform in $tool.Assets.Keys | Sort-Object) {
    $file = ([string]$tool.Assets[$platform].Name).Replace($old, $Version)
    if ($files.ContainsKey($file)) {
        $assets[$platform] = @{ Name = $file; Sha256 = $files[$file] }
    }
    else {
        $missing.Add("$platform $file")
    }
}
if ($missing.Count -gt 0) {
    throw "The release $tag of $($tool.Repository) has no file of the expected name for:`n$(($missing | ForEach-Object { " - $_" }) -join "`n")`nSet the names of $Name in $Path by hand."
}

# The lines of the tool's block, from its opening line to the line that closes it at the same indent.
$lines = [System.Collections.Generic.List[string]]::new([string[]]((Get-Content -Raw -Path $Path) -split "`n"))
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^(?<indent>\s*)'?$([regex]::Escape($Name))'?\s*=\s*@\{\s*$") {
        $start = $i
        $indent = $Matches.indent
        break
    }
}
if ($start -lt 0) {
    throw "$Path has no block of '$Name' on lines of its own."
}
for ($i = $start + 1; $i -lt $lines.Count -and $lines[$i] -notmatch "^$([regex]::Escape($indent))\}\s*$"; $i++) {
    $line = $lines[$i]
    $line = $line -replace "^(\s*Version\s*=\s*')[^']*(')", "`${1}$Version`${2}"
    $line = $line -replace "^(\s*Tag\s*=\s*')[^']*(')", "`${1}$tag`${2}"
    foreach ($platform in $assets.Keys) {
        $pattern = "^(\s*'$([regex]::Escape($platform))'\s*=\s*@\{\s*Name\s*=\s*')[^']*(';\s*Sha256\s*=\s*')[^']*(')"
        $line = $line -replace $pattern, "`${1}$($assets[$platform].Name)`${2}$($assets[$platform].Sha256)`${3}"
    }
    $lines[$i] = $line
}

# The new text read back as data, before it is written: a line not in the form rewritten above (an entry over several
# lines, a comment after a value) would otherwise leave a half-raised tool.
$newText = $lines -join "`n"
$hashtable = [System.Management.Automation.Language.Parser]::ParseInput($newText, [ref]$null, [ref]$null).Find({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $false)
$written = $hashtable.SafeGetValue().Tools[$Name]
$unchanged = @(
    if ($written.Version -cne $Version) { 'Version' }
    if ($written.Tag -cne $tag) { 'Tag' }
    foreach ($platform in $assets.Keys) {
        if ($written.Assets[$platform].Name -cne $assets[$platform].Name -or $written.Assets[$platform].Sha256 -cne $assets[$platform].Sha256) { $platform }
    }
)
if ($unchanged.Count -gt 0) {
    throw "$Path has lines of $Name in another form than '<key> = ''<value>''' or '''<platform>'' = @{ Name = ''...''; Sha256 = ''...'' }' on one line: $($unchanged -join ', '). Nothing was written."
}

if ($PSCmdlet.ShouldProcess("$Name $old -> $Version in $Path", 'Update the pinned release files')) {
    # UTF-8 without BOM, the line endings the file had.
    [System.IO.File]::WriteAllText($Path, $newText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "$Name $old -> $Version ($tag): $(($assets.Keys | ForEach-Object { "$_ $($assets[$_].Name)" }) -join ', ')"
}
