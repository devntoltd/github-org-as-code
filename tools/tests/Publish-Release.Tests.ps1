BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:releaseScript = Join-Path -Path $script:root -ChildPath 'tools/Publish-Release.ps1'
    # CI sets it for the whole job, and Invoke-Coverage.ps1 writes to it after the tests: restored after every test.
    $script:savedSummary = $env:GITHUB_STEP_SUMMARY
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')

    $script:commit = 'a' * 40
    $script:other = 'b' * 40

    function Initialize-TestRelease {
        # The manifest at 1.1.0, the pinning module, a changelog and the step summary in $Folder; the gh fixtures: no
        # tag, the published release v1.0.0.
        param([Parameter(Mandatory)][string]$Folder)

        $script:manifest = Join-Path -Path $Folder -ChildPath 'Engine.psd1'
        Write-TestManifest -Version '1.1.0'
        $script:module = Join-Path -Path $Folder -ChildPath 'Common.psm1'
        Set-Content -Path $script:module -Value "`$script:GitHubApiVersion = '2026-03-10'"
        $script:changelog = Join-Path -Path $Folder -ChildPath 'CHANGELOG.md'
        Set-Content -Path $script:changelog -Value (@(
                '# Changelog'
                ''
                '## [Unreleased]'
                ''
                '## [1.1.0] - 2026-11-20'
                ''
                '### Changed'
                ''
                '- The new behavior.'
                ''
                '## [1.0.0] - 2026-11-13'
                ''
                '### Added'
                ''
                '- The first release.'
                ''
                '[Unreleased]: https://example.test/compare/v1.1.0...HEAD'
                '[1.1.0]: https://example.test/compare/v1.0.0...v1.1.0'
            ) -join "`n")
        $script:paths = @{ ManifestPath = $script:manifest; ChangelogPath = $script:changelog; ModulePath = $script:module }
        $script:summary = Join-Path -Path $Folder -ChildPath 'summary.md'
        $env:GITHUB_STEP_SUMMARY = $script:summary

        # The refs of 'git/matching-refs/tags/<tag>', the annotated tag objects by sha, and 'gh release list'.
        $script:TestRefs = @()
        $script:TestTagObjects = @{}
        $script:TestReleases = @(@{ tagName = 'v1.0.0'; isDraft = $false })
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
    }

    function Write-TestManifest {
        param([Parameter(Mandatory)][string]$Version, [string]$Path = $script:manifest)

        Set-Content -Path $Path -Value "@{`n    RootModule    = 'Engine.psm1'`n    ModuleVersion = '$Version'`n}"
    }

    function Get-TestRef {
        # A ref as 'git/matching-refs' returns it: a commit (lightweight tag) or a tag object (annotated tag).
        param([string]$Name, [string]$Sha, [string]$Type = 'commit')

        @{ ref = "refs/tags/$Name"; object = @{ sha = $Sha; type = $Type } }
    }
}

