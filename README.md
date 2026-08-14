# Suite Core

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
