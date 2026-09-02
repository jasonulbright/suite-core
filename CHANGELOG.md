# Changelog

## [0.4.1] - 2026-09-02

Supersedes the unreleased 0.4.0 entry, whose installer carried three
components; the shipping installer carries twelve.

### Installer

- **`installer\suite.nsi`** - all-in-one NSIS installer for all twelve
  suite components: the launcher (`suite-core\`), `app-packager\`,
  `site-hygiene\`, `collection-and-compliance-manager\`,
  `collection-manager\`, `deployment-helper\`, `detection-tester\`,
  `dp-content-manager\`, `installer-analysis\`,
  `maintenance-window-manager\`, `mecm-health-dashboard\` and
  `supersedence-auditor\`. `RequestExecutionLevel user`, no elevation,
  install root `%LOCALAPPDATA%\AppPackagerSuite` with one subfolder per
  component. Start-menu group "AppPackager Suite" carries twelve
  shortcuts, each targeting the native `System32` `powershell.exe` with
  `-NoProfile -ExecutionPolicy Bypass -File <entry>.ps1`. HKCU ARP entry
  (`DisplayName`, `DisplayVersion`, `Publisher`, `InstallLocation`,
  `UninstallString`, `QuietUninstallString`, `EstimatedSize`, `NoModify`,
  `NoRepair`). `/S` silent install and uninstall.
- **Upgrade preserves user state without a backup-restore cycle.** Payload
  files overwrite; files absent from the payload are untouched, and every
  preserved class (`*.json` per app folder and its `Packagers` subfolder,
  `Logs\`, `Packagers\Icons\`) is absent from the payload because each is
  gitignored in its source repository. Same preserve set as
  app-packager's `install.ps1` `Get-PreservedStateFile`, reached without
  copying state out and back.

### Build

- **`tools\build-suite-installer.ps1`** - stages the payload from the
  local sibling repositories at HEAD via `git archive`, strips `Tests`
  folders and `*.Tests.ps1` from the payload, reads each component
  version, writes `suite-manifest.json` (suite version, plus
  name/version/versionSource/commit/entry/shortcut/file-count per
  component), compiles with `makensis`, and emits
  `SuiteSetup-<version>.exe` and `checksums.txt` into `installer\out\`.
  Suite version defaults to `yyyy.MM.dd`; `-SuiteVersion` overrides.
- **One component table drives the whole build.** `$Components` carries
  folder, repository, entry script, shortcut name and version source per
  row; staging, the manifest, and the generated `components.nsh` that
  `suite.nsi` includes all read it, so adding a tool is one row rather
  than edits in three places. `suite.nsi` names no component.
- **Version source is per component and recorded in the manifest.**
  `ScriptHeader` for app-packager, `ModuleManifest` for suite-core,
  `Changelog` for the other ten - the header `Version` line in the tool
  repositories trails their CHANGELOG headline.

### Changed

- **Uninstall preserves user state.** The uninstaller deletes only the
  files the build shipped (a generated per-file list), removes
  directories non-recursively, and leaves preferences, logs, icons, and
  anything else written after install in place.

## [0.3.2] - 2026-09-01

### Fixed

- **Launcher** - maximized-window restore and background bootstrap
  errors surfaced instead of swallowed. (Entry backfilled; the release
  shipped without one.)

## [0.3.1] - 2026-08-16

### Added

- **`Connect-CMSite` regains the site-code mismatch diagnostic** for
  every consumer: under verbose logging, a drive whose provider serves
  different site codes is called out with the "Key cannot be null"
  explanation instead of leaving later CM cmdlets to fail opaquely.

## [0.3.0] - 2026-08-16

### Additions

- **Suite launcher (`start-suite.ps1`).** Thin WPF shell: one tile per
  installed suite tool (discovered as sibling folders, version read from
  each tool's CHANGELOG with a manifest fallback), each launching as its
  own process. The connection profile (site code + SMS provider) is
  entered once and handed to every launch via `SUITE_CM_PROVIDER` /
  `SUITE_CM_SITECODE`; `Connect-CMSite` already falls back to the
  provider variable. MahApps assemblies vendored under `Lib\`.
- **Background-work helpers.** `New-SuiteBgRunspace` (STA runspace with
  tool-module pre-import and attached logging), `Stop-SuiteBgWork`
  (`BeginStop` into a reaped graveyard instead of a synchronous `Stop()`
  that blocks the UI thread while a pipeline is stuck inside a provider
  call), `Close-SuiteBgRunspace` (`CloseAsync` at shell exit).
  Explicit-argument by design: shells keep their own pipeline state.
- **CM collection widgets.** `Build-CollectionTree` (folder-nested,
  filterable) and `Show-CollectionPickerDialog` (modal picker over the
  tree). The tree builder fixes a latent defect in the consumers'
  originals: the populate scriptblock's boolean no longer leaks into the
  pipeline ahead of the returned leaf count.

## [0.2.0] - 2026-08-16

### Additions

- **Window chrome.** Native title-bar drag (`Install-TitleBarDragFallback`
  and the WM_NCHITTEST hook family) with hook state owned by the module,
  and window-state persistence (`Save-WindowState` /
  `Restore-WindowState`) with a clamp-to-nearest-monitor restore and a
  `RestoreBounds`-aware save.
- **Theming.** `Initialize-SuiteTheme` stores the per-shell context
  (standard palette with overrides, view buttons, dark/active-view
  getters); `Update-TitleBarBrushes`, `Update-SidebarButtonTheme`
  (fill- and border-based active modes), `Set-ButtonTheme`, and
  `Set-DialogTheme` read it.
- **Themed dialogs.** `Show-ThemedMessage` (OK / OKCancel / YesNo,
  glyph-only icons, Escape closes OK-only dialogs) and
  `Show-ConfirmDialog`, both themed from their owner window.

### Fixed

- **Hook-state leak on window close.** Removal keyed on the HWND, which
  is already destroyed when `Closed` fires, so the delegate and window
  reference of every hooked window stayed rooted for the process
  lifetime; removal now sweeps by window reference.
- **Never-shown windows crashed the save path.** Non-finite geometry
  (NaN / Empty rect) skips the save instead of throwing from the
  caller's `Closing` handler.

## [0.1.0] - 2026-08-14

### Additions

- **`SuiteCommon` module, first release.** Logging (`Initialize-Logging`
  with `-Attach` and `-VerboseLogging`, four-level `Write-Log` with
  `SUITE_VERBOSE` gating for DEBUG, `Write-LogErrorRecord` full-diagnostic
  catch-block logging), CM site connection (`Connect-CMSite` with
  globally scoped PSDrive creation, stale-drive rebuild, multi-path
  console module resolution, optional `Get-CMSite` verification;
  `Disconnect-CMSite`; `Test-CMConnection`; `Get-CMConnectionInfo`;
  `Test-CMSiteCodeMatchesProvider` mismatch diagnostic), flat JSON
  settings persistence (`Read-SuiteSettings`, `Save-SuiteSettings`), and
  `Get-SuiteCommonVersion`.
- **`sync-suitecommon.ps1`.** Vendors the module into consumer repos at
  `Lib\SuiteCommon\`; `-Check` reports content-hash drift and exits
  nonzero so it can gate releases.
