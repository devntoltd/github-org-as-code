BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:installScript = Join-Path -Path $script:root -ChildPath 'tools/Install-DevTools.ps1'

    # Stand-ins for the native commands, so Pester can mock them on a machine without them.
    function git { }
}

Describe 'dev-tools.psd1' {
    It 'pins the <Name> version that .github/workflows/ci.yml uses' -ForEach @(
        @{ Name = 'actionlint'; Step = 'actionlint' }
        @{ Name = 'zizmor'; Step = 'zizmor' }
        @{ Name = 'betterleaks'; Step = 'Betterleaks' }
        @{ Name = 'lychee'; Step = 'Markdown links' }
        @{ Name = 'editorconfig-checker'; Step = 'EditorConfig' }
        @{ Name = 'shellcheck'; Step = 'shellcheck' }
    ) {
        $tools = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'dev-tools.psd1')
        $workflow = Get-Content -Path (Join-Path -Path $script:root -ChildPath '.github/workflows/ci.yml') -Raw

        # VERSION of a run: step, or version / lycheeVersion (-match ignores case) in the with: of an action; v1.2.3 is 1.2.3.
        $found = if ($workflow -match "(?s)- name: $Step\r?\n.*?(VERSION|version): (?<version>\S+)") { $Matches.version -replace '^v', '' }
        $found | Should -Not -BeNullOrEmpty
        $found | Should -Be $tools.Tools[$Name].Version
    }

    It 'pins the <Name> SHA-256 of linux-x64 that .github/workflows/ci.yml downloads' -ForEach @(
        @{ Name = 'actionlint'; Step = 'actionlint' }
        @{ Name = 'betterleaks'; Step = 'Betterleaks' }
        @{ Name = 'editorconfig-checker'; Step = 'EditorConfig' }
        @{ Name = 'shellcheck'; Step = 'shellcheck' }
    ) {
        # The same file on the same platform: CI and a contributor on Linux run the same binary.
        $tools = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'dev-tools.psd1')
        $workflow = Get-Content -Path (Join-Path -Path $script:root -ChildPath '.github/workflows/ci.yml') -Raw

        $workflow -match "(?s)- name: $Step\r?\n.*?SHA256: (?<sha>[0-9a-f]{64})" | Should -BeTrue
        $tools.Tools[$Name].Assets['linux-x64'].Sha256 | Should -Be $Matches.sha
    }

    # The central workflow (engine/examples/org-checks.yml) is copied by hand to the organization's .github repository, so its
    # pins must follow the ones of ci.yml, which Dependabot and the dependency check keep current. Dependabot never
    # updates the reference copy, so its pull requests fail here until the copy follows: the message says what to do.
    BeforeAll {
        $script:orgChecksBecause = 'every pin of ci.yml that engine/examples/org-checks.yml shares must match there: raise the same action or tool in engine/examples/org-checks.yml in this pull request (Dependabot does not update it), then copy it to the .github repository of the organization and put the new merge commit in github.json (engine/README.md, Manual setup)'
    }

    It 'pins the <Name> version and SHA-256 of ci.yml in engine/examples/org-checks.yml' -ForEach @(
        @{ Name = 'actionlint'; Step = 'actionlint' }
        @{ Name = 'shellcheck'; Step = 'shellcheck' }
        @{ Name = 'betterleaks'; Step = 'Betterleaks' }
    ) {
        $tools = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'dev-tools.psd1')
        $ci = Get-Content -Path (Join-Path -Path $script:root -ChildPath '.github/workflows/ci.yml') -Raw
        $org = Get-Content -Path (Join-Path -Path $script:root -ChildPath 'engine/examples/org-checks.yml') -Raw
        $pattern = "(?s)- name: $Step\r?\n.*?VERSION: (?<version>\S+)\r?\n\s+SHA256: (?<sha>\S+)"

        $ci -match $pattern | Should -BeTrue
        $expected = $Matches
        $org -match $pattern | Should -BeTrue
        $Matches.version | Should -Be $tools.Tools[$Name].Version -Because $script:orgChecksBecause
        $Matches.sha | Should -Be $expected.sha -Because $script:orgChecksBecause
    }

    It 'pins the zizmor version of dev-tools.psd1 in engine/examples/org-checks.yml' {
        $tools = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'dev-tools.psd1')
        $org = Get-Content -Path (Join-Path -Path $script:root -ChildPath 'engine/examples/org-checks.yml') -Raw

        $org -match '(?s)- name: zizmor\r?\n.*?version: (?<version>\S+)' | Should -BeTrue
        $Matches.version | Should -Be $tools.Tools['zizmor'].Version -Because $script:orgChecksBecause
    }

    # GitHub's release downloads answer 504 at times (2026-11-08: four reruns of one pull request), and curl -f fails the
    # step at once without a retry. --retry alone retries 5xx answers and timeouts; --retry-all-errors would retry a 404
    # of a wrong version too, so it is left out and a bad pin fails at once.
    It 'retries every download of <File> on a transient error, within a time limit' -ForEach @(
        @{ File = '.github/workflows/ci.yml' }
        @{ File = 'engine/examples/org-checks.yml' }
    ) {
        $workflow = Get-Content -Path (Join-Path -Path $script:root -ChildPath $File) -Raw

        $downloads = @([regex]::Matches($workflow, '(?m)^\s*curl .*$') | ForEach-Object { $_.Value.Trim() })
        $downloads.Count | Should -BeGreaterThan 0
        foreach ($download in $downloads) {
            $download | Should -Match '\s--retry \d+(\s|$)' -Because 'a download retries a 5xx answer or a timeout'
            $download | Should -Match '\s--retry-max-time \d+(\s|$)' -Because 'the retries of a download end after a time limit'
            $download | Should -Not -Match '\s--retry-all-errors(\s|$)' -Because 'a 404 of a wrong version fails at once'
        }
    }

    It 'pins every action of engine/examples/org-checks.yml to the SHA ci.yml uses' {
        $ci = Get-Content -Path (Join-Path -Path $script:root -ChildPath '.github/workflows/ci.yml') -Raw
        $org = Get-Content -Path (Join-Path -Path $script:root -ChildPath 'engine/examples/org-checks.yml') -Raw

        $uses = [regex]::Matches($org, '(?m)^\s*(?:- )?uses: (?<action>[^@\s]+)@(?<sha>\S+)')
        $uses.Count | Should -BeGreaterThan 0
        foreach ($use in $uses) {
            $action = [regex]::Escape($use.Groups['action'].Value)
            $ci | Should -Match "uses: $action@$($use.Groups['sha'].Value)\s" -Because $script:orgChecksBecause
        }
    }
}

