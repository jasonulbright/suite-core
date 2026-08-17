#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x tests for the SuiteCommon shared module.

.DESCRIPTION
    Covers logging, settings persistence, and the CM connection functions
    with mocked CM cmdlets. No MECM site, network, or elevation required.

.EXAMPLE
    Invoke-Pester .\SuiteCommon.Tests.ps1
#>

BeforeAll {
    Import-Module "$PSScriptRoot\..\SuiteCommon\SuiteCommon.psd1" -Force -DisableNameChecking

    # Connect-CMSite resolves Get-CMSite through the module's fallback to the
    # global scope; a global stub makes the command mockable without a CM
    # console in the test session.
    function global:Get-CMSite { param([string]$SiteCode) throw 'stub Get-CMSite reached without a mock' }
}

AfterAll {
    Remove-Item -LiteralPath 'function:\Get-CMSite' -ErrorAction SilentlyContinue
}

# ============================================================================
# Write-Log / Initialize-Logging
# ============================================================================

Describe 'Write-Log' {
    It 'writes formatted message to log file' {
        $logFile = Join-Path $TestDrive 'test.log'
        Initialize-Logging -LogPath $logFile
        Write-Log 'Hello world' -Quiet
        (Get-Content -LiteralPath $logFile -Raw) | Should -Match '\[INFO \] Hello world'
    }

    It 'tags WARN messages correctly' {
        $logFile = Join-Path $TestDrive 'warn.log'
        Initialize-Logging -LogPath $logFile
        Write-Log 'Slow' -Level WARN -Quiet
        (Get-Content -LiteralPath $logFile -Raw) | Should -Match '\[WARN \] Slow'
    }

    It 'tags ERROR messages correctly' {
        $logFile = Join-Path $TestDrive 'error.log'
        Initialize-Logging -LogPath $logFile
        Write-Log 'Boom' -Level ERROR -Quiet
        (Get-Content -LiteralPath $logFile -Raw) | Should -Match '\[ERROR\] Boom'
    }

    It 'writes DEBUG lines to the log file even when verbose is off' {
        $logFile = Join-Path $TestDrive 'debug.log'
        Initialize-Logging -LogPath $logFile
        Write-Log 'Trace detail' -Level DEBUG
        (Get-Content -LiteralPath $logFile -Raw) | Should -Match '\[DEBUG\] Trace detail'
    }

    It 'accepts empty string message' {
        $logFile = Join-Path $TestDrive 'empty.log'
        Initialize-Logging -LogPath $logFile
        { Write-Log '' -Quiet } | Should -Not -Throw
    }
}

