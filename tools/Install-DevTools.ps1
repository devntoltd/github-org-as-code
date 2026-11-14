<#
.SYNOPSIS
Installs what the checks of CONTRIBUTING.md need and sets up the git settings of this clone.
.DESCRIPTION
Run once on a new machine or clone, and again after a version changes; it skips what is already in place.

- Command-line tools (the Tools of dev-tools.psd1): the exact versions CI uses, as the release file of this platform
  (windows-x64, linux-x64, linux-arm64, macos-x64, macos-arm64; Windows on arm64 takes windows-x64), checked against
  its SHA-256 in dev-tools.psd1 before it is extracted, into .tools/bin of this clone. A tool counts as installed while
  .tools/bin holds it with a stamp of its pinned version and file (<command>.pinned). build.ps1 and the pre-commit
  hook put .tools/bin first on PATH (docs/decisions/2026-11-14-dev-tools-download.md).
- PowerShell modules (modules.lock.psd1 and the Modules of dev-tools.psd1): first a check that every dependency the
  Gallery lists for a locked version is locked in the same file, with a version in its range; then the exact versions
  for the current user with Install-PSResource -SkipDependencyCheck, the Authenticode signature checked on Windows.
- git config --local: core.hooksPath .githooks (the secret scan of the staged changes before every commit) and
  blame.ignoreRevsFile .git-blame-ignore-revs (git blame skips the formatting commits).

.EXAMPLE
./tools/Install-DevTools.ps1 -WhatIf
.EXAMPLE
./tools/Install-DevTools.ps1 -ModulesOnly
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Only the PowerShell modules: no command-line tools, no git settings (what CI runs).
    [switch]$ModulesOnly,
    # Where the tools go.
    [string]$ToolsPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.tools/bin'),
    # The platform whose release files to install, such as linux-x64; the one this runs on by default.
    [string]$Platform
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent

# The platform this runs on, as dev-tools.psd1 names them: <os>-<architecture>.
function Get-DevToolPlatform {
    $os = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } elseif ($IsLinux) { 'linux' } else { 'unknown' }
    $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'X64' { 'x64' }
        'Arm64' { 'arm64' }
        default { ([string]$_).ToLowerInvariant() }
    }
    "$os-$architecture"
}

# Downloads the release file $Asset of $Tool, checks its SHA-256, and puts the executable $Executable it holds into
# $ToolsPath with its stamp. Nothing in $ToolsPath changes before the file has its pinned hash.
function Install-DevToolFile {
    param([string]$Name, [hashtable]$Tool, [hashtable]$Asset, [string]$Executable, [string]$Stamp)

    $work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path (Join-Path -Path $work -ChildPath 'files') -Force | Out-Null
    try {
        $file = Join-Path -Path $work -ChildPath $Asset.Name
        # Retried as CI retries the same downloads: GitHub release files answer 5xx at times. A 404 is not retried.
        Invoke-WebRequest -Uri "https://github.com/$($Tool.Repository)/releases/download/$($Tool.Tag)/$($Asset.Name)" -OutFile $file -MaximumRetryCount 5 -RetryIntervalSec 10
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne $Asset.Sha256) {
            throw "$($Asset.Name) of $Name $($Tool.Version) has the SHA-256 $hash, not the pinned $($Asset.Sha256); nothing was installed."
        }
        $files = Join-Path -Path $work -ChildPath 'files'
        if ($Asset.Name -like '*.zip') {
            Expand-Archive -LiteralPath $file -DestinationPath $files
        }
        else {
            # Relative paths: GNU tar (as git-bash puts first on PATH on Windows) reads C:\... as host:path.
            Push-Location -LiteralPath $work
            try {
                & tar -xzf $Asset.Name -C 'files'
                if ($LASTEXITCODE -ne 0) {
                    throw "tar could not extract $($Asset.Name) (exit code $LASTEXITCODE)."
                }
            }
            finally {
                Pop-Location
            }
        }
        $found = Get-ChildItem -LiteralPath $files -Recurse -File | Where-Object { $_.Name -ceq $Executable } | Select-Object -First 1
        if (-not $found) {
            throw "$($Asset.Name) of $Name $($Tool.Version) holds no $Executable."
        }
        New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
        $target = Join-Path -Path $ToolsPath -ChildPath $Executable
        Copy-Item -LiteralPath $found.FullName -Destination $target -Force
        if (-not $IsWindows) {
            $execute = [System.IO.UnixFileMode]::UserExecute -bor [System.IO.UnixFileMode]::GroupExecute -bor [System.IO.UnixFileMode]::OtherExecute
            [System.IO.File]::SetUnixFileMode($target, [System.IO.File]::GetUnixFileMode($target) -bor $execute)
        }
        Set-Content -LiteralPath (Join-Path -Path $ToolsPath -ChildPath "$Name.pinned") -Value $Stamp
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Whether $Version is inside a NuGet version range as the Gallery reports it: '[5.5.3, )', '(1.0, 2.0]', '[1.0]' or a
# bare minimum '5.5.3'.
function Test-VersionInRange {
    param([version]$Version, [string]$Range)

    $text = $Range.Trim()
    if ($text -notmatch '^[\[\(]') {
        return $Version -ge [version]$text
    }
    if ($text -match '^\[(?<exact>[^,\]]+)\]$') {
        return $Version -eq [version]$Matches.exact.Trim()
    }
    if ($text -notmatch '^(?<open>[\[\(])\s*(?<min>[^,]*?)\s*,\s*(?<max>[^\]\)]*?)\s*(?<close>[\]\)])$') {
        throw "Unknown version range '$Range'."
    }
    if ($Matches.min) {
        $min = [version]$Matches.min
        if ($Version -lt $min -or ($Matches.open -eq '(' -and $Version -eq $min)) {
            return $false
        }
    }
    if ($Matches.max) {
        $max = [version]$Matches.max
        if ($Version -gt $max -or ($Matches.close -eq ')' -and $Version -eq $max)) {
            return $false
        }
    }
    return $true
}

$devTools = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'dev-tools.psd1')