Describe 'Install-DevTools.ps1' {
    BeforeAll {
        # Release files as the upstream publishes them: a .tar.gz with the executable in a folder, a .zip with the .exe.
        $script:archives = Join-Path -Path $TestDrive -ChildPath 'archives'
        $content = Join-Path -Path $TestDrive -ChildPath 'content'
        New-Item -ItemType Directory -Path $script:archives, (Join-Path -Path $content -ChildPath 'sample-1.0.0') -Force | Out-Null
        Set-Content -Path (Join-Path -Path $content -ChildPath 'sample-1.0.0/sample') -Value 'sample 1.0.0 for linux' -NoNewline
        Set-Content -Path (Join-Path -Path $content -ChildPath 'sample.exe') -Value 'sample 1.0.0 for windows' -NoNewline
        # Relative paths, as the script uses them: GNU tar reads C:\... as host:path.
        Push-Location -LiteralPath $content
        try {
            & tar -czf '../archives/sample_1.0.0_linux_amd64.tar.gz' 'sample-1.0.0'
            if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE." }
        }
        finally {
            Pop-Location
        }
        Compress-Archive -Path (Join-Path -Path $content -ChildPath 'sample.exe') -DestinationPath (Join-Path -Path $script:archives -ChildPath 'sample_1.0.0_windows_amd64.zip')
        $script:hash = @{}
        foreach ($file in Get-ChildItem -Path $script:archives) {
            $script:hash[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    BeforeEach {
        $script:toolsPath = Join-Path -Path $TestDrive -ChildPath "bin-$([guid]::NewGuid())"
        $linux = @{ Name = 'sample_1.0.0_linux_amd64.tar.gz'; Sha256 = $script:hash['sample_1.0.0_linux_amd64.tar.gz'] }
        $windows = @{ Name = 'sample_1.0.0_windows_amd64.zip'; Sha256 = $script:hash['sample_1.0.0_windows_amd64.zip'] }
        $script:TestTools = @{
            sample = @{
                Version    = '1.0.0'
                Repository = 'example/sample'
                Tag        = 'v1.0.0'
                Assets     = @{ 'linux-arm64' = $linux; 'linux-x64' = $linux; 'macos-arm64' = $linux; 'macos-x64' = $linux; 'windows-x64' = $windows }
            }
        }
        $script:paths = @{ ToolsPath = $script:toolsPath; Platform = 'linux-x64' }

        # Before the Get-Module mock: Pester resolves the mocked command through Get-Module.
        Mock Install-PSResource { }
        Mock Find-PSResource { [pscustomobject]@{ Name = $Name; Version = $Version; Dependencies = @() } }
        Mock Import-PowerShellDataFile -ParameterFilter { $Path -like '*dev-tools.psd1' } { @{ Modules = @{ Pester = '6.2.0' }; Tools = $TestTools } }
        Mock Import-PowerShellDataFile -ParameterFilter { $Path -like '*modules.lock.psd1' } { @{ 'Example.Base' = '5.5.3'; 'Example.Tool' = '10.2.1' } }
        Mock Get-Module -ParameterFilter { $ListAvailable } {
            @{
                Pester         = [pscustomobject]@{ Version = [version]'6.2.0' }
                'Example.Base' = [pscustomobject]@{ Version = [version]'5.5.3' }
                'Example.Tool' = [pscustomobject]@{ Version = [version]'10.2.1' }
            }[$Name]
        }
        # The download copies the release file of that name.
        Mock Invoke-WebRequest { Copy-Item -LiteralPath (Join-Path -Path $archives -ChildPath ($Uri -split '/')[-1]) -Destination $OutFile }
        Mock git {
            $global:LASTEXITCODE = 0
            if ($args -contains 'core.hooksPath' -and $args -contains '--get') { '.githooks' }
            if ($args -contains 'blame.ignoreRevsFile' -and $args -contains '--get') { '.git-blame-ignore-revs' }
        }
        Mock Write-Host { }
        Mock Write-Warning { }

        function Write-TestInstalled {
            # .tools/bin as an earlier install left it: the executable and its stamp.
            param([string]$Stamp, [string]$Executable = 'sample', [string]$Content = 'installed earlier')

            New-Item -ItemType Directory -Path $script:toolsPath -Force | Out-Null
            Set-Content -Path (Join-Path -Path $script:toolsPath -ChildPath $Executable) -Value $Content -NoNewline
            Set-Content -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample.pinned') -Value $Stamp
        }
    }

    It 'installs nothing when every tool, module and the hook are in place' {
        Write-TestInstalled -Stamp "1.0.0 $($script:hash['sample_1.0.0_linux_amd64.tar.gz'])"

        & $script:installScript @paths

        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke Install-PSResource -Times 0
        Should -Invoke git -Times 0 -ParameterFilter { $args -notcontains '--get' }
    }

    It 'installs a missing tool from its pinned release file, wherever the archive keeps the executable' {
        & $script:installScript @paths

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://github.com/example/sample/releases/download/v1.0.0/sample_1.0.0_linux_amd64.tar.gz' }
        Get-Content -Raw -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample') | Should -Be 'sample 1.0.0 for linux'
        (Get-Content -Raw -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample.pinned')).Trim() | Should -Be "1.0.0 $($script:hash['sample_1.0.0_linux_amd64.tar.gz'])"
    }

    It 'makes the installed tool executable on Linux and macOS' -Skip:$IsWindows {
        & $script:installScript @paths

        $mode = [System.IO.File]::GetUnixFileMode((Join-Path -Path $script:toolsPath -ChildPath 'sample'))
        $mode.HasFlag([System.IO.UnixFileMode]::UserExecute) | Should -BeTrue
    }

    It 'installs into a relative -ToolsPath below the PowerShell location, as one full path throughout' {
        # .NET calls (the executable bit on Linux and macOS) resolve a relative path against the process, not the location.
        $location = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        Push-Location -LiteralPath $location
        try {
            & $script:installScript -ToolsPath 'tools/bin' -Platform 'linux-x64'
        }
        finally {
            Pop-Location
        }

        $full = Join-Path -Path $location -ChildPath 'tools/bin'
        Get-Content -Raw -Path (Join-Path -Path $full -ChildPath 'sample') | Should -Be 'sample 1.0.0 for linux'
        Test-Path -LiteralPath (Join-Path -Path $full -ChildPath 'sample.pinned') | Should -BeTrue
        Should -Invoke Write-Host -ParameterFilter { $Object -eq "sample 1.0.0 installed into $([System.IO.Path]::GetFullPath($full))" }
    }

    It 'installs again when the stamp is of another pin' {
        Write-TestInstalled -Stamp "0.9.0 $('d' * 64)"

        & $script:installScript @paths

        Get-Content -Raw -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample') | Should -Be 'sample 1.0.0 for linux'
    }

    It 'stops on a file whose SHA-256 differs from the pin, and keeps the installed tool' {
        # A download cut short, an error page saved as the file, or a release file replaced on GitHub.
        Write-TestInstalled -Stamp "0.9.0 $('d' * 64)"
        $script:TestTools.sample.Assets['linux-x64'] = @{ Name = 'sample_1.0.0_linux_amd64.tar.gz'; Sha256 = 'e' * 64 }

        { & $script:installScript @paths } | Should -Throw "*sample_1.0.0_linux_amd64.tar.gz*$('e' * 64)*"

        Get-Content -Raw -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample') | Should -Be 'installed earlier'
    }

    It 'installs the .exe on <Platform>' -ForEach @(
        @{ Platform = 'windows-x64' }
        # Windows on arm64 runs the x64 build through emulation.
        @{ Platform = 'windows-arm64' }
    ) {
        & $script:installScript -ToolsPath $script:toolsPath -Platform $Platform

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/sample_1.0.0_windows_amd64.zip' }
        Get-Content -Raw -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample.exe') | Should -Be 'sample 1.0.0 for windows'
    }

    It 'skips the tools on a platform without pinned files, naming the supported ones, and still sets up the rest' {
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains '--get' }

        & $script:installScript -ToolsPath $script:toolsPath -Platform 'freebsd-x64'

        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*freebsd-x64*linux-arm64, linux-x64, macos-arm64, macos-x64, windows-x64*' }
        # The secret scan of the hook and the modules do not depend on the tools of the checks.
        Should -Invoke git -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '* config --local core.hooksPath .githooks' }
        Should -Invoke Find-PSResource -Times 3 -Exactly
    }

    It 'installs again over an empty stamp an interrupted install left' {
        Write-TestInstalled -Stamp ''
        Set-Content -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample.pinned') -Value '' -NoNewline

        & $script:installScript @paths

        Get-Content -Raw -Path (Join-Path -Path $script:toolsPath -ChildPath 'sample') | Should -Be 'sample 1.0.0 for linux'
    }

    It 'retries a download, as CI does: GitHub release files answer 5xx at times' {
        & $script:installScript @paths

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $MaximumRetryCount -ge 3 -and $RetryIntervalSec -ge 5 }
    }

    It 'takes the file of the platform it runs on' {
        & $script:installScript -ToolsPath $script:toolsPath

        $expected = if ($IsWindows) { '*.zip' } else { '*.tar.gz' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -like $expected }
    }

    It 'installs exactly the locked version, without dependencies, when only another one is installed' {
        Mock Get-Module -ParameterFilter { $ListAvailable } {
            @{
                Pester         = [pscustomobject]@{ Version = [version]'6.3.0' }
                'Example.Base' = [pscustomobject]@{ Version = [version]'5.5.3' }
                'Example.Tool' = [pscustomobject]@{ Version = [version]'10.2.1' }
            }[$Name]
        }

        & $script:installScript @paths

        Should -Invoke Install-PSResource -Times 1 -Exactly
        Should -Invoke Install-PSResource -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Pester' -and $Version -eq '6.2.0' -and $Scope -eq 'CurrentUser' -and $SkipDependencyCheck -and $TrustRepository -and
            $Repository -eq 'PSGallery' -and [bool]$AuthenticodeCheck -eq [bool]$IsWindows
        }
    }

    It 'refuses a dependency that is not locked, before installing anything' {
        Mock Get-Module -ParameterFilter { $ListAvailable } { $null }
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Tool' } {
            [pscustomobject]@{ Name = 'Example.Tool'; Version = '10.2.1'; Dependencies = @([pscustomobject]@{ Name = 'Example.Other'; VersionRange = '[1.0.0, )' }) }
        }

        { & $script:installScript @paths } | Should -Throw '*Example.Tool 10.2.1 needs Example.Other `[1.0.0, ), which is not in modules.lock.psd1*'
        Should -Invoke Install-PSResource -Times 0
    }

    It 'refuses a locked dependency outside the range' {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Tool' } {
            [pscustomobject]@{ Name = 'Example.Tool'; Version = '10.2.1'; Dependencies = @([pscustomobject]@{ Name = 'Example.Base'; VersionRange = '[5.6.0, )' }) }
        }

        { & $script:installScript @paths } | Should -Throw '*Example.Tool 10.2.1 needs Example.Base `[5.6.0, ); modules.lock.psd1 locks 5.5.3*'
    }

    It 'reads the version range <Range> of the Gallery' -ForEach @(
        @{ Range = '[5.5.3, )'; Ok = $true }
        @{ Range = '5.5.3'; Ok = $true }
        @{ Range = '[5.5.3]'; Ok = $true }
        @{ Range = '(5.5.3, 6.0.0)'; Ok = $false }
        @{ Range = '[5.0.0, 5.5.3]'; Ok = $true }
        @{ Range = '[5.0.0, 5.5.3)'; Ok = $false }
    ) {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Tool' } {
            [pscustomobject]@{ Name = 'Example.Tool'; Version = '10.2.1'; Dependencies = @([pscustomobject]@{ Name = 'Example.Base'; VersionRange = $Range }) }
        }

        if ($Ok) {
            { & $script:installScript @paths } | Should -Not -Throw
        }
        else {
            { & $script:installScript @paths } | Should -Throw '*locks 5.5.3*'
        }
    }

    It 'installs only the modules with -ModulesOnly' {
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains '--get' }

        & $script:installScript @paths -ModulesOnly

        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke git -Times 0
        Should -Invoke Find-PSResource -Times 3 -Exactly
    }

    It 'enables the pre-commit hook for this clone only' {
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains '--get' }

        & $script:installScript @paths

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '* config --local core.hooksPath .githooks' }
    }

    It 'makes git blame skip the formatting commits for this clone only' {
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains 'blame.ignoreRevsFile' -and $args -contains '--get' }

        & $script:installScript @paths

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '* config --local blame.ignoreRevsFile .git-blame-ignore-revs' }
        Should -Invoke git -Times 0 -ParameterFilter { ($args -join ' ') -like '* config --local core.hooksPath .githooks' }
    }

    It 'changes nothing with -WhatIf' {
        Mock Get-Module -ParameterFilter { $ListAvailable } { $null }
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains '--get' }

        & $script:installScript @paths -WhatIf

        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke Install-PSResource -Times 0
        Should -Invoke git -Times 0 -ParameterFilter { $args -notcontains '--get' }
    }
}