Describe 'Initialize-Logging' {
    It 'creates log file with header line' {
        $logFile = Join-Path $TestDrive 'init.log'
        Initialize-Logging -LogPath $logFile
        Test-Path -LiteralPath $logFile | Should -BeTrue
        (Get-Content -LiteralPath $logFile -Raw) | Should -Match '\[INFO \] === Log initialized ==='
    }

    It 'creates parent directories if missing' {
        $logFile = Join-Path $TestDrive 'sub\dir\deep.log'
        Initialize-Logging -LogPath $logFile
        Test-Path -LiteralPath $logFile | Should -BeTrue
    }

    It '-Attach preserves an externally-created log file' {
        $logFile = Join-Path $TestDrive 'attach.log'
        $sentinel = "[2026-01-01 00:00:00] [INFO ] Shell-managed header"
        Set-Content -LiteralPath $logFile -Value $sentinel -Encoding UTF8
        Initialize-Logging -LogPath $logFile -Attach
        Write-Log 'Module appended line' -Quiet
        $content = Get-Content -LiteralPath $logFile -Raw
        $content | Should -Match 'Shell-managed header'
        $content | Should -Match 'Module appended line'
    }

    It 'treats a whitespace-only LogPath as no log path instead of throwing' {
        { Initialize-Logging -LogPath ' ' } | Should -Not -Throw
        { Write-Log 'after whitespace path' -Quiet } | Should -Not -Throw
    }

    It '-VerboseLogging turns the verbose flag on' {
        $logFile = Join-Path $TestDrive 'verbose.log'
        Initialize-Logging -LogPath $logFile -VerboseLogging
        InModuleScope SuiteCommon { $script:__SuiteVerbose } | Should -BeTrue
        Initialize-Logging -LogPath $logFile
        InModuleScope SuiteCommon { $script:__SuiteVerbose } | Should -BeFalse
    }

    It 'SUITE_VERBOSE env var enables verbose unless holding an off value' {
        $logFile = Join-Path $TestDrive 'envverbose.log'
        try {
            $env:SUITE_VERBOSE = '1'
            Initialize-Logging -LogPath $logFile
            InModuleScope SuiteCommon { $script:__SuiteVerbose } | Should -BeTrue
            $env:SUITE_VERBOSE = 'false'
            Initialize-Logging -LogPath $logFile
            InModuleScope SuiteCommon { $script:__SuiteVerbose } | Should -BeFalse
        }
        finally {
            Remove-Item Env:\SUITE_VERBOSE -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Write-LogErrorRecord' {
    It 'logs exception type, error id, and stack frames' {
        $logFile = Join-Path $TestDrive 'errrec.log'
        Initialize-Logging -LogPath $logFile
        $record = $null
        try { throw [System.InvalidOperationException]::new('deliberate failure') }
        catch { $record = $_ }
        Write-LogErrorRecord -ErrorRecord $record -Context 'unit test' -Level DEBUG
        $content = Get-Content -LiteralPath $logFile -Raw
        $content | Should -Match 'Failure context'
        $content | Should -Match 'System\.InvalidOperationException: deliberate failure'
        $content | Should -Match 'FullyQualifiedErrorId'
        $content | Should -Match 'Stack'
    }
}

# ============================================================================
# Settings
# ============================================================================

Describe 'Read-SuiteSettings' {
    It 'returns defaults when the file does not exist' {
        $s = Read-SuiteSettings -Path (Join-Path $TestDrive 'missing.json') -Defaults @{ DarkMode = $true; SiteCode = '' }
        $s.DarkMode | Should -BeTrue
        $s.SiteCode | Should -Be ''
    }

    It 'overlays file values onto defaults' {
        $p = Join-Path $TestDrive 'prefs.json'
        @{ DarkMode = $false; SiteCode = 'MCM' } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding UTF8
        $s = Read-SuiteSettings -Path $p -Defaults @{ DarkMode = $true; SiteCode = ''; SMSProvider = '' }
        $s.DarkMode | Should -BeFalse
        $s.SiteCode | Should -Be 'MCM'
        $s.SMSProvider | Should -Be ''
    }

    It 'ignores keys the defaults do not declare' {
        $p = Join-Path $TestDrive 'extra.json'
        @{ DarkMode = $false; Rogue = 'x' } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding UTF8
        $s = Read-SuiteSettings -Path $p -Defaults @{ DarkMode = $true }
        $s.ContainsKey('Rogue') | Should -BeFalse
    }

    It 'returns defaults unchanged for a corrupt file' {
        $p = Join-Path $TestDrive 'corrupt.json'
        Set-Content -LiteralPath $p -Value '{ not json' -Encoding UTF8
        $s = Read-SuiteSettings -Path $p -Defaults @{ DarkMode = $true; SiteCode = 'ABC' }
        $s.DarkMode | Should -BeTrue
        $s.SiteCode | Should -Be 'ABC'
    }

    It 'decodes BOM-less UTF-8 files correctly' {
        $p = Join-Path $TestDrive 'nobom.json'
        $json = '{ "SiteCode": "Zoë" }'
        [System.IO.File]::WriteAllText($p, $json, [System.Text.UTF8Encoding]::new($false))
        $s = Read-SuiteSettings -Path $p -Defaults @{ SiteCode = '' }
        $s.SiteCode | Should -Be 'Zoë'
    }
}

Describe 'Save-SuiteSettings' {
    It 'round-trips through Read-SuiteSettings' {
        $p = Join-Path $TestDrive 'roundtrip.json'
        $ok = Save-SuiteSettings -Path $p -Settings @{ DarkMode = $false; SiteCode = 'MCM'; SMSProvider = 'cm01.contoso.com' }
        $ok | Should -BeTrue
        $s = Read-SuiteSettings -Path $p -Defaults @{ DarkMode = $true; SiteCode = ''; SMSProvider = '' }
        $s.DarkMode | Should -BeFalse
        $s.SMSProvider | Should -Be 'cm01.contoso.com'
    }

    It 'creates a missing parent directory on first save' {
        $p = Join-Path $TestDrive 'fresh\install\dir\prefs.json'
        $ok = Save-SuiteSettings -Path $p -Settings @{ A = 1 }
        $ok | Should -BeTrue
        Test-Path -LiteralPath $p | Should -BeTrue
    }

    It 'returns $false for an unwritable path' {
        # A FILE named like a directory segment makes parent creation fail.
        $blocker = Join-Path $TestDrive 'blocker'
        Set-Content -LiteralPath $blocker -Value 'x' -Encoding Ascii
        $ok = Save-SuiteSettings -Path (Join-Path $blocker 'x.json') -Settings @{ A = 1 }
        $ok | Should -BeFalse
    }
}

# ============================================================================
# CM connection (mocked)
# ============================================================================

Describe 'Connect-CMSite' {
    BeforeEach {
        Remove-Item Env:\SUITE_CM_PROVIDER -ErrorAction SilentlyContinue
    }

    It 'creates the CMSite PSDrive with -Scope Global when the drive is missing' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { $null } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
            Mock Set-Location { }
            Mock Get-CMSite { [pscustomobject]@{ SiteName = 'Lab Site' } }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' -SMSProvider 'cm01.contoso.com' | Should -BeTrue

            Should -Invoke New-PSDrive -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'MCM' -and $PSProvider -eq 'CMSite' -and $Root -eq 'cm01.contoso.com' -and $Scope -eq 'Global'
            }
            Should -Invoke Get-CMSite -Times 1 -Exactly
        }
    }

    It 'binds the provider through the ProviderMachineName alias' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { $null } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
            Mock Set-Location { }
            Mock Get-CMSite { [pscustomobject]@{ SiteName = 'Lab Site' } }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' -ProviderMachineName 'cm02.contoso.com' | Should -BeTrue

            Should -Invoke New-PSDrive -Times 1 -Exactly -ParameterFilter { $Root -eq 'cm02.contoso.com' }
        }
    }

    It 'falls back to SUITE_CM_PROVIDER when no provider parameter is given' {
        try {
            $env:SUITE_CM_PROVIDER = 'cm03.contoso.com'
            InModuleScope SuiteCommon {
                Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
                Mock Get-PSDrive { $null } -ParameterFilter { $PSProvider -eq 'CMSite' }
                Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
                Mock Set-Location { }
                Mock Get-CMSite { [pscustomobject]@{ SiteName = 'Lab Site' } }
                Mock Write-Log { }

                Connect-CMSite -SiteCode 'MCM' | Should -BeTrue

                Should -Invoke New-PSDrive -Times 1 -Exactly -ParameterFilter { $Root -eq 'cm03.contoso.com' }
            }
        }
        finally {
            Remove-Item Env:\SUITE_CM_PROVIDER -ErrorAction SilentlyContinue
        }
    }

    It 'fails clearly when no drive exists and no provider can be resolved' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { $null } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock New-PSDrive { throw 'should not be called' }
            Mock Set-Location { }
            Mock Get-CMSite { }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' | Should -BeFalse

            Should -Invoke New-PSDrive -Times 0 -Exactly
        }
    }

    It 'rebinds an existing drive whose root differs from the requested provider' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { [pscustomobject]@{ Name = 'MCM'; Root = 'oldprov.contoso.com' } } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock Remove-PSDrive { }
            Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
            Mock Set-Location { }
            Mock Get-CMSite { [pscustomobject]@{ SiteName = 'Lab Site' } }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' -SMSProvider 'newprov.contoso.com' | Should -BeTrue

            Should -Invoke Remove-PSDrive -Times 1 -Exactly
            Should -Invoke New-PSDrive -Times 1 -Exactly -ParameterFilter { $Root -eq 'newprov.contoso.com' -and $Scope -eq 'Global' }
            # Steps off the drive before removing it - the drive you are
            # located in cannot be removed.
            Should -Invoke Set-Location -ParameterFilter { $LiteralPath -eq "$env:SystemDrive\" }
        }
    }

    It 'keeps an existing matching drive without rebinding' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { [pscustomobject]@{ Name = 'MCM'; Root = 'prov.contoso.com' } } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock Remove-PSDrive { throw 'must not be called' }
            Mock New-PSDrive { throw 'must not be called' }
            Mock Set-Location { }
            Mock Get-CMSite { [pscustomobject]@{ SiteName = 'Lab Site' } }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' -SMSProvider 'prov.contoso.com' | Should -BeTrue

            Should -Invoke Remove-PSDrive -Times 0 -Exactly
            Should -Invoke New-PSDrive -Times 0 -Exactly
        }
    }

    It 'rebuilds a stale drive whose Set-Location fails, reusing its root' {
        InModuleScope SuiteCommon {
            $script:__slCalls = 0
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { [pscustomobject]@{ Name = 'MCM'; Root = 'oldprov.contoso.com' } } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock Remove-PSDrive { }
            Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
            Mock Set-Location {
                $script:__slCalls++
                if ($script:__slCalls -eq 1) { throw 'provider connection lost' }
            }
            Mock Get-CMSite { [pscustomobject]@{ SiteName = 'Lab Site' } }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' | Should -BeTrue

            Should -Invoke Remove-PSDrive -Times 1 -Exactly
            Should -Invoke New-PSDrive -Times 1 -Exactly -ParameterFilter { $Root -eq 'oldprov.contoso.com' -and $Scope -eq 'Global' }
        }
    }

    It 'returns $false when site verification fails' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { $null } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
            Mock Set-Location { }
            Mock Get-CMSite { throw 'no such site' }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' -SMSProvider 'cm01.contoso.com' | Should -BeFalse
        }
    }

    It '-SkipSiteVerification skips the Get-CMSite round-trip' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { $null } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
            Mock Set-Location { }
            Mock Get-CMSite { throw 'must not be reached' }
            Mock Write-Log { }

            Connect-CMSite -SiteCode 'MCM' -SMSProvider 'cm01.contoso.com' -SkipSiteVerification | Should -BeTrue

            Should -Invoke Get-CMSite -Times 0 -Exactly
        }
    }
}

