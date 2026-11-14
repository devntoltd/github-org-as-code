BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:updateScript = Join-Path -Path $script:root -ChildPath 'tools/Update-DevTool.ps1'
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')

    $script:hashA = 'a' * 64
    $script:hashB = 'b' * 64
    $script:hashC = 'c' * 64

    function Get-TestAsset {
        # An asset as 'gh api repos/<repo>/releases/tags/<tag>' lists it.
        param([string]$Name, [string]$Hash)

        @{ name = $Name; digest = "sha256:$Hash" }
    }
}

Describe 'Update-DevTool.ps1' {
    BeforeEach {
        $folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        $script:module = Join-Path -Path $folder -ChildPath 'Common.psm1'
        Set-Content -Path $script:module -Value "`$script:GitHubApiVersion = '2026-03-10'"
        $script:devTools = Join-Path -Path $folder -ChildPath 'dev-tools.psd1'
        Set-Content -Path $script:devTools -NoNewline -Value (@(
                '@{'
                '    Modules = @{'
                "        'Pester' = '6.2.0'"
                '    }'
                '    Tools   = @{'
                "        'sample' = @{"
                "            Version    = '1.2.3'"
                "            Repository = 'example/sample'"
                "            Tag        = 'v1.2.3'"
                '            Assets     = @{'
                "                'linux-x64'   = @{ Name = 'sample_1.2.3_linux_amd64.tar.gz'; Sha256 = '$script:hashA' }"
                "                'windows-x64' = @{ Name = 'sample-all.zip'; Sha256 = '$script:hashB' }"
                '            }'
                '        }'
                '    }'
                '}'
                ''
            ) -join "`n")
        $script:paths = @{ Path = $script:devTools; ModulePath = $script:module }

        # Release tag -> assets.
        $script:TestReleases = @{
            'v1.2.3' = @((Get-TestAsset -Name 'sample_1.2.3_linux_amd64.tar.gz' -Hash $script:hashA), (Get-TestAsset -Name 'sample-all.zip' -Hash $script:hashB))
            'v1.3.0' = @((Get-TestAsset -Name 'sample_1.3.0_linux_amd64.tar.gz' -Hash $script:hashC), (Get-TestAsset -Name 'sample-all.zip' -Hash $script:hashA))
        }
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        # The mock runs inside the script under test: the fixtures are found by name (dynamic scoping).
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $endpoint = @($args | Where-Object { $_ -like 'repos/*' })[0]
            $tag = ($endpoint -split '/')[-1]
            if (-not $TestReleases.ContainsKey($tag)) {
                $global:LASTEXITCODE = 1
                return 'gh: Not Found (HTTP 404)'
            }
            $global:LASTEXITCODE = 0
            @{ tag_name = $tag; assets = @($TestReleases[$tag]) } | ConvertTo-Json -Depth 5
        }
        Mock Write-Host { }
    }

    It 'verifies every pinned file against its release and writes nothing' {
        $before = Get-Content -Raw -Path $script:devTools

        & $script:updateScript @paths

        Get-Content -Raw -Path $script:devTools | Should -Be $before
        @($TestGhCalls | Where-Object { $_ -contains 'repos/example/sample/releases/tags/v1.2.3' }).Count | Should -Be 1
    }

    It 'throws naming the tool, platform and file when a pinned hash differs from the release' {
        $script:TestReleases['v1.2.3'][1] = Get-TestAsset -Name 'sample-all.zip' -Hash $script:hashC

        { & $script:updateScript @paths } | Should -Throw '*sample*windows-x64*sample-all.zip*'
    }

    It 'raises a tool: version, tag, the name and hash of every platform' {
        & $script:updateScript @paths -Name 'sample' -Version '1.3.0'

        $tool = (Import-PowerShellDataFile -Path $script:devTools).Tools.sample
        $tool.Version | Should -Be '1.3.0'
        $tool.Tag | Should -Be 'v1.3.0'
        $tool.Assets['linux-x64'].Name | Should -Be 'sample_1.3.0_linux_amd64.tar.gz'
        $tool.Assets['linux-x64'].Sha256 | Should -Be $script:hashC
        $tool.Assets['windows-x64'].Name | Should -Be 'sample-all.zip'
        $tool.Assets['windows-x64'].Sha256 | Should -Be $script:hashA
        (Import-PowerShellDataFile -Path $script:devTools).Modules.Pester | Should -Be '6.2.0'
    }

    It 'writes nothing when the new release has no file of an expected name' {
        # The upstream renamed a file: the platform and the name it looked for are named, and no line changes.
        $script:TestReleases['v1.3.0'] = @(Get-TestAsset -Name 'sample-all.zip' -Hash $script:hashA)
        $before = Get-Content -Raw -Path $script:devTools

        { & $script:updateScript @paths -Name 'sample' -Version '1.3.0' } | Should -Throw '*linux-x64*sample_1.3.0_linux_amd64.tar.gz*'

        Get-Content -Raw -Path $script:devTools | Should -Be $before
    }

    It 'throws for a tool that dev-tools.psd1 does not pin' {
        { & $script:updateScript @paths -Name 'other' -Version '1.0.0' } | Should -Throw "*'other'*"
    }

    It 'sends the pinned REST API version with every gh api call' {
        & $script:updateScript @paths

        foreach ($call in $TestGhCalls) {
            Get-GhOption -Call $call -Name '--header' | Should -Be 'X-GitHub-Api-Version: 2026-03-10'
        }
    }

    It 'writes nothing when a line of the tool is not in the form it rewrites' {
        # A platform entry over several lines: rewriting the others would leave a half-raised block.
        $text = (Get-Content -Raw -Path $script:devTools) -replace "'windows-x64' = @\{ Name = 'sample-all.zip'; Sha256 = '$script:hashB' \}", "'windows-x64' = @{`n                    Name = 'sample-all.zip'; Sha256 = '$script:hashB'`n                }"
        Set-Content -Path $script:devTools -Value $text -NoNewline

        { & $script:updateScript @paths -Name 'sample' -Version '1.3.0' } | Should -Throw '*windows-x64*'

        Get-Content -Raw -Path $script:devTools | Should -Be $text
    }

    It 'writes to the file it read when -Path is relative' {
        Push-Location -Path (Split-Path -Path $script:devTools -Parent)
        try {
            & $script:updateScript -Path './dev-tools.psd1' -ModulePath $script:module -Name 'sample' -Version '1.3.0'
        }
        finally {
            Pop-Location
        }

        (Import-PowerShellDataFile -Path $script:devTools).Tools.sample.Version | Should -Be '1.3.0'
    }

    It 'with -WhatIf writes nothing' {
        $before = Get-Content -Raw -Path $script:devTools

        & $script:updateScript @paths -Name 'sample' -Version '1.3.0' -WhatIf

        Get-Content -Raw -Path $script:devTools | Should -Be $before
    }
}
