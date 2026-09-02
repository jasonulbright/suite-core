<#
.SYNOPSIS
    Builds the AppPackager Suite all-in-one NSIS installer.

.DESCRIPTION
    Stages the payload from the local sibling repositories at their current
    HEAD via git archive, writes suite-manifest.json describing the suite and
    each component, compiles installer\suite.nsi with makensis, and emits
    SuiteSetup-<version>.exe plus checksums.txt into installer\out.

    Test files are stripped from the payload: nothing under a Tests folder and
    no *.Tests.ps1 file reaches a shipped artifact.

.PARAMETER SuiteVersion
    Suite version stamped into the installer, the manifest and the file name.
    Defaults to the build date as yyyy.MM.dd.

.PARAMETER MakeNsis
    Path to makensis.exe.

.PARAMETER KeepStage
    Leave the staging folder in place for inspection.
#>
[CmdletBinding()]
param(
    [string]$SuiteVersion,
    [string]$MakeNsis = 'C:\Program Files (x86)\NSIS\makensis.exe',
    [switch]$KeepStage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot     = Split-Path -Parent $PSScriptRoot
$InstallerDir = Join-Path $RepoRoot 'installer'
$OutDir       = Join-Path $InstallerDir 'out'
$StageRoot    = Join-Path $InstallerDir 'stage'
$NsiPath      = Join-Path $InstallerDir 'suite.nsi'
$SiblingRoot  = Split-Path -Parent $RepoRoot

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('[build] ' + $Message)
}

function Get-ChangelogVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $Path -TotalCount 40)) {
        if ($line -match '^##\s+\[?([0-9][0-9\.]*[0-9])\]?') { return $Matches[1] }
    }
    return $null
}

function Get-ManifestVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match "ModuleVersion\s*=\s*'([^']+)'") { return $Matches[1] }
    }
    return $null
}

function Get-ScriptHeaderVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $Path -TotalCount 80)) {
        if ($line -match '^\s*Version\s*:\s*([0-9][0-9\.]*[0-9])\s*$') { return $Matches[1] }
    }
    return $null
}

function Export-RepoHead {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        throw ('Not a git repository: ' + $RepoPath)
    }
    $zip = Join-Path ([IO.Path]::GetTempPath()) ('suitestage-' + [Guid]::NewGuid().ToString('N') + '.zip')
    try {
        & git -C $RepoPath archive --format=zip -o $zip HEAD
        if ($LASTEXITCODE -ne 0) { throw ('git archive failed for ' + $RepoPath) }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $Destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    }
}

function Remove-TestArtifact {
    param([Parameter(Mandatory)][string]$Root)
    $removed = 0
    foreach ($dir in @(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Filter 'Tests' -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath $dir.FullName) {
            $removed += @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File).Count
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force
        }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $file.FullName -Force
        $removed++
    }
    return $removed
}

function Get-HeadCommit {
    param([Parameter(Mandatory)][string]$RepoPath)
    $sha = (& git -C $RepoPath rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw ('git rev-parse failed for ' + $RepoPath) }
    return $sha.Trim()
}

if ([string]::IsNullOrWhiteSpace($SuiteVersion)) {
    $SuiteVersion = (Get-Date).ToString('yyyy.MM.dd')
}
if ($SuiteVersion -notmatch '^[0-9][0-9A-Za-z\.\-]*$') {
    throw ('Unusable suite version: ' + $SuiteVersion)
}
if (-not (Test-Path -LiteralPath $MakeNsis)) {
    throw ('makensis.exe not found: ' + $MakeNsis)
}
if (-not (Test-Path -LiteralPath $NsiPath)) {
    throw ('Installer script not found: ' + $NsiPath)
}