Describe 'Get-CMConnectionInfo / Disconnect-CMSite' {
    It 'records the connection after Connect-CMSite and clears it on Disconnect' {
        InModuleScope SuiteCommon {
            Mock Get-Module { [pscustomobject]@{ Name = 'ConfigurationManager' } } -ParameterFilter { $Name -eq 'ConfigurationManager' }
            Mock Get-PSDrive { $null } -ParameterFilter { $PSProvider -eq 'CMSite' }
            Mock New-PSDrive { [pscustomobject]@{ Name = $Name; Root = $Root } }
            Mock Set-Location { }
            Mock Get-CMSite { [pscustomobject]@{ SiteName = 'Lab Site' } }
            Mock Write-Log { }

            [void](Connect-CMSite -SiteCode 'MCM' -SMSProvider 'cm01.contoso.com')
            $info = Get-CMConnectionInfo
            $info | Should -Not -BeNullOrEmpty
            $info.SiteCode | Should -Be 'MCM'
            $info.SMSProvider | Should -Be 'cm01.contoso.com'
            $info.ConnectedAt | Should -Not -BeNullOrEmpty

            Disconnect-CMSite
            Get-CMConnectionInfo | Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-CMConnection' {
    It 'is $false when nothing is connected' {
        InModuleScope SuiteCommon {
            Mock Write-Log { }
            Disconnect-CMSite
            Test-CMConnection | Should -BeFalse
        }
    }
}

Describe 'Get-SuiteCommonVersion' {
    It 'reports the manifest ModuleVersion' {
        Get-SuiteCommonVersion | Should -Be ([string](Import-PowerShellDataFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'SuiteCommon\SuiteCommon.psd1')).ModuleVersion)
    }
}