if (-not $ModulesOnly) {
    $supported = @('linux-arm64', 'linux-x64', 'macos-arm64', 'macos-x64', 'windows-x64')
    if (-not $Platform) {
        $Platform = Get-DevToolPlatform
    }
    # Windows on arm64 runs the x64 builds through emulation.
    $filePlatform = if ($Platform -eq 'windows-arm64') { 'windows-x64' } else { $Platform }
    # Another platform gets no tools, but still the modules and the git settings: the secret scan of the hook works
    # with any Betterleaks on PATH.
    $tools = $devTools.Tools
    if ($filePlatform -notin $supported) {
        Write-Warning "dev-tools.psd1 pins no release files for $Platform; the supported platforms are $($supported -join ', '). Install the tools of the checks at the versions of dev-tools.psd1 yourself."
        $tools = @{}
    }
    foreach ($name in $tools.Keys | Sort-Object) {
        $tool = $tools[$name]
        $asset = $tool.Assets[$filePlatform]
        $executable = if ($filePlatform -like 'windows-*') { "$name.exe" } else { $name }
        $stamp = "$($tool.Version) $($asset.Sha256)"
        $stampPath = Join-Path -Path $ToolsPath -ChildPath "$name.pinned"
        $installed = (Test-Path -LiteralPath (Join-Path -Path $ToolsPath -ChildPath $executable)) -and
            (Test-Path -LiteralPath $stampPath) -and ((Get-Content -Raw -LiteralPath $stampPath) -join '').Trim() -ceq $stamp
        if ($installed) {
            Write-Host "$name $($tool.Version) is installed"
            continue
        }
        if ($PSCmdlet.ShouldProcess("$name $($tool.Version) ($($asset.Name)) into $ToolsPath", 'Download and install')) {
            Install-DevToolFile -Name $name -Tool $tool -Asset $asset -Executable $executable -Stamp $stamp
            Write-Host "$name $($tool.Version) installed into $ToolsPath"
        }
    }
}
$lock = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'modules.lock.psd1')
$moduleSets = [ordered]@{ 'modules.lock.psd1' = $lock; 'dev-tools.psd1' = $devTools.Modules }

# Installs run with -SkipDependencyCheck, so every dependency the Gallery lists must be locked in the same file.
$findings = [System.Collections.Generic.List[string]]::new()
foreach ($file in $moduleSets.Keys) {
    $set = $moduleSets[$file]
    foreach ($name in $set.Keys | Sort-Object) {
        $found = Find-PSResource -Name $name -Version $set[$name] -Repository PSGallery -Type Module
        foreach ($dependency in @($found.Dependencies | Where-Object { $_ })) {
            $range = [string]$dependency.VersionRange
            if (-not $set.Contains($dependency.Name)) {
                $findings.Add("$name $($set[$name]) needs $($dependency.Name) $range, which is not in $file.")
                continue
            }
            if (-not (Test-VersionInRange -Version $set[$dependency.Name] -Range $range)) {
                $findings.Add("$name $($set[$name]) needs $($dependency.Name) $range; $file locks $($set[$dependency.Name]).")
            }
        }
    }
}
if ($findings.Count -gt 0) {
    throw "Module dependencies:`n$(($findings | ForEach-Object { " - $_" }) -join "`n")"
}

# Exact versions, never their dependencies (checked above); the signature on Windows, where the operators run.
$signature = @{}
if ($IsWindows) {
    $signature.AuthenticodeCheck = $true
}
foreach ($file in $moduleSets.Keys) {
    $set = $moduleSets[$file]
    foreach ($name in $set.Keys | Sort-Object) {
        $version = $set[$name]
        if (Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -eq [version]$version }) {
            Write-Host "$name $version is installed ($file)"
            continue
        }
        if ($PSCmdlet.ShouldProcess("$name $version ($file)", 'Install-PSResource')) {
            Install-PSResource -Name $name -Version $version -Repository PSGallery -Scope CurrentUser -SkipDependencyCheck -TrustRepository @signature
            Write-Host "Installed $name $version ($file)"
        }
    }
}

if ($ModulesOnly) {
    return
}

# Settings of this clone: the secret scan of the staged changes before every commit, and git blame skipping the
# formatting commits (GitHub reads .git-blame-ignore-revs by itself).
$gitSettings = [ordered]@{
    'core.hooksPath'       = '.githooks'
    'blame.ignoreRevsFile' = '.git-blame-ignore-revs'
}
foreach ($key in $gitSettings.Keys) {
    $value = $gitSettings[$key]
    $current = git -C $root config --local --get $key
    if ($LASTEXITCODE -eq 0 -and $current -eq $value) {
        Write-Host "git $key is $value"
    }
    elseif ($PSCmdlet.ShouldProcess($root, "git config --local $key $value")) {
        git -C $root config --local $key $value
        if ($LASTEXITCODE -ne 0) {
            throw "git config $key failed with exit code $LASTEXITCODE."
        }
    }
}
