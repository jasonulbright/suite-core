#requires -Module Pester
<#
.SYNOPSIS
    Headless tests for the SuiteCommon chrome layer: window-state
    save/restore geometry (RestoreBounds branch, clamp-to-monitor,
    legacy X/Y schema bridge, ExtraState merge) and the theme context.
    Dialog and hook behavior needs real windows and lives in the STA
    harness, not here.
#>

BeforeAll {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
    Get-Module SuiteCommon | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'SuiteCommon\SuiteCommon.psd1') -Force -ErrorAction Stop

    function New-MockWindow {
        param(
            [int]$Left = 100, [int]$Top = 100, [int]$Width = 800, [int]$Height = 600,
            [System.Windows.WindowState]$WindowState = [System.Windows.WindowState]::Normal,
            $RestoreBounds = $null,
            [double]$MinWidth = 200, [double]$MinHeight = 150
        )
        [pscustomobject]@{
            Left = [double]$Left; Top = [double]$Top
            Width = [double]$Width; Height = [double]$Height
            WindowState = $WindowState
            RestoreBounds = $RestoreBounds
            MinWidth = $MinWidth; MinHeight = $MinHeight
        }
    }
}

AfterAll {
    Get-Module SuiteCommon | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Save-WindowState geometry capture' {

    It 'captures live bounds when the window is Normal' {
        $w = New-MockWindow -Left 50 -Top 60 -Width 900 -Height 700
        $path = Join-Path $TestDrive 'normal.json'
        Save-WindowState -Window $w -Path $path
        $s = Get-Content $path -Raw | ConvertFrom-Json
        $s.Left | Should -Be 50
        $s.Width | Should -Be 900
        $s.Maximized | Should -BeFalse
    }

    It 'captures RestoreBounds, not full-screen extents, when maximized' {
        $rb = [pscustomobject]@{ Left = 120; Top = 80; Width = 1000; Height = 650 }
        $w = New-MockWindow -Left 0 -Top 0 -Width 2560 -Height 1400 -WindowState Maximized -RestoreBounds $rb
        $path = Join-Path $TestDrive 'max.json'
        Save-WindowState -Window $w -Path $path
        $s = Get-Content $path -Raw | ConvertFrom-Json
        $s.Maximized | Should -BeTrue
        $s.Left | Should -Be 120
        $s.Width | Should -Be 1000
        $s.Height | Should -Be 650
    }

    It 'skips the save without throwing when geometry reads NaN (window never shown)' {
        $w = New-MockWindow
        $w.Left = [double]::NaN; $w.Top = [double]::NaN; $w.Width = [double]::NaN; $w.Height = [double]::NaN
        $path = Join-Path $TestDrive 'nan.json'
        { Save-WindowState -Window $w -Path $path } | Should -Not -Throw
        Test-Path $path | Should -BeFalse
    }

    It 'skips the save without throwing on an Empty-rect RestoreBounds' {
        $rb = [pscustomobject]@{
            Left = [double]::PositiveInfinity; Top = [double]::PositiveInfinity
            Width = [double]::NegativeInfinity; Height = [double]::NegativeInfinity
        }
        $w = New-MockWindow -WindowState Maximized -RestoreBounds $rb
        $path = Join-Path $TestDrive 'empty-rect.json'
        { Save-WindowState -Window $w -Path $path } | Should -Not -Throw
        Test-Path $path | Should -BeFalse
    }

    It 'merges ExtraState keys into the persisted document' {
        $w = New-MockWindow
        $path = Join-Path $TestDrive 'extra.json'
        Save-WindowState -Window $w -Path $path -ExtraState @{ ActiveView = 'Findings'; DarkTheme = $true }
        $s = Get-Content $path -Raw | ConvertFrom-Json
        $s.ActiveView | Should -Be 'Findings'
        $s.DarkTheme | Should -BeTrue
    }
}