$components = @(
    [pscustomobject]@{ Name = 'app-packager'; Path = Join-Path $SiblingRoot 'app-packager'; Entry = 'start-apppackager.ps1' }
    [pscustomobject]@{ Name = 'site-hygiene'; Path = Join-Path $SiblingRoot 'site-hygiene'; Entry = 'start-sitehygiene.ps1' }
    [pscustomobject]@{ Name = 'suite-core';   Path = $RepoRoot;                             Entry = 'start-suite.ps1' }
)
foreach ($component in $components) {
    if (-not (Test-Path -LiteralPath $component.Path)) {
        throw ('Component repository missing: ' + $component.Path)
    }
}

if (Test-Path -LiteralPath $StageRoot) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }
New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$manifestComponents = New-Object System.Collections.Generic.List[object]

foreach ($component in $components) {
    Write-Step ('Staging ' + $component.Name + ' from ' + $component.Path)
    $dest = Join-Path $StageRoot $component.Name
    Export-RepoHead -RepoPath $component.Path -Destination $dest

    $stripped = Remove-TestArtifact -Root $dest
    if ($stripped -gt 0) { Write-Step ('  removed ' + $stripped + ' test file(s) from the payload') }

    $entryPath = Join-Path $dest $component.Entry
    if (-not (Test-Path -LiteralPath $entryPath)) {
        throw ('Entry script missing from payload: ' + $entryPath)
    }

    switch ($component.Name) {
        'app-packager' { $version = Get-ScriptHeaderVersion -Path $entryPath }
        'site-hygiene' { $version = Get-ChangelogVersion -Path (Join-Path $dest 'CHANGELOG.md') }
        default {
            # SuiteCommon.psd1 is the launcher's own version of record; the
            # CHANGELOG headline can trail it between releases.
            $version = Get-ManifestVersion -Path (Join-Path $dest 'SuiteCommon\SuiteCommon.psd1')
            if (-not $version) { $version = Get-ChangelogVersion -Path (Join-Path $dest 'CHANGELOG.md') }
        }
    }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw ('Could not determine a version for ' + $component.Name)
    }

    $fileCount = @(Get-ChildItem -LiteralPath $dest -Recurse -File).Count
    Write-Step ('  version ' + $version + ', ' + $fileCount + ' file(s)')

    $manifestComponents.Add([ordered]@{
        name    = $component.Name
        version = $version
        commit  = (Get-HeadCommit -RepoPath $component.Path)
        entry   = $component.Entry
        files   = $fileCount
    })
}

$manifest = [ordered]@{
    suite      = 'AppPackager Suite'
    version    = $SuiteVersion
    built      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    components = $manifestComponents.ToArray()
}
$manifestPath = Join-Path $StageRoot 'suite-manifest.json'
($manifest | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $manifestPath -Encoding ASCII
Write-Step ('Wrote ' + $manifestPath)

$outFile = Join-Path $OutDir ('SuiteSetup-' + $SuiteVersion + '.exe')
if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }

Write-Step ('Compiling ' + $NsiPath)
& $MakeNsis `
    ('/DSUITEVERSION=' + $SuiteVersion) `
    ('/DPAYLOADDIR=' + $StageRoot) `
    ('/DOUTFILE=' + $outFile) `
    $NsiPath
if ($LASTEXITCODE -ne 0) { throw ('makensis failed with exit code ' + $LASTEXITCODE) }
if (-not (Test-Path -LiteralPath $outFile)) { throw ('makensis produced no output at ' + $outFile) }

$hash = (Get-FileHash -LiteralPath $outFile -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item -LiteralPath $outFile).Length
$checksums = Join-Path $OutDir 'checksums.txt'
($hash + '  ' + (Split-Path -Leaf $outFile)) | Set-Content -LiteralPath $checksums -Encoding ASCII

if (-not $KeepStage) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }

Write-Step ('Output  : ' + $outFile)
Write-Step ('Size    : ' + [Math]::Round($size / 1MB, 2) + ' MB (' + $size + ' bytes)')
Write-Step ('SHA256  : ' + $hash)
Write-Step ('Checksum: ' + $checksums)
