# MECM Suite launcher: tool tiles + shared connection profile.
# Thin by design -- every tool launches as its own process; the only state
# handed across is the connection profile via environment variables
# (SUITE_CM_PROVIDER is a Connect-CMSite fallback; SUITE_CM_SITECODE is
# published for tools that opt in).
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Start-Process powershell.exe -ArgumentList '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"" | Out-Null
    exit
}
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
foreach ($dll in 'Microsoft.Xaml.Behaviors.dll','ControlzEx.dll','MahApps.Metro.dll') {
    $p = Join-Path $PSScriptRoot "Lib\$dll"
    Unblock-File -Path $p -ErrorAction SilentlyContinue
    [void][System.Reflection.Assembly]::LoadFrom($p)
}
Import-Module (Join-Path $PSScriptRoot 'SuiteCommon\SuiteCommon.psd1') -Force -DisableNameChecking

$script:SettingsPath    = Join-Path $PSScriptRoot 'suite.settings.json'
$script:WindowStatePath = Join-Path $PSScriptRoot 'suite.windowstate.json'
$global:Prefs = Read-SuiteSettings -Path $script:SettingsPath -Defaults @{
    SiteCode    = ''
    SMSProvider = ''
    DarkMode    = $true
    ToolsRoot   = ''
}

# Registry of suite tools: folder name, display name, entry script.
# Discovery is folder-presence under ToolsRoot (default: this repo's parent,
# the side-by-side checkout/extract layout every tool zip documents).
$script:ToolRegistry = @(
    @{ Folder = 'app-packager';                      Name = 'App Packager';            Script = 'start-apppackager.ps1' }
    @{ Folder = 'dp-content-manager';                Name = 'DP Content Manager';      Script = 'start-dpcontentmgr.ps1' }
    @{ Folder = 'collection-manager';                Name = 'Collection Manager';      Script = 'start-collectionmanager.ps1' }
    @{ Folder = 'deployment-helper';                 Name = 'Deployment Helper';       Script = 'start-deploymenthelper.ps1' }
    @{ Folder = 'detection-tester';                  Name = 'Detection Tester';        Script = 'start-detectiontester.ps1' }
    @{ Folder = 'installer-analysis';                Name = 'Installer Analysis';      Script = 'start-installeranalysis.ps1' }
    @{ Folder = 'maintenance-window-manager';        Name = 'Maintenance Windows';     Script = 'start-maintenancewindowmgr.ps1' }
    @{ Folder = 'mecm-health-dashboard';             Name = 'Health Dashboard';        Script = 'start-mecmhealthdashboard.ps1' }
    @{ Folder = 'collection-and-compliance-manager'; Name = 'Collection + Compliance'; Script = 'start-ccm.ps1' }
    @{ Folder = 'site-hygiene';                      Name = 'Site Hygiene';            Script = 'start-sitehygiene.ps1' }
)

function Get-SuiteToolsRoot {
    $root = [string]$global:Prefs['ToolsRoot']
    if ([string]::IsNullOrWhiteSpace($root)) { $root = Split-Path $PSScriptRoot -Parent }
    return $root
}

function Get-ToolVersion {
    param([Parameter(Mandatory)][string]$ToolDir)
    # CHANGELOG headline first ('## [1.2.3]' or '## 1.2.3'); module manifest
    # as fallback. The manifest can trail the app version (app-packager's
    # module versions independently of its releases).
    $cl = Join-Path $ToolDir 'CHANGELOG.md'
    if (Test-Path -LiteralPath $cl) {
        foreach ($line in (Get-Content -LiteralPath $cl -TotalCount 30)) {
            if ($line -match '^##\s+\[?([0-9][0-9\.]*[0-9])\]?') { return $Matches[1] }
        }
    }
    $psd1 = Get-ChildItem -Path (Join-Path $ToolDir 'Module') -Filter '*.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($psd1) {
        try { return [string](Import-PowerShellDataFile -LiteralPath $psd1.FullName).ModuleVersion } catch { $null = $_ }
    }
    return ''
}

