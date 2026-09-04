#requires -Module Pester
<#
.SYNOPSIS
    Headless tests for the background-work lifecycle helpers: runspace
    creation with module pre-import, BeginStop + graveyard reaping, and
    async close.
#>

BeforeAll {
    Get-Module SuiteCommon | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:manifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'SuiteCommon\SuiteCommon.psd1'
    Import-Module $script:manifest -Force -ErrorAction Stop

    # CloseAsync leaves the runspace thread alive until the close finishes;
    # a test host (unlike a closing WPF shell) hangs on exit if the runspace
    # is never disposed. Wait bounded, then dispose.
    function Complete-RunspaceClose {
        param($Runspace, [int]$TimeoutSec = 10)
        if (-not $Runspace) { return }
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ($Runspace.RunspaceStateInfo.State -notin @('Closed', 'Broken') -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 100
        }
        try { $Runspace.Dispose() } catch { $null = $_ }
    }
}

AfterAll {
    Get-Module SuiteCommon | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'New-SuiteBgRunspace' {

    It 'opens an STA runspace with the tool module pre-imported' {
        $rs = New-SuiteBgRunspace -ModulePath $script:manifest
        try {
            $rs.RunspaceStateInfo.State | Should -Be 'Opened'
            $rs.ApartmentState | Should -Be 'STA'
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            $ver = $ps.AddScript({ Get-SuiteCommonVersion }).Invoke() | Select-Object -First 1
            $ps.Dispose()
            $ver | Should -Be ([string](Import-PowerShellDataFile $script:manifest).ModuleVersion) -Because 'the bootstrap import must make module functions resolvable'
        } finally {
            $rs.Close(); $rs.Dispose()
        }
    }
}

Describe 'New-SuiteBgRunspace failure surfacing' {

    It 'names the real bootstrap failure, logs it, and throws instead of returning a broken runspace' {
        $log = Join-Path $TestDrive 'bginit.log'
        Initialize-Logging -LogPath $log
        { New-SuiteBgRunspace -ModulePath (Join-Path $TestDrive 'no-such-module.psd1') 6>$null } | Should -Throw '*no-such-module*'
        $content = Get-Content $log -Raw
        $content | Should -Match 'Background runspace initialization failed'
        $content | Should -Match 'no-such-module'
    }
}

Describe 'Repair-WindowsPowerShellModulePath' {

    It 'drops PowerShell 7 module roots and keeps the Windows PowerShell ones first' {
        $saved = $env:PSModulePath
        try {
            $winPs = Join-Path $PSHOME 'Modules'
            $env:PSModulePath = 'C:\Users\x\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;c:\program files\windowsapps\microsoft.powershell_7.6.5.0_x64__8wekyb3d8bbwe\Modules;C:\Program Files\WindowsPowerShell\Modules;' + $winPs + ';C:\bin'
            Repair-WindowsPowerShellModulePath | Should -BeTrue
            $roots = @($env:PSModulePath -split ';')
            $roots | Should -Not -Contain 'C:\Program Files\PowerShell\Modules'
            $roots | Should -Not -Contain 'C:\Users\x\Documents\PowerShell\Modules'
            ($roots | Where-Object { $_ -match 'microsoft\.powershell_' }) | Should -BeNullOrEmpty
            $roots | Should -Contain 'C:\Program Files\WindowsPowerShell\Modules'
            $roots | Should -Contain $winPs
            $roots | Should -Contain 'C:\bin'
        } finally {
            $env:PSModulePath = $saved
        }
    }

    It 'reports no change on a clean path and never drops WindowsPowerShell roots' {
        $saved = $env:PSModulePath
        try {
            $winPs = Join-Path $PSHOME 'Modules'
            $env:PSModulePath = 'C:\Program Files\WindowsPowerShell\Modules;' + $winPs
            Repair-WindowsPowerShellModulePath | Should -BeFalse
            $env:PSModulePath | Should -Be ('C:\Program Files\WindowsPowerShell\Modules;' + $winPs)
        } finally {
            $env:PSModulePath = $saved
        }
    }
}

Describe 'Stop-SuiteBgWork graveyard lifecycle' {

    It 'parks a stuck pipeline instead of blocking, then reaps it once stopped' {
        $rs = New-SuiteBgRunspace -ModulePath $script:manifest
        try {
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddScript({ Start-Sleep -Seconds 60 })
            [void]$ps.BeginInvoke()
            Start-Sleep -Milliseconds 300

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $yard = @(Stop-SuiteBgWork -PowerShell $ps -Graveyard @())
            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeLessThan 2000 -Because 'BeginStop must not block on the sleeping pipeline'

            $deadline = (Get-Date).AddSeconds(15)
            while ($yard.Count -gt 0 -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 250
                $yard = @(Stop-SuiteBgWork -PowerShell $null -Graveyard $yard)
            }
            $yard.Count | Should -Be 0 -Because 'the stopped pipeline must eventually be reaped and disposed'
        } finally {
            Close-SuiteBgRunspace -Runspace $rs
            Complete-RunspaceClose -Runspace $rs
        }
    }

    It 'passes an empty teardown through untouched' {
        @(Stop-SuiteBgWork -PowerShell $null -Timer $null -Graveyard @()).Count | Should -Be 0
    }
}

Describe 'Close-SuiteBgRunspace' {

    It 'returns without blocking and tolerates null' {
        { Close-SuiteBgRunspace -Runspace $null } | Should -Not -Throw
        $rs = New-SuiteBgRunspace -ModulePath $script:manifest
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        { Close-SuiteBgRunspace -Runspace $rs } | Should -Not -Throw
        $sw.Stop()
        $sw.ElapsedMilliseconds | Should -BeLessThan 1500
        Complete-RunspaceClose -Runspace $rs
    }
}
