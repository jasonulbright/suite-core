<#
.SYNOPSIS
    Vendors SuiteCommon into consumer repos and reports drift.

.DESCRIPTION
    Copies SuiteCommon\SuiteCommon.psd1/.psm1 from this repository into each
    consumer's Lib\SuiteCommon\. Content hashes decide staleness, so both
    version drift and local edits to a vendored copy are caught. -Check
    compares without copying and exits 1 on any drift so the check can gate
    a release.

.EXAMPLE
    .\sync-suitecommon.ps1
    .\sync-suitecommon.ps1 -Check
    .\sync-suitecommon.ps1 -Consumer 'C:\projects\dp-content-manager'
#>
param(
    [string[]]$Consumer = @(),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

if (-not $Consumer -or $Consumer.Count -eq 0) {
    $projectsRoot = Split-Path -Parent $PSScriptRoot
    $Consumer = @(
        (Join-Path $projectsRoot 'dp-content-manager'),
        (Join-Path $projectsRoot 'collection-manager'),
        (Join-Path $projectsRoot 'site-hygiene')
    )
}

$sourceDir = Join-Path $PSScriptRoot 'SuiteCommon'
$files = @('SuiteCommon.psd1', 'SuiteCommon.psm1')

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $f))) {
        throw "Source file missing: $(Join-Path $sourceDir $f)"
    }
}

$version = ''
try { $version = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $sourceDir 'SuiteCommon.psd1')).ModuleVersion } catch { $null = $_ }
Write-Host ("SuiteCommon {0}" -f $version)

$drift = $false
$failures = 0
foreach ($c in $Consumer) {
    if (-not (Test-Path -LiteralPath $c -PathType Container)) {
        Write-Host ("SKIP   {0} (consumer path not found or not a directory)" -f $c)
        continue
    }
    $dest = Join-Path $c 'Lib\SuiteCommon'
    foreach ($f in $files) {
        $s = Join-Path $sourceDir $f
        $d = Join-Path $dest $f
        # Per-file isolation: one locked or misconfigured consumer must not
        # abort the remaining consumers in the list.
        try {
            $sHash = (Get-FileHash -LiteralPath $s -Algorithm SHA256).Hash
            $dHash = if (Test-Path -LiteralPath $d) { (Get-FileHash -LiteralPath $d -Algorithm SHA256).Hash } else { '' }

            if ($sHash -eq $dHash) {
                Write-Host ("OK     {0}" -f $d)
                continue
            }

            $drift = $true
            if ($Check) {
                Write-Host ("DRIFT  {0}" -f $d)
            }
            else {
                if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                Copy-Item -LiteralPath $s -Destination $d -Force
                Write-Host ("SYNCED {0}" -f $d)
            }
        }
        catch {
            $failures++
            Write-Host ("FAILED {0}: {1}" -f $d, $_.Exception.Message)
        }
    }
}

# Exit codes: 2 = at least one file failed to process (real error); 1 =
# -Check found drift; 0 = clean. Failure outranks drift so a gate cannot
# read a locked file as "drift found".
if ($failures -gt 0) { exit 2 }
if ($Check -and $drift) { exit 1 }