function Get-InstalledTools {
    $root = Get-SuiteToolsRoot
    foreach ($t in $script:ToolRegistry) {
        $dir = Join-Path $root $t.Folder
        $entry = Join-Path $dir $t.Script
        if (Test-Path -LiteralPath $entry) {
            [pscustomobject]@{
                Folder  = $t.Folder
                Name    = $t.Name
                Entry   = $entry
                Version = Get-ToolVersion -ToolDir $dir
            }
        }
    }
}

function Set-LaunchEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Sets process-scope environment variables for child inheritance.')]
    param()
    $provider = ([string]$global:Prefs['SMSProvider']).Trim()
    $site     = ([string]$global:Prefs['SiteCode']).Trim()
    if ($provider) { $env:SUITE_CM_PROVIDER = $provider } else { Remove-Item Env:SUITE_CM_PROVIDER -ErrorAction SilentlyContinue }
    if ($site)     { $env:SUITE_CM_SITECODE = $site }     else { Remove-Item Env:SUITE_CM_SITECODE -ErrorAction SilentlyContinue }
}

function Start-SuiteTool {
    param([Parameter(Mandatory)]$Tool)
    Set-LaunchEnvironment
    Start-Process powershell.exe -ArgumentList '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"`"$($Tool.Entry)`"" -WorkingDirectory (Split-Path $Tool.Entry -Parent) | Out-Null
    Set-SuiteStatus ('Launched {0}.' -f $Tool.Name)
}

$mainXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="MECM Suite" Width="760" Height="560" MinWidth="620" MinHeight="420"
    TitleCharacterCasing="Normal" ShowIconOnTitleBar="False"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1" WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Padding="14,12,14,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="SITE" FontSize="11" VerticalAlignment="Center"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}" Margin="0,0,6,0"/>
                <TextBox x:Name="txtSiteCode" Grid.Column="1" Width="70" FontSize="12" Padding="6,3,6,3"
                         Controls:TextBoxHelper.Watermark="MCM" VerticalAlignment="Center" Margin="0,0,14,0"/>
                <TextBlock Grid.Column="2" Text="SMS PROVIDER" FontSize="11" VerticalAlignment="Center"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}" Margin="0,0,6,0"/>
                <TextBox x:Name="txtProvider" Grid.Column="3" FontSize="12" Padding="6,3,6,3"
                         Controls:TextBoxHelper.Watermark="cm01.contoso.com" VerticalAlignment="Center" Margin="0,0,14,0"/>
                <Button x:Name="btnSaveProfile" Grid.Column="4" Content="Save" MinWidth="70" Height="28"
                        Style="{DynamicResource MahApps.Styles.Button.Square.Accent}"
                        Controls:ControlsHelper.ContentCharacterCasing="Normal" Margin="0,0,14,0"/>
                <TextBlock x:Name="txtThemeLabel" Grid.Column="5" Text="Dark Theme" FontSize="11"
                           VerticalAlignment="Center" Margin="0,0,6,0"/>
                <Controls:ToggleSwitch x:Name="toggleTheme" Grid.Column="6" VerticalAlignment="Center"
                                       OnContent="" OffContent="" MinWidth="0"/>
            </Grid>
        </Border>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="10,0,10,0">
            <WrapPanel x:Name="panelTiles" Orientation="Horizontal"/>
        </ScrollViewer>

        <Border Grid.Row="2" Padding="14,6,14,6" Background="{DynamicResource MahApps.Brushes.Gray10}">
            <TextBlock x:Name="txtStatus" Text="Ready." FontSize="11"/>
        </Border>
    </Grid>
</Controls:MetroWindow>
'@

[xml]$mx = $mainXaml
$window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $mx))
$txtSiteCode    = $window.FindName('txtSiteCode')
$txtProvider    = $window.FindName('txtProvider')
$btnSaveProfile = $window.FindName('btnSaveProfile')
$toggleTheme    = $window.FindName('toggleTheme')
$txtThemeLabel  = $window.FindName('txtThemeLabel')
$panelTiles     = $window.FindName('panelTiles')
$txtStatus      = $window.FindName('txtStatus')

function Set-SuiteStatus {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Updates an in-window TextBlock only.')]
    param([Parameter(Mandatory)][string]$Text)
    $txtStatus.Text = $Text
}

