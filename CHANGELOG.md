# Changelog

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
