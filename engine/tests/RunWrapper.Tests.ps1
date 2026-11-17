# engine/examples/run.ps1, the wrapper a config repository copies: run from a copy in the test drive, with git mocked
# and the engine replaced by a stub bootstrap.ps1 that records how it was called.
BeforeAll {
    # Stand-in for the native command, so Pester can mock it on a machine without it.
    function git { }

    $script:source = Join-Path -Path $PSScriptRoot -ChildPath '../examples/run.ps1'
    $script:commit = 'a' * 40
    $script:other = 'b' * 40

    # The stub engine: writes its bound switches, the config and -WhatIf to calls.json next to run.ps1.
    $script:stub = @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$ConfigPath, [switch]$Force, [switch]$SkipLatestVersionCheck, [switch]$ManualChecklist, [switch]$PageWalk, [switch]$ValidateOnly)
$switches = @($PSBoundParameters.Keys | Where-Object { $PSBoundParameters[$_] -is [switch] -and $PSBoundParameters[$_] })
@{ ConfigPath = $ConfigPath; Switches = $switches; WhatIf = [bool]$WhatIfPreference } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../calls.json') -WhatIf:$false
'@
}

Describe 'engine/examples/run.ps1' {
    BeforeEach {
        $directory = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $directory | Out-Null
        $script:run = Join-Path -Path $directory -ChildPath 'run.ps1'
        Copy-Item -LiteralPath $script:source -Destination $script:run
        Set-Content -LiteralPath (Join-Path -Path $directory -ChildPath 'engine.psd1') -Value "@{ Repository = 'example-owner/github-org-as-code'; Tag = 'v1.0.0'; Commit = '$script:commit' }"
        # A config whose ruleset requires the central workflow, the central workflow of the pinned engine, and the copy of
        # the config repository beside github.json.
        $script:config = Join-Path -Path $directory -ChildPath 'github.json'
        Set-Content -LiteralPath $script:config -Value '{ "ruleset": { "rules": { "workflows": [ { "repository": ".github", "path": ".github/workflows/org-checks.yml", "sha": "0123456789abcdef0123456789abcdef01234567" } ] } } }'
        $example = "name: org checks`n"
        $script:ownExample = Join-Path -Path $directory -ChildPath 'org-checks.yml'
        Set-Content -LiteralPath $script:ownExample -Value $example -NoNewline
        # Shared with the mocks, whose bodies do not see this file's script scope: a closure keeps the reference.
        $state = @{ Directory = $directory; Head = $null; Status = @(); TagLines = @("$script:commit`trefs/tags/v1.0.0"); Commit = $script:commit; Stub = $script:stub; Wrapper = (Get-Content -Raw -LiteralPath $script:source); Example = $example }
        $script:state = $state

        Mock git { $global:LASTEXITCODE = 0; $state.TagLines }.GetNewClosure() -ParameterFilter { $args[0] -eq 'ls-remote' }
        Mock git { $global:LASTEXITCODE = 0 } -ParameterFilter { $args[0] -eq 'init' }
        Mock git { $global:LASTEXITCODE = 0 } -ParameterFilter { $args -contains 'fetch' }
        Mock git {
            $global:LASTEXITCODE = 0
            $state.Head = $state.Commit
            $engine = Join-Path -Path $state.Directory -ChildPath '.engine/engine'
            New-Item -ItemType Directory -Path $engine -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'bootstrap.ps1') -Value $state.Stub
            New-Item -ItemType Directory -Path (Join-Path -Path $engine -ChildPath 'examples') -Force | Out-Null
            if ($null -ne $state.Wrapper) { Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'examples/run.ps1') -Value $state.Wrapper -NoNewline }
            Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'examples/org-checks.yml') -Value $state.Example -NoNewline
        }.GetNewClosure() -ParameterFilter { $args -contains 'checkout' }
        Mock git { $global:LASTEXITCODE = 0; $state.Head }.GetNewClosure() -ParameterFilter { $args -contains 'rev-parse' }
        # Untracked files show only when asked for, as with status.showUntrackedFiles=no in the user's git config.
        Mock git { $global:LASTEXITCODE = 0; if ($args -contains '--untracked-files=all') { $state.Status } }.GetNewClosure() -ParameterFilter { $args -contains 'status' }

        function Initialize-TestEngine {
            # A checkout already in place at $Head: .engine/.git, the stub engine, and the wrapper and the central workflow
            # of the pinned engine.
            param([Parameter(Mandatory)][string]$Head)

            $engine = Join-Path -Path $script:state.Directory -ChildPath '.engine/engine'
            New-Item -ItemType Directory -Path $engine, (Join-Path -Path $script:state.Directory -ChildPath '.engine/.git') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'bootstrap.ps1') -Value $script:state.Stub
            New-Item -ItemType Directory -Path (Join-Path -Path $engine -ChildPath 'examples') -Force | Out-Null
            if ($null -ne $script:state.Wrapper) { Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'examples/run.ps1') -Value $script:state.Wrapper -NoNewline }
            Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'examples/org-checks.yml') -Value $script:state.Example -NoNewline
            $script:state.Head = $Head
        }

        function Get-TestCall {
            $path = Join-Path -Path $script:state.Directory -ChildPath 'calls.json'
            if (Test-Path -LiteralPath $path) { Get-Content -Raw -LiteralPath $path | ConvertFrom-Json }
        }
    }

    It 'stops when the tag is not at the pinned commit' {
        $script:state.TagLines = @("$script:other`trefs/tags/v1.0.0")

        { & $script:run -WhatIf } | Should -Throw "Tag v1.0.0 of example-owner/github-org-as-code is at $script:other, not at the pinned commit $script:commit."
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -BeNullOrEmpty
    }

    It 'uses the peeled commit of an annotated tag' {
        $script:state.TagLines = @("$script:other`trefs/tags/v1.0.0", "$script:commit`trefs/tags/v1.0.0^{}")

        & $script:run -WhatIf

        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'reuses .engine at the pinned commit' {
        Initialize-TestEngine -Head $script:commit

        & $script:run -WhatIf

        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'stops when .engine at the pinned commit has local changes' {
        Initialize-TestEngine -Head $script:commit
        $script:state.Status = @(' M engine/src/Plan.ps1', '?? extra.ps1')

        { & $script:run -WhatIf } | Should -Throw '*.engine*has local changes*engine/src/Plan.ps1*extra.ps1*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -BeNullOrEmpty
        Join-Path -Path $script:state.Directory -ChildPath '.engine/engine/bootstrap.ps1' | Should -Exist
    }

    It 'stops when .engine at another commit has local changes, before replacing it' {
        Initialize-TestEngine -Head $script:other
        $script:state.Status = @('?? extra.ps1')

        { & $script:run -WhatIf } | Should -Throw '*.engine*has local changes*extra.ps1*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Join-Path -Path $script:state.Directory -ChildPath '.engine/engine/bootstrap.ps1' | Should -Exist
    }

    It 'stops when a new checkout has local changes' {
        # Such as a post-checkout hook of the user's git config would make.
        $script:state.Status = @(' M engine/bootstrap.ps1')

        { & $script:run -WhatIf } | Should -Throw '*.engine*has local changes*engine/bootstrap.ps1*'
        Get-TestCall | Should -BeNullOrEmpty
    }

    It 'stops when .engine is not a checkout and holds files' {
        $file = Join-Path -Path $script:state.Directory -ChildPath '.engine/notes.txt'
        New-Item -ItemType File -Path $file -Force | Out-Null

        { & $script:run -WhatIf } | Should -Throw '*.engine*not a checkout*notes.txt*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq 'init' }
        $file | Should -Exist
    }

    It 'stops when .engine holds only a file named .git in another case' {
        # Not git's metadata on a case-sensitive file system, so a file of the user.
        $file = Join-Path -Path $script:state.Directory -ChildPath '.engine/.Git'
        New-Item -ItemType File -Path $file -Force | Out-Null

        { & $script:run -WhatIf } | Should -Throw '*.engine*not a checkout*.Git*'
        $file | Should -Exist
    }

    It 'replaces .engine that holds only an unfinished checkout' {
        # An interrupted first fetch: .engine/.git without a commit, so HEAD cannot be read.
        New-Item -ItemType Directory -Path (Join-Path -Path $script:state.Directory -ChildPath '.engine/.git') -Force | Out-Null

        & $script:run -WhatIf

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'replaces .engine at another commit' {
        Initialize-TestEngine -Head $script:other

        & $script:run -WhatIf

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args -contains 'fetch' -and $args -contains ('a' * 40) }
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'forwards the switches and -WhatIf' {
        & $script:run -WhatIf -PageWalk

        $call = Get-TestCall
        $call.ConfigPath | Should -Be (Join-Path -Path $script:state.Directory -ChildPath 'github.json')
        # Only the switches given, -WhatIf among them; the others are bound as false.
        @($call.Switches | Sort-Object) | Should -Be @('PageWalk', 'WhatIf')
        $call.WhatIf | Should -BeTrue
    }

    It 'warns after the engine ran when the copy differs from the wrapper of the pinned engine (<Checkout>)' -ForEach @(
        @{ Checkout = 'a new checkout' }
        @{ Checkout = 'a reused checkout' }
    ) {
        # A config repository raised Tag and Commit but kept its old run.ps1.
        $script:state.Wrapper = "# The wrapper of a later release.`n"
        # The engine prints its plan: the warning comes after it, where the end of the run shows it.
        $script:state.Stub += "`n'engine output'"
        if ($Checkout -eq 'a reused checkout') { Initialize-TestEngine -Head $script:commit }

        $output = @(& $script:run -WhatIf 3>&1)

        $pinned = [System.IO.Path]::GetFullPath((Join-Path -Path $script:state.Directory -ChildPath '.engine/engine/examples/run.ps1'))
        $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -Be 1
        $warnings[0].Message | Should -Be "run.ps1 differs from the wrapper of v1.0.0; copy $pinned over $script:run, unless you changed it on purpose."
        $output[-1] | Should -BeOfType ([System.Management.Automation.WarningRecord])
        $output | Should -Contain 'engine output'
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'warns when the engine fails, and the failure of the engine still stops the run' {
        $script:state.Wrapper = "# The wrapper of a later release.`n"
        Set-Content -LiteralPath $script:ownExample -Value "name: old checks`n" -NoNewline
        $script:state.Stub = "throw 'the engine failed'"

        $failure = $null
        try {
            & $script:run -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue
        }
        catch {
            $failure = $_
        }

        [string]$failure | Should -BeLike '*the engine failed*'
        @($warnings).Count | Should -Be 2
        [string]$warnings[0] | Should -BeLike 'run.ps1 differs from the wrapper of v1.0.0;*'
        [string]$warnings[1] | Should -BeLike 'org-checks.yml differs from the example of v1.0.0;*'
    }

    It 'does not warn when the copy equals the wrapper of the pinned engine apart from <Case>' -ForEach @(
        @{ Case = 'LF in the pinned one'; Pinned = { param($t) $t } }
        @{ Case = 'CRLF in the pinned one'; Pinned = { param($t) $t -replace "`n", "`r`n" } }
        @{ Case = 'CRLF in the copy'; Own = { param($t) $t -replace "`n", "`r`n" } }
        @{ Case = 'the newlines at the end'; Pinned = { param($t) $t.TrimEnd() } ; Own = { param($t) "$t`n`n" } }
        @{ Case = 'a signature block of the copy'; Own = { param($t) "$t# SIG # Begin signature block`n# MIIFfAYJKoZIhvcNAQcCoIIFbTCC`n# SIG # End signature block`n" } }
    ) {
        $text = (Get-Content -Raw -LiteralPath $script:source) -replace "`r`n", "`n"
        $script:state.Wrapper = if ($Pinned) { & $Pinned $text } else { $text }
        if ($Own) { Set-Content -LiteralPath $script:run -Value (& $Own $text) -NoNewline }

        & $script:run -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeNullOrEmpty
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'warns after the engine ran when org-checks.yml differs from the example of the pinned engine' {
        # A config repository raised the pin but kept the central workflow of the release before.
        Set-Content -LiteralPath $script:ownExample -Value "name: old checks`n" -NoNewline
        $script:state.Stub += "`n'engine output'"

        $output = @(& $script:run -WhatIf 3>&1)

        $pinned = [System.IO.Path]::GetFullPath((Join-Path -Path $script:state.Directory -ChildPath '.engine/engine/examples/org-checks.yml'))
        $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -Be 1
        $warnings[0].Message | Should -Be "org-checks.yml differs from the example of v1.0.0; copy $pinned over $script:ownExample, unless you changed it on purpose."
        $output[-1] | Should -BeOfType ([System.Management.Automation.WarningRecord])
        $output | Should -Contain 'engine output'
    }

    It 'warns after the engine ran when there is no org-checks.yml beside github.json' {
        Remove-Item -LiteralPath $script:ownExample

        & $script:run -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue

        $pinned = [System.IO.Path]::GetFullPath((Join-Path -Path $script:state.Directory -ChildPath '.engine/engine/examples/org-checks.yml'))
        @($warnings).Count | Should -Be 1
        [string]$warnings[0] | Should -Be "No org-checks.yml beside github.json; copy $pinned to $script:ownExample, the reference copy of the central workflow (engine/README.md, Manual setup)."
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'does not warn when org-checks.yml equals the example of the pinned engine apart from <Case>' -ForEach @(
        @{ Case = 'CRLF in the copy'; Own = "name: org checks`r`n" }
        @{ Case = 'the newlines at the end'; Own = "name: org checks`n`n`n" }
    ) {
        Set-Content -LiteralPath $script:ownExample -Value $Own -NoNewline

        & $script:run -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeNullOrEmpty
    }

    It 'does not check org-checks.yml when the ruleset requires no workflow of that name (<Case>)' -ForEach @(
        @{ Case = 'another name'; Path = '.github/workflows/checks.yml' }
        @{ Case = 'another case'; Path = '.github/workflows/Org-checks.yml' }
    ) {
        Set-Content -LiteralPath $script:config -Value ('{ "ruleset": { "rules": { "workflows": [ { "repository": ".github", "path": "' + $Path + '", "sha": "0123456789abcdef0123456789abcdef01234567" } ] } } }')
        Remove-Item -LiteralPath $script:ownExample

        & $script:run -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeNullOrEmpty
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'leaves github.json that is not JSON to the engine and does not check org-checks.yml' {
        Set-Content -LiteralPath $script:config -Value '{ not json'
        Set-Content -LiteralPath $script:ownExample -Value "name: old checks`n" -NoNewline

        & $script:run -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeNullOrEmpty
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'warns about run.ps1 first, then about org-checks.yml' {
        $script:state.Wrapper = "# The wrapper of a later release.`n"
        Set-Content -LiteralPath $script:ownExample -Value "name: old checks`n" -NoNewline

        & $script:run -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue

        @($warnings).Count | Should -Be 2
        [string]$warnings[0] | Should -BeLike 'run.ps1 differs from the wrapper of v1.0.0;*'
        [string]$warnings[1] | Should -BeLike 'org-checks.yml differs from the example of v1.0.0;*'
    }

    It 'stops before the engine runs when the pinned engine has no engine/examples/run.ps1' {
        $script:state.Wrapper = $null

        { & $script:run -WhatIf } | Should -Throw -ExpectedMessage 'The engine v1.0.0 has no engine/examples/run.ps1, which every release keeps; report it as a bug of the engine.'
        Get-TestCall | Should -BeNullOrEmpty
    }

    It 'rejects a manifest with a short commit' {
        Set-Content -LiteralPath (Join-Path -Path $script:state.Directory -ChildPath 'engine.psd1') -Value "@{ Repository = 'example-owner/github-org-as-code'; Tag = 'v1.0.0'; Commit = 'abc' }"

        { & $script:run -WhatIf } | Should -Throw '*Commit*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq 'ls-remote' }
    }
}
