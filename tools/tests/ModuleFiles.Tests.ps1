BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:lock = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'modules.lock.psd1')
}

Describe 'modules.lock.psd1' {
    It 'holds an exact version for every module' {
        # Empty while the engine needs no runtime module.
        foreach ($name in $lock.Keys) {
            $lock[$name] | Should -Match '^\d+\.\d+\.\d+(\.\d+)?$' -Because $name
        }
    }
}

Describe 'dev-tools.psd1' {
    BeforeAll {
        $script:devTools = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'dev-tools.psd1')
    }

    It 'holds an exact version for every module of the checks' {
        @($devTools.Modules.Keys | Sort-Object) | Should -Be @('Pester', 'PSScriptAnalyzer')
        foreach ($name in $devTools.Modules.Keys) {
            $devTools.Modules[$name] | Should -Match '^\d+\.\d+\.\d+$' -Because $name
        }
    }

    It 'has an exact version, a GitHub repository, a release tag and a file with a SHA-256 for every platform of every tool' {
        $platforms = @('linux-arm64', 'linux-x64', 'macos-arm64', 'macos-x64', 'windows-x64')
        $devTools.Tools.Count | Should -BeGreaterThan 0
        foreach ($name in $devTools.Tools.Keys) {
            $tool = $devTools.Tools[$name]
            $tool.Keys | Should -Not -Contain 'WinGetId' -Because $name
            $tool.Version | Should -Match '^\d+\.\d+\.\d+$' -Because $name
            $tool.Repository | Should -Match '^[\w.-]+/[\w.-]+$' -Because $name
            $tool.Tag | Should -BeLike "*$($tool.Version)" -Because $name
            @($tool.Assets.Keys | Sort-Object) | Should -Be $platforms -Because $name
            foreach ($platform in $platforms) {
                $tool.Assets[$platform].Name | Should -Match '\.(zip|tar\.gz)$' -Because "$name $platform"
                $tool.Assets[$platform].Sha256 | Should -MatchExactly '^[0-9a-f]{64}$' -Because "$name $platform"
            }
        }
    }
}
