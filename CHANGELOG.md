# Changelog

## [0.4.9] - 2026-09-04

### Installer

- Carry app-packager 1.5.1.6; the other eleven components are unchanged.

## [0.4.8] - 2026-09-04

### Installer

- Carry app-packager 1.5.1.5 and installer-analysis 1.3.3.0; the other ten components are unchanged.

## [0.4.7] - 2026-09-04

### Installer

- **Component refresh.** The suite installer carries app-packager 1.5.1.4
  (install mode toggle for switchable installers in the drop preview) and
  installer-analysis 1.3.2.0 (both install modes reported for NSIS and
  Inno Setup installers that accept a mode switch). The other ten
  components are unchanged from 0.4.6. Component versions and commits are
  in `suite-manifest.json` as before.

## [0.4.6] - 2026-09-04

### Build

- **Component release guard.** `build-suite-installer.ps1` refuses to
  build unless every component repository is clean, checked out at its
  highest `v*` tag, and that tag's version equals the version the payload
  carries; the tag must also exist on origin and have a GitHub release
  (`-SkipReleaseCheck` waives the two remote checks for an offline build).
  A component bumped but never released, or a stale checkout of one that
  was, stops the build with the component and the two versions named.
  `-ValidateOnly` runs the checks for all twelve components and stops
  before compiling.

### Installer

- **Component refresh.** The suite installer carries the same eleven
  tool versions as 0.4.5; only the launcher (this repository) changed.

## [0.4.5] - 2026-09-04

### Installer

- **Component refresh.** The suite installer carries app-packager 1.5.1.3
  (the Options window reports how GitHub API calls authenticate, and a
  signed-in GitHub CLI login is used for those calls). The other eleven
  components are unchanged from 0.4.4. Component versions and commits are
  in `suite-manifest.json` as before.

## [0.4.4] - 2026-09-04

### Installer

- **Component refresh.** The suite installer carries app-packager 1.5.1.2
  (Slack staged as the vendor's MSIX, Defraggler and ShareX following their
  vendors' source changes, Wireshark staged from its compiled installer
  script, GitHub API calls authenticated through `GITHUB_TOKEN`). The other
  eleven components are unchanged from 0.4.3. Component versions and
  commits are in `suite-manifest.json` as before.

## [0.4.3] - 2026-09-04

### SuiteCommon

- **`Repair-WindowsPowerShellModulePath`.** A Windows PowerShell process
  launched from PowerShell 7 inherits the 7.x module directories at the
  front of `PSModulePath`; every runspace opened later and every child
  `powershell.exe` then autoloads a `Microsoft.PowerShell.Utility` that
  carries no `Get-FileHash` or `ConvertFrom-Json` in 5.1. The module
  strips those roots and puts `$PSHOME\Modules` first at import time, so
  every tool that imports SuiteCommon is covered before it opens a
  runspace; `New-SuiteBgRunspace` repeats the repair before it creates
  the runspace.
- **Bootstrap failures throw.** `New-SuiteBgRunspace` disposes the
  runspace and rethrows when the module import inside it fails, instead
  of handing back a runspace whose later commands fail as unknown.

### Installer

- **Component refresh.** The suite installer carries app-packager
  1.5.1.1 (Inno Setup drops read from the compiled header, Apache
  NetBeans packager, the per-user misclassification of Inno Setup 6
  stubs fixed), installer-analysis 1.3.1.0 (Inno Setup header decoding
  for data versions 5.x through 7.0.0.3), site-hygiene 0.8.1,
  collection-and-compliance-manager 1.0.2, collection-manager 1.2.3,
  deployment-helper 1.2.3, detection-tester 1.2.3, dp-content-manager
  1.2.3, maintenance-window-manager 1.2.3, mecm-health-dashboard 1.3.3
  and supersedence-auditor 1.0.1; every component vendors SuiteCommon
  0.4.3 (supersedence-auditor carries the same repair inline), and the
  version labels of every tool read their entry script header.
  Component versions and commits are in `suite-manifest.json` as before.

## [0.4.2] - 2026-09-04

### Installer

- **Component refresh.** The suite installer carries app-packager
  1.5.1.0 (NSIS installers analyzed from their compiled script, per-user
  drops staged as user-context deployments, PowerShell 7 module-path
  isolation, window sizing) and installer-analysis 1.3.0.1 (NSIS header
  decoding, analysis runspace module-path fix). Component versions and
  commits are in `suite-manifest.json` as before.

### Build

- **Entry-header drift guard.** `Get-ComponentVersion` warns when a
  component's entry script `Version` header disagrees with its version
  of record, so a stale header cannot ship inside the payload unnoticed.

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