Describe 'Publish-Release.ps1' {
    BeforeEach {
        Initialize-TestRelease -Folder (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        $script:paths.Commit = $script:commit
        # The mocks run inside the script under test: the fixtures are found by name (dynamic scoping), so their names
        # must not clash with variables of the script.
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'api') {
                $path = $args[-1]
                if ($path -like 'repos/{owner}/{repo}/git/matching-refs/tags/*') { return ConvertTo-Json -InputObject @($TestRefs) -Depth 5 }
                if ($path -like 'repos/{owner}/{repo}/git/tags/*') { return $TestTagObjects[($path -split '/')[-1]] | ConvertTo-Json -Depth 5 }
            }
            switch ($args[0..1] -join ' ') {
                'release list' { ConvertTo-Json -InputObject @($TestReleases) }
                'release create' { 'https://example.test/releases/tag/v1.1.0' }
            }
        }
        Mock Write-Host { }
        # git: rev-parse resolves a revision to $TestResolved (the revision itself when unset); show of the parent's
        # manifest gives $TestParentManifest, a failure when it is $null.
        $script:TestResolved = $null
        $script:TestParentManifest = "@{ ModuleVersion = '1.0.0' }"
        $script:TestGitCalls = [System.Collections.Generic.List[string[]]]::new()
        Mock git {
            $TestGitCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            if ($args -contains 'rev-parse') {
                $revision = [string]($args | Where-Object { $_ -like '*^{commit}' }) -replace '\^\{commit\}$'
                if ($TestResolved) { $TestResolved } else { $revision }
            }
            elseif ($args -contains 'show') {
                if ($null -eq $TestParentManifest) { $global:LASTEXITCODE = 128 } else { $TestParentManifest -split "`n" }
            }
        }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    It 'publishes the release of a new version at the commit, with the changelog section as notes' {
        & $script:releaseScript @paths

        $created = Get-GhCall -Command 'release create'
        $created.Count | Should -Be 1
        $created[0][2] | Should -Be 'v1.1.0'
        Get-GhOption -Call $created[0] -Name '--target' | Should -Be $script:commit
        Get-GhOption -Call $created[0] -Name '--title' | Should -Be 'v1.1.0'
        # The section only: neither its heading, nor the next release.
        Get-GhOption -Call $created[0] -Name '--notes' | Should -Be "### Changed`n`n- The new behavior."
        $created[0] | Should -Contain '--latest'
        $created[0] | Should -Not -Contain '--draft'
    }

    It 'keeps a link definition inside the section and leaves out those at the end of the file' {
        Set-Content -Path $script:changelog -Value (@(
                '## [1.1.0] - 2026-11-20'
                ''
                '- See [the notes][n].'
                ''
                '[n]: https://example.test/notes'
                ''
                '- More.'
                ''
                '[1.1.0]: https://example.test/compare/v1.0.0...v1.1.0'
            ) -join "`n")

        & $script:releaseScript @paths

        Get-GhOption -Call (Get-GhCall -Command 'release create')[0] -Name '--notes' |
            Should -Be "- See [the notes][n].`n`n[n]: https://example.test/notes`n`n- More."
    }

    It 'marks the release Latest only when no published release has a higher version' {
        $script:TestReleases = @(@{ tagName = 'v1.0.0'; isDraft = $false }, @{ tagName = 'v1.2.0'; isDraft = $false })

        & $script:releaseScript @paths

        $created = (Get-GhCall -Command 'release create')[0]
        $created | Should -Contain '--latest=false'
        $created | Should -Not -Contain '--latest'
    }

    It 'sends the pinned REST API version with every gh api call' {
        & $script:releaseScript @paths

        $api = @($TestGhCalls | Where-Object { $_[0] -eq 'api' })
        $api.Count | Should -BeGreaterThan 0
        foreach ($call in $api) {
            Get-GhOption -Call $call -Name '--header' | Should -Be 'X-GitHub-Api-Version: 2026-03-10'
        }
    }

    It 'does nothing when the release of the version exists' {
        # Every commit of main after the release: the tag is at an earlier commit.
        $script:TestRefs = @(Get-TestRef -Name 'v1.1.0' -Sha $script:other)
        $script:TestReleases = @(@{ tagName = 'v1.1.0'; isDraft = $false })
        $script:TestParentManifest = "@{ ModuleVersion = '1.1.0' }"

        & $script:releaseScript @paths

        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
        Get-Content -Raw -Path $script:summary | Should -Match '\| 1\.1\.0 \| v1\.1\.0 \| released \|'
    }

    It 'publishes only the release when the tag exists at the commit (<Kind>)' -ForEach @(
        @{ Kind = 'lightweight' }
        @{ Kind = 'annotated' }
    ) {
        if ($Kind -eq 'annotated') {
            $script:TestRefs = @(Get-TestRef -Name 'v1.1.0' -Sha ('c' * 40) -Type 'tag')
            $script:TestTagObjects[('c' * 40)] = @{ object = @{ sha = $script:commit; type = 'commit' } }
        }
        else {
            $script:TestRefs = @(Get-TestRef -Name 'v1.1.0' -Sha $script:commit)
        }

        & $script:releaseScript @paths

        (Get-GhCall -Command 'release create').Count | Should -Be 1
    }

    It 'stops before any write when the tag is at another commit' {
        # A ref of another tag with the same prefix does not count.
        $script:TestRefs = @((Get-TestRef -Name 'v1.1.0' -Sha $script:other), (Get-TestRef -Name 'v1.1.0-rc' -Sha $script:commit))

        { & $script:releaseScript @paths } | Should -Throw "*v1.1.0 is at $script:other, not at $script:commit*"
        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
    }

    It 'stops before any write when a draft release of the tag exists' {
        $script:TestReleases = @(@{ tagName = 'v1.1.0'; isDraft = $true })

        { & $script:releaseScript @paths } | Should -Throw '*draft release v1.1.0*'
        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
    }

    It 'stops before any gh call when the changelog has <Case>' -ForEach @(
        @{ Case = 'no section of the version'; Version = '1.2.0' }
        @{ Case = 'an empty section of the version'; Version = '1.1.0'; Section = '' }
        @{ Case = 'only headings in the section of the version'; Version = '1.1.0'; Section = "### Changed`n`n### Fixed`n" }
    ) {
        Write-TestManifest -Version $Version
        if ($null -ne $Section) {
            Set-Content -Path $script:changelog -Value "# Changelog`n`n## [1.1.0] - 2026-11-20`n`n$Section`n## [1.0.0] - 2026-11-13`n`n- The first release."
        }

        { & $script:releaseScript @paths } | Should -Throw "*CHANGELOG.md has no entries under ## ``[$Version``]*"
        $TestGhCalls | Should -BeNullOrEmpty
    }

    It 'with -WhatIf reads but publishes nothing' {
        & $script:releaseScript @paths -WhatIf

        Get-GhCall -Command 'release list' | Should -Not -BeNullOrEmpty
        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
        Get-Content -Raw -Path $script:summary | Should -Match '\| 1\.1\.0 \| v1\.1\.0 \| new \|'
    }

    It 'publishes nothing and warns on a commit that did not raise the version' {
        # The run of the release merge has not published (yet): a later commit of main must not take its place.
        $script:TestParentManifest = "@{`n    ModuleVersion = `"1.1.0`"`n}"

        & $script:releaseScript @paths

        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
        Get-Content -Raw -Path $script:summary | Should -Match '\| 1\.1\.0 \| v1\.1\.0 \| waits for the commit that raised it \|'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '::warning::*v1.1.0*not published*' }
        $show = @($TestGitCalls | Where-Object { $_ -contains 'show' })[0]
        $show | Should -Contain "$script:commit^1:./Engine.psd1"
    }

    It 'stops when the manifest of the parent commit cannot be read' {
        $script:TestParentManifest = $null

        { & $script:releaseScript @paths } | Should -Throw '*git show*exit code 128*'
        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
    }

    It 'resolves the commit to its full SHA' {
        $script:paths.Commit = 'HEAD'
        $script:TestResolved = $script:other

        & $script:releaseScript @paths

        Get-GhOption -Call (Get-GhCall -Command 'release create')[0] -Name '--target' | Should -Be $script:other
    }

    It 'takes the commit of the run from GITHUB_SHA' {
        $saved = $env:GITHUB_SHA
        $env:GITHUB_SHA = $script:other
        try {
            $paths.Remove('Commit')
            & $script:releaseScript @paths
        }
        finally {
            $env:GITHUB_SHA = $saved
        }

        Get-GhOption -Call (Get-GhCall -Command 'release create')[0] -Name '--target' | Should -Be $script:other
    }
}