Install-TitleBarDragFallback -Window $window

# Tiles are plain square buttons; Set-ButtonTheme themes them as the
# workflow-button set, so the launcher rides the shared palette.
$script:TileButtons = @()
$script:Tools = @(Get-InstalledTools)
foreach ($tool in $script:Tools) {
    $btn = New-Object System.Windows.Controls.Button
    $btn.Width = 168; $btn.Height = 64; $btn.Margin = '6,6,6,6'
    $btn.Style = $window.FindResource('MahApps.Styles.Button.Square')
    [MahApps.Metro.Controls.ControlsHelper]::SetContentCharacterCasing($btn, 'Normal')
    $stack = New-Object System.Windows.Controls.StackPanel
    $tbName = New-Object System.Windows.Controls.TextBlock
    $tbName.Text = $tool.Name; $tbName.FontSize = 13; $tbName.FontWeight = 'SemiBold'
    $tbName.TextAlignment = 'Center'; $tbName.TextWrapping = 'Wrap'
    $tbVer = New-Object System.Windows.Controls.TextBlock
    $tbVer.Text = if ($tool.Version) { 'v' + $tool.Version } else { '' }
    $tbVer.FontSize = 11; $tbVer.TextAlignment = 'Center'; $tbVer.Opacity = 0.7
    [void]$stack.Children.Add($tbName); [void]$stack.Children.Add($tbVer)
    $btn.Content = $stack
    $btn.Tag = $tool
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($btn, 'btnTool_' + $tool.Folder)
    # Panel content leaves the button nameless to UI Automation; screen
    # readers and automation both need the explicit name.
    $accName = if ($tool.Version) { '{0} v{1}' -f $tool.Name, $tool.Version } else { $tool.Name }
    [System.Windows.Automation.AutomationProperties]::SetName($btn, $accName)
    $btn.Add_Click({ param($s, $e) Start-SuiteTool -Tool $s.Tag })
    [void]$panelTiles.Children.Add($btn)
    $script:TileButtons += $btn
}

Initialize-SuiteTheme -Window $window `
    -IsDarkGetter { [bool]$global:Prefs['DarkMode'] } `
    -WorkflowButtons $script:TileButtons `
    -OptionsButtons @($btnSaveProfile)

$txtSiteCode.Text = [string]$global:Prefs['SiteCode']
$txtProvider.Text = [string]$global:Prefs['SMSProvider']

$btnSaveProfile.Add_Click({
    $global:Prefs['SiteCode']    = ([string]$txtSiteCode.Text).Trim()
    $global:Prefs['SMSProvider'] = ([string]$txtProvider.Text).Trim()
    $null = Save-SuiteSettings -Path $script:SettingsPath -Settings $global:Prefs
    Set-LaunchEnvironment
    Set-SuiteStatus 'Connection profile saved; new launches inherit it.'
})

$toggleTheme.Add_Toggled({
    $isDark = [bool]$toggleTheme.IsOn
    if ($isDark) { [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Dark.Steel'); $txtThemeLabel.Text = 'Dark Theme' }
    else         { [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Light.Blue'); $txtThemeLabel.Text = 'Light Theme' }
    $global:Prefs['DarkMode'] = $isDark
    $null = Save-SuiteSettings -Path $script:SettingsPath -Settings $global:Prefs
    Set-ButtonTheme
    Update-TitleBarBrushes
})

$window.Add_Closing({
    Save-WindowState -Window $window -Path $script:WindowStatePath
})

$window.Add_Loaded({
    Restore-WindowState -Window $window -Path $script:WindowStatePath
    $isDark = [bool]$global:Prefs['DarkMode']
    $toggleTheme.IsOn = $isDark
    if (-not $isDark) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Light.Blue')
        $txtThemeLabel.Text = 'Light Theme'
    }
    Set-ButtonTheme
    Update-TitleBarBrushes
    Set-SuiteStatus ('{0} tool(s) found under {1}. Site profile is handed to every launch.' -f $script:Tools.Count, (Get-SuiteToolsRoot))
})

[void]$window.ShowDialog()