Describe 'Restore-WindowState geometry apply' {

    It 'round-trips an on-screen geometry unchanged' {
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $left = $area.X + 40; $top = $area.Y + 40
        $path = Join-Path $TestDrive 'rt.json'
        @{ Left = $left; Top = $top; Width = 640; Height = 480; Maximized = $false } | ConvertTo-Json | Set-Content $path
        $w = New-MockWindow -Left 0 -Top 0
        Restore-WindowState -Window $w -Path $path
        $w.Left | Should -Be $left
        $w.Width | Should -Be 640
    }

    It 'clamps an off-screen position into the nearest working area, keeping the size' {
        $path = Join-Path $TestDrive 'off.json'
        @{ Left = -30000; Top = -30000; Width = 800; Height = 600; Maximized = $false } | ConvertTo-Json | Set-Content $path
        $w = New-MockWindow -Left 0 -Top 0
        Restore-WindowState -Window $w -Path $path
        $found = $false
        foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
            $a = $screen.WorkingArea
            if ($w.Left -ge $a.X -and $w.Left -le $a.Right -and $w.Top -ge $a.Y -and $w.Top -le $a.Bottom) { $found = $true }
        }
        $found | Should -BeTrue -Because 'the position must land inside some working area'
        $w.Width | Should -Be 800 -Because 'the size survives the clamp'
        $w.Height | Should -Be 600
    }

    It 'floors restored size at the window minimums' {
        $path = Join-Path $TestDrive 'tiny.json'
        @{ Left = 100; Top = 100; Width = 10; Height = 10; Maximized = $false } | ConvertTo-Json | Set-Content $path
        $w = New-MockWindow -MinWidth 320 -MinHeight 240
        Restore-WindowState -Window $w -Path $path
        $w.Width | Should -Be 320
        $w.Height | Should -Be 240
    }

    It 'maps the legacy X/Y schema onto Left/Top' {
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $x = $area.X + 55; $y = $area.Y + 66
        $path = Join-Path $TestDrive 'legacy.json'
        @{ X = $x; Y = $y; Width = 700; Height = 500; Maximized = $false } | ConvertTo-Json | Set-Content $path
        $w = New-MockWindow -Left 0 -Top 0
        Restore-WindowState -Window $w -Path $path
        $w.Left | Should -Be $x
        $w.Top | Should -Be $y
    }

    It 'applies saved geometry as the normal bounds before maximizing, and hands the raw state to OnStateLoaded' {
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $gl = $area.X + 123; $gt = $area.Y + 100
        $path = Join-Path $TestDrive 'maxload.json'
        @{ Left = $gl; Top = $gt; Width = 901; Height = 702; Maximized = $true; ActiveView = 'Content' } | ConvertTo-Json | Set-Content $path
        $w = New-MockWindow -Left 500 -Top 500 -Width 800 -Height 600
        $seen = $null
        Restore-WindowState -Window $w -Path $path -OnStateLoaded { param($s) Set-Variable -Name seen -Value $s -Scope 1 }
        $w.WindowState | Should -Be ([System.Windows.WindowState]::Maximized)
        $w.Width | Should -Be 901 -Because 'the saved geometry must become the normal bounds so un-maximizing returns to it'
        $w.Height | Should -Be 702
        $w.Left | Should -Be $gl
        $seen.ActiveView | Should -Be 'Content'
    }

    It 'does nothing when the state file is absent' {
        $w = New-MockWindow -Left 77 -Top 88
        Restore-WindowState -Window $w -Path (Join-Path $TestDrive 'missing.json')
        $w.Left | Should -Be 77
    }

    It 'survives a corrupt state file without touching the window' {
        $path = Join-Path $TestDrive 'corrupt.json'
        Set-Content $path -Value '{not json'
        $w = New-MockWindow -Left 77 -Top 88
        { Restore-WindowState -Window $w -Path $path } | Should -Not -Throw
        $w.Left | Should -Be 77
    }
}

Describe 'Suite theme context' {

    It 'throws a clear error when theme functions run before Initialize-SuiteTheme' {
        InModuleScope SuiteCommon { $script:SuiteTheme = $null }
        { Update-SidebarButtonTheme -IsDark $true } | Should -Throw '*Initialize-SuiteTheme*'
    }

    It 'stores defaults and applies overrides' {
        $w = [pscustomobject]@{ Name = 'win' }
        Initialize-SuiteTheme -Window $w -IsDarkGetter { $true } -Brushes @{ TitleBarActive = 'OVERRIDE' }
        InModuleScope SuiteCommon {
            $script:SuiteTheme.Brushes.TitleBarActive | Should -Be 'OVERRIDE'
            $script:SuiteTheme.Brushes.LogLabelDark.ToString() | Should -Be '#FFB0B0B0'
            $script:SuiteTheme.ActiveMode | Should -Be 'Fill'
        }
    }

    It 'themes sidebar buttons by fill in Fill mode and by border in Border mode' {
        function New-FakeButton {
            [pscustomobject]@{ Background = $null; BorderBrush = $null; BorderThickness = $null }
        }
        $b1 = New-FakeButton; $b2 = New-FakeButton
        $views = @(@{ Name = 'A'; Button = $b1 }, @{ Name = 'B'; Button = $b2 })

        Initialize-SuiteTheme -Window ([pscustomobject]@{}) -IsDarkGetter { $true } -ActiveViewGetter { 'A' } -ViewButtons $views -ActiveMode Fill
        Update-SidebarButtonTheme
        $b1.Background.ToString() | Should -Be '#FF3A3A3A'
        $b2.Background.ToString() | Should -Be '#FF1E1E1E'
        $b1.BorderBrush.ToString() | Should -Be $b2.BorderBrush.ToString()

        Initialize-SuiteTheme -Window ([pscustomobject]@{}) -IsDarkGetter { $true } -ActiveViewGetter { 'A' } -ViewButtons $views -ActiveMode Border
        Update-SidebarButtonTheme
        $b1.Background.ToString() | Should -Be $b2.Background.ToString()
        $b1.BorderBrush.ToString() | Should -Be '#FFF9F9F9'
        $b2.BorderBrush.ToString() | Should -Be '#FF555555'
    }

    It 'evaluates the IsDark getter in the caller scope' {
        $script:probeDark = $false
        Initialize-SuiteTheme -Window ([pscustomobject]@{}) -IsDarkGetter { $script:probeDark } -ViewButtons @()
        $btn = [pscustomobject]@{ Background = $null; BorderBrush = $null; BorderThickness = $null }
        Initialize-SuiteTheme -Window ([pscustomobject]@{}) -IsDarkGetter { $script:probeDark } -ViewButtons @(@{ Name='X'; Button=$btn }) -ActiveViewGetter { 'X' }
        $script:probeDark = $true
        Update-SidebarButtonTheme
        $btn.Background.ToString() | Should -Be '#FF3A3A3A' -Because 'getter must see the updated caller-scope value'
    }
}
