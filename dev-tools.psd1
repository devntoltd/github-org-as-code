# Exact versions of the developer's tools, installed by tools/Install-DevTools.ps1. Dependabot does not update them; the
# weekly recurring.yml opens an issue for newer versions (tools/Invoke-DependencyUpdateCheck.ps1).
@{
    # PowerShell modules of the checks: name -> version. tools/Invoke-Coverage.ps1 and tools/Invoke-Lint.ps1 load
    # exactly these. Not read by the engine, whose runtime modules (none) are in modules.lock.psd1.
    Modules = @{
        'Pester'           = '6.2.0'
        'PSScriptAnalyzer' = '1.25.0'
    }
    # Command-line tools of the checks: command -> the version .github/workflows/ci.yml pins (a test keeps both equal),
    # the GitHub repository and tag of its release, and per platform the release file and its SHA-256, which
    # tools/Install-DevTools.ps1 checks before it extracts the file into .tools/bin. tools/Update-DevTool.ps1 checks
    # these against GitHub and raises a tool (docs/decisions/2026-11-14-dev-tools-download.md).
    Tools   = @{
        'actionlint'           = @{
            Version    = '1.7.12'
            Repository = 'rhysd/actionlint'
            Tag        = 'v1.7.12'
            Assets     = @{
                'linux-arm64' = @{ Name = 'actionlint_1.7.12_linux_arm64.tar.gz'; Sha256 = '325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6' }
                'linux-x64'   = @{ Name = 'actionlint_1.7.12_linux_amd64.tar.gz'; Sha256 = '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' }
                'macos-arm64' = @{ Name = 'actionlint_1.7.12_darwin_arm64.tar.gz'; Sha256 = 'aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f' }
                'macos-x64'   = @{ Name = 'actionlint_1.7.12_darwin_amd64.tar.gz'; Sha256 = '5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644' }
                'windows-x64' = @{ Name = 'actionlint_1.7.12_windows_amd64.zip'; Sha256 = '6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9' }
            }
        }
        'betterleaks'          = @{
            Version    = '1.9.0'
            Repository = 'betterleaks/betterleaks'
            Tag        = 'v1.9.0'
            Assets     = @{
                'linux-arm64' = @{ Name = 'betterleaks_1.9.0_linux_arm64.tar.gz'; Sha256 = '1d39116e0a58dc94574715e2aa12a2dbd5062f193eee3fec011fef6ba06bd13b' }
                'linux-x64'   = @{ Name = 'betterleaks_1.9.0_linux_x64.tar.gz'; Sha256 = 'f8b185a39ffcece2a1ca82bf3a4e7435cd81963ffd16b7a9128daf75f35f6de7' }
                'macos-arm64' = @{ Name = 'betterleaks_1.9.0_darwin_arm64.tar.gz'; Sha256 = '83dd7eaab13d44a1e8e347a17064cdef153a1478db473276d41b38d55613d3f2' }
                'macos-x64'   = @{ Name = 'betterleaks_1.9.0_darwin_x64.tar.gz'; Sha256 = '68dfd83458d9e7f90663daa7a81c7f944083b170dae82e4f5f8d0581ed519ef1' }
                'windows-x64' = @{ Name = 'betterleaks_1.9.0_windows_x64.zip'; Sha256 = 'b765daec9fda475b031b5a5159798cbe4294a3f2a50683cbc0471226e376d3da' }
            }
        }
        'editorconfig-checker' = @{
            Version    = '4.0.2'
            Repository = 'editorconfig-checker/editorconfig-checker'
            Tag        = 'v4.0.2'
            # One macOS file for both architectures.
            Assets     = @{
                'linux-arm64' = @{ Name = 'editorconfig-checker-linux-arm64.tar.gz'; Sha256 = 'abad76da8c9950fdc2a314bcd66969172aa823e9c595fa7e3a389a91e34d025e' }
                'linux-x64'   = @{ Name = 'editorconfig-checker-linux-amd64.tar.gz'; Sha256 = '44efaef3ed14c6ab52eb87481d78e5e5c204796dccf26e2f4598a61ba17f8003' }
                'macos-arm64' = @{ Name = 'editorconfig-checker-darwin-all.tar.gz'; Sha256 = 'ff59f57717d95fc62b8e372c8051dbbb766f7d660942409a85d027b0feb2422c' }
                'macos-x64'   = @{ Name = 'editorconfig-checker-darwin-all.tar.gz'; Sha256 = 'ff59f57717d95fc62b8e372c8051dbbb766f7d660942409a85d027b0feb2422c' }
                'windows-x64' = @{ Name = 'editorconfig-checker-windows-amd64.zip'; Sha256 = '857f8f74dfc259d73dac93573e37cf3ce01150787d7b139bf839549cc6b5beb9' }
            }
        }
        'lychee'               = @{
            Version    = '0.24.2'
            Repository = 'lycheeverse/lychee'
            Tag        = 'lychee-v0.24.2'
            Assets     = @{
                'linux-arm64' = @{ Name = 'lychee-aarch64-unknown-linux-gnu.tar.gz'; Sha256 = '91a7bd65685da41b90ccb9bc867a3d649a7818042dae04ff405e55a25bddee4c' }
                'linux-x64'   = @{ Name = 'lychee-x86_64-unknown-linux-gnu.tar.gz'; Sha256 = '1f4e0ef7f6554a6ed33dd7ac144fb2e1bbed98598e7af973042fc5cd43951c9a' }
                'macos-arm64' = @{ Name = 'lychee-aarch64-apple-darwin.tar.gz'; Sha256 = 'c9d3740ea2d891854d37116c9fba840f37b6e7c89d330e7db84ac333631c4977' }
                'macos-x64'   = @{ Name = 'lychee-x86_64-apple-darwin.tar.gz'; Sha256 = '887503a9cff667d322b8d0892b40bf49976eb9507af8483220a3706cdad55978' }
                'windows-x64' = @{ Name = 'lychee-x86_64-pc-windows-msvc.zip'; Sha256 = '32975d1493ee1a975d6bb41e4fb56fe419cb442ded628bb772ba2e614acfacad' }
            }
        }
        # actionlint runs it on the run: scripts of the workflows only when it is installed, and skips them silently otherwise.
        'shellcheck'           = @{
            Version    = '0.11.0'
            Repository = 'koalaman/shellcheck'
            Tag        = 'v0.11.0'
            Assets     = @{
                'linux-arm64' = @{ Name = 'shellcheck-v0.11.0.linux.aarch64.tar.gz'; Sha256 = '68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc' }
                'linux-x64'   = @{ Name = 'shellcheck-v0.11.0.linux.x86_64.tar.gz'; Sha256 = 'b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6' }
                'macos-arm64' = @{ Name = 'shellcheck-v0.11.0.darwin.aarch64.tar.gz'; Sha256 = '339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f' }
                'macos-x64'   = @{ Name = 'shellcheck-v0.11.0.darwin.x86_64.tar.gz'; Sha256 = 'c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51' }
                'windows-x64' = @{ Name = 'shellcheck-v0.11.0.zip'; Sha256 = '8a4e35ab0b331c85d73567b12f2a444df187f483e5079ceffa6bda1faa2e740e' }
            }
        }
        'zizmor'               = @{
            Version    = '1.31.1'
            Repository = 'zizmorcore/zizmor'
            Tag        = 'v1.31.1'
            Assets     = @{
                'linux-arm64' = @{ Name = 'zizmor-aarch64-unknown-linux-gnu.tar.gz'; Sha256 = '37eebbd5762a44f262d94875431b14a6d2402991e90a685113ea97b8b41be833' }
                'linux-x64'   = @{ Name = 'zizmor-x86_64-unknown-linux-gnu.tar.gz'; Sha256 = 'd185f726bdaf92df78273217dfdd24ebcd6b0ef48cf3ce776ff5762b6e138c99' }
                'macos-arm64' = @{ Name = 'zizmor-aarch64-apple-darwin.tar.gz'; Sha256 = 'ad5aa633cd56215b11e6c51d51f90c7e6b22904a75047d1215abbd422f61d698' }
                'macos-x64'   = @{ Name = 'zizmor-x86_64-apple-darwin.tar.gz'; Sha256 = '72ae63bb85b67229c06242f04195cb43927e9fab5f43803c6434dc701a517d61' }
                'windows-x64' = @{ Name = 'zizmor-x86_64-pc-windows-msvc.zip'; Sha256 = '4de30371c8a3b483aecbcf0dec1fd6a2b6aae65051ca226b4f6527baac6a8c7a' }
            }
        }
    }
}