# The same script on a real git history, gh still mocked: what the git calls answer is the behavior here.
Describe 'Publish-Release.ps1 with a real git history' {
    BeforeAll {
        $script:repository = Join-Path -Path $TestDrive -ChildPath 'history'
        New-Item -ItemType Directory -Path $script:repository | Out-Null
        Initialize-TestRelease -Folder $script:repository

        function Add-TestCommit {
            # Commits the manifest as it is and returns the full SHA.
            param([string]$Message)

            git -C $script:repository add --all 2>&1 | Out-Null
            git -C $script:repository -c user.name=test -c user.email=test@example.test -c commit.gpgsign=false commit -q -m $Message 2>&1 | Out-Null
            git -C $script:repository rev-parse HEAD
        }

        git -C $script:repository init -q 2>&1 | Out-Null
        Write-TestManifest -Version '1.0.0'
        $script:first = Add-TestCommit -Message 'Release 1.0.0'
        Write-TestManifest -Version '1.1.0'
        $script:raised = Add-TestCommit -Message 'Release 1.1.0'
        # Only the alignment of the line changes: not a raise.
        Set-Content -Path $script:manifest -Value "@{`n    RootModule  = 'Engine.psm1'`n    ModuleVersion   =   '1.1.0'`n}"
        $script:reformatted = Add-TestCommit -Message 'Reformat the manifest'
    }

    BeforeEach {
        $env:GITHUB_STEP_SUMMARY = $script:summary
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'api') { return '[]' }
            if (($args[0..1] -join ' ') -eq 'release list') { return ConvertTo-Json -InputObject @(@{ tagName = 'v1.0.0'; isDraft = $false }) }
        }
        Mock Write-Host { }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    It 'publishes from the commit that raised the version, given by a short SHA' {
        & $script:releaseScript @paths -Commit $script:raised.Substring(0, 7)

        Get-GhOption -Call (Get-GhCall -Command 'release create')[0] -Name '--target' | Should -Be $script:raised
    }

    It 'publishes nothing from a later commit that only reformats the version line' {
        & $script:releaseScript @paths -Commit $script:reformatted

        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
    }
}
