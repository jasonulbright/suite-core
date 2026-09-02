# Suite Core

[![Latest release](https://img.shields.io/github/v/release/jasonulbright/suite-core?label=release)](https://github.com/jasonulbright/suite-core/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/jasonulbright/suite-core/total?label=downloads)](https://github.com/jasonulbright/suite-core/releases)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4)](#requirements)
[![License](https://img.shields.io/github/license/jasonulbright/suite-core)](LICENSE)

Shared core module (`SuiteCommon`) for a family of MECM (Configuration
Manager) admin tools. Each consumer tool carries a vendored copy at
`Lib\SuiteCommon\` so every tool stays fully standalone — no module
installation, no gallery dependency.

## What SuiteCommon provides

| Area | Functions |
|---|---|
| Logging | `Initialize-Logging` (`-Attach`, `-VerboseLogging`), `Write-Log` (INFO/WARN/ERROR/DEBUG, `-Quiet`), `Write-LogErrorRecord` |
| CM connection | `Connect-CMSite`, `Disconnect-CMSite`, `Test-CMConnection`, `Get-CMConnectionInfo`, `Resolve-ConfigurationManagerModulePath`, `Test-CMSiteCodeMatchesProvider` |
| Settings | `Read-SuiteSettings` (flat defaults merge), `Save-SuiteSettings` |
| Window chrome | `Install-TitleBarDragFallback` (+ the WM_NCHITTEST hook family), `Save-WindowState`, `Restore-WindowState` |
| Theming | `Initialize-SuiteTheme`, `Update-TitleBarBrushes`, `Update-SidebarButtonTheme`, `Set-ButtonTheme`, `Set-DialogTheme` |
| Dialogs | `Show-ThemedMessage`, `Show-ConfirmDialog` |
| Background work | `New-SuiteBgRunspace`, `Stop-SuiteBgWork`, `Close-SuiteBgRunspace` |
| CM widgets | `Build-CollectionTree`, `Show-CollectionPickerDialog` |
| Identity | `Get-SuiteCommonVersion` |

`Connect-CMSite` imports the ConfigurationManager module (from
`SMS_ADMIN_UI_PATH` or known console install paths), creates the site
PSDrive with `-Scope Global` so sibling modules can resolve the CMSite
location, rebuilds a stale drive whose provider connection died, and
verifies the site with `Get-CMSite` (skippable via
`-SkipSiteVerification`). DEBUG console output enables via
`Initialize-Logging -VerboseLogging` or the `SUITE_VERBOSE` environment
variable; a provider machine can be supplied via parameter or
`SUITE_CM_PROVIDER`.

## Launcher

![Suite launcher](docs/launcher.png)

`start-suite.ps1` is a thin WPF shell: one tile per installed suite
tool, discovered as sibling folders of this repository (override the
root in `suite.settings.json`), with each tool's version read from its
CHANGELOG. Every tile launches its tool as a separate process. The
connection profile — site code and SMS provider — is entered once and
handed to each launch through the `SUITE_CM_PROVIDER` /
`SUITE_CM_SITECODE` environment variables; `Connect-CMSite` falls back
to the provider variable, so tools connect without per-tool
configuration. The launcher embeds no tools and hosts no plugins.

## All-in-one installer

`installer\suite.nsi` builds `SuiteSetup-<version>.exe`, a single
installer carrying every suite tool plus this repository (the launcher
and `SuiteCommon`). Twelve components ship:

| Component | Folder | Entry script |
| --- | --- | --- |
| AppPackager Suite Launcher | `suite-core\` | `start-suite.ps1` |
| App Packager | `app-packager\` | `start-apppackager.ps1` |
| Site Hygiene | `site-hygiene\` | `start-sitehygiene.ps1` |
| Collection and Compliance Manager | `collection-and-compliance-manager\` | `start-ccm.ps1` |
| Collection Manager | `collection-manager\` | `start-collectionmanager.ps1` |
| Deployment Helper | `deployment-helper\` | `start-deploymenthelper.ps1` |
| Detection Method Tester | `detection-tester\` | `start-detectiontester.ps1` |
| DP Content Manager | `dp-content-manager\` | `start-dpcontentmgr.ps1` |
| Installer Analysis | `installer-analysis\` | `start-installeranalysis.ps1` |
| Maintenance Window Manager | `maintenance-window-manager\` | `start-maintenancewindowmgr.ps1` |
| MECM Health Dashboard | `mecm-health-dashboard\` | `start-mecmhealthdashboard.ps1` |
| Supersedence and Dependency Auditor | `supersedence-auditor\` | `start-supersedenceauditor.ps1` |

The component list lives in one table in
`tools\build-suite-installer.ps1`. That table drives staging, the
manifest, and the generated `components.nsh` that `suite.nsi` includes,
so adding a tool is one row.

```powershell
.\tools\build-suite-installer.ps1                        # version = build date
.\tools\build-suite-installer.ps1 -SuiteVersion 1.0.0    # explicit version
```

The build stages each component from the local sibling repository at its
current commit, so it packages what is checked in, not what is sitting
dirty in the working tree. Output lands in `installer\out\` along with
`checksums.txt`.

What the installer does:

- **Installs per user, with no elevation prompt.** Everything goes to
  `%LOCALAPPDATA%\AppPackagerSuite\`, one folder per component, and the
  Add/Remove Programs entry is written under `HKCU`. Nothing touches
  `Program Files`, the machine registry, or another user's profile.
- **Creates a start-menu group, "AppPackager Suite"**, with a shortcut
  for each of the eleven tools and one for the launcher. Each shortcut runs
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <entry>.ps1`,
  so the tools start regardless of the machine's execution policy without
  changing that policy for anything else.
- **Writes `suite-manifest.json`** at the install root, recording the
  suite version and the version and commit of each bundled component.
- **Supports `/S`** for a silent install, and the uninstaller supports it
  too.

### Upgrading

Run the newer installer over the existing install. Files that ship in the
package are replaced; files that do not ship are left alone. That covers
your settings and window state (`*.json`), the `Logs\` folders, and the
downloaded icon pack at `app-packager\Packagers\Icons\` - all of them
survive an upgrade untouched.

Uninstalling is different: it deletes the whole install root, user state
included. Copy anything you want to keep out of
`%LOCALAPPDATA%\AppPackagerSuite\` before uninstalling.

### The SmartScreen warning

The installer is not code-signed. The first time you run a new build,
Windows will likely show a blue "Windows protected your PC" box that
hides the Run button behind **More info**. This is Windows saying it has
not seen this exact file before, not that it found anything wrong with
it. Compare the file's SHA-256 against the `checksums.txt` published with
it, then choose **More info** followed by **Run anyway**. The warning
returns for each new build, because every build is a new file.

## Consuming

A tool module loads its vendored copy once, globally:

```powershell
if (-not (Get-Module SuiteCommon)) {
    Import-Module (Join-Path $PSScriptRoot '..\Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking
}
```

Consumers never edit the vendored copy. Changes land in this repository
and re-vendor via the sync script:

```powershell
.\sync-suitecommon.ps1          # copy current core into consumers
.\sync-suitecommon.ps1 -Check   # report drift, exit 1 if any
```

Drift detection is content-hash based, so both version skew and local
edits to a vendored copy are caught.

## Requirements

- Windows PowerShell 5.1
- Configuration Manager console for the CM connection functions
  (logging and settings work without it)

## License

MIT.
