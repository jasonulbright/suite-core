<#
.SYNOPSIS
    Shared core module for the MECM tool suite.

.DESCRIPTION
    Vendored into each consumer tool at Lib\SuiteCommon\ by
    sync-suitecommon.ps1. Provides:
      - Structured logging (Initialize-Logging, Write-Log, Write-LogErrorRecord)
      - CM site connection management (Connect-CMSite, Disconnect-CMSite,
        Test-CMConnection, Get-CMConnectionInfo)
      - Flat JSON settings persistence (Read-SuiteSettings, Save-SuiteSettings)

    Consumers never edit the vendored copy; changes flow through the
    suite-core repository and re-sync.

.EXAMPLE
    # Top of a consumer tool module (Module\<Tool>Common.psm1):
    if (-not (Get-Module SuiteCommon)) {
        Import-Module (Join-Path $PSScriptRoot '..\Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking
    }
#>

# ---------------------------------------------------------------------------
# Module-scoped state
# ---------------------------------------------------------------------------

$script:__SuiteLogPath         = $null
$script:__SuiteVerbose         = $false
$script:OriginalLocation       = $null
$script:ConnectedSiteCode      = $null
$script:ConnectedSMSProvider   = $null
$script:ConnectedAt            = $null

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Initialize-Logging {
    <#
    .SYNOPSIS
        Sets the log file path and verbose behavior for Write-Log.

    .DESCRIPTION
        -Attach appends to an existing file instead of writing a fresh
        header (used by background runspaces that share the shell's log).
        Verbose diagnostics: the explicit switch wins; otherwise the
        SUITE_VERBOSE environment variable enables DEBUG console output
        unless it holds an explicit off value (0/false/no).
    #>
    param(
        [string]$LogPath,
        [switch]$Attach,
        [switch]$VerboseLogging
    )

    # A whitespace-only path reaches Set-Content as a filename Windows strips
    # to nothing and throws DirectoryNotFoundException; treat it as no path.
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) { $LogPath = $LogPath.Trim() } else { $LogPath = $null }

    $script:__SuiteLogPath = $LogPath

    $envVerbose = $env:SUITE_VERBOSE
    $script:__SuiteVerbose = [bool]$VerboseLogging -or
        (-not [string]::IsNullOrWhiteSpace($envVerbose) -and $envVerbose -notin @('0', 'false', 'no'))

    if ($LogPath) {
        $parentDir = Split-Path -Path $LogPath -Parent
        if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        if (-not $Attach) {
            $header = "[{0}] [INFO ] === Log initialized ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Set-Content -LiteralPath $LogPath -Value $header -Encoding UTF8
        }
    }

    if ($script:__SuiteVerbose) {
        Write-Log "Verbose logging enabled (DEBUG lines on console and in log file)." -Level DEBUG
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped, severity-tagged log message.

    .DESCRIPTION
        INFO  -> Write-Host (stdout)
        WARN  -> Write-Host (stdout)
        ERROR -> Write-Host (stdout) + $host.UI.WriteErrorLine (stderr)
        DEBUG -> log file always; console only when verbose logging is
                 enabled (Initialize-Logging -VerboseLogging or the
                 SUITE_VERBOSE environment variable).

        -Quiet suppresses all console output but still writes to the log file.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Write-Log is the single console-surfacing path; Write-Host is the deliberate contract so lines reach both the host and the file log.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification='Write-Log is the suite-wide logging contract on Windows PowerShell 5.1, which ships no Write-Log.')]
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',

        [switch]$Quiet
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formatted = "[{0}] [{1,-5}] {2}" -f $timestamp, $Level, $Message

    $suppressConsole = $Quiet -or ($Level -eq 'DEBUG' -and -not $script:__SuiteVerbose)

    if (-not $suppressConsole) {
        Write-Host $formatted

        if ($Level -eq 'ERROR') {
            $host.UI.WriteErrorLine($formatted)
        }
    }

    if ($script:__SuiteLogPath) {
        # Concurrent writers (a background runspace sharing the shell's log
        # via -Attach) collide on the per-line open/close and the sharing
        # violation silently drops the line - measured at 35-86% loss under
        # contention. A named mutex keyed on the path serializes every
        # SuiteCommon writer in the session; the retry loop still covers
        # non-SuiteCommon writers holding the file.
        $mutexName = 'SuiteCommonLog_' + ($script:__SuiteLogPath.ToLowerInvariant() -replace '[\\/:]', '_')
        $mutex = $null
        $owned = $false
        try {
            $mutex = New-Object System.Threading.Mutex($false, $mutexName)
            try { $owned = $mutex.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $owned = $true }
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    Add-Content -LiteralPath $script:__SuiteLogPath -Value $formatted -Encoding UTF8 -ErrorAction Stop
                    break
                }
                catch {
                    if ($attempt -lt 3) { Start-Sleep -Milliseconds 5 }
                }
            }
        }
        catch { $null = $_ }
        finally {
            if ($mutex) {
                if ($owned) { try { $mutex.ReleaseMutex() } catch { $null = $_ } }
                $mutex.Dispose()
            }
        }
    }
}

function Write-LogErrorRecord {
    <#
    .SYNOPSIS
        Logs full diagnostics for an ErrorRecord: exception chain, error id,
        failing file/line/statement, and the script stack trace.

    .DESCRIPTION
        Designed for catch blocks. The InvocationInfo position and
        ScriptStackTrace identify the exact line that threw, which a bare
        $_.Exception.Message never reveals.

    .PARAMETER Level
        Log level for the diagnostic lines. Default ERROR. Pass DEBUG when
        the caller already emits its own single ERROR summary line and the
        detail should only land in the log file.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [string]$Context = '',

        [ValidateSet('ERROR', 'WARN', 'DEBUG')]
        [string]$Level = 'ERROR'
    )

    if ($Context) {
        Write-Log ("Failure context              : {0}" -f $Context) -Level $Level
    }

    $ex = $ErrorRecord.Exception
    if ($ex) {
        Write-Log ("Exception                    : {0}: {1}" -f $ex.GetType().FullName, $ex.Message) -Level $Level
        $inner = $ex.InnerException
        while ($inner) {
            Write-Log ("Inner exception              : {0}: {1}" -f $inner.GetType().FullName, $inner.Message) -Level $Level
            $inner = $inner.InnerException
        }
    }

    Write-Log ("FullyQualifiedErrorId        : {0}" -f $ErrorRecord.FullyQualifiedErrorId) -Level $Level

    $ii = $ErrorRecord.InvocationInfo
    if ($ii) {
        if ($ii.ScriptName) {
            Write-Log ("Failing location             : {0}:{1}" -f $ii.ScriptName, $ii.ScriptLineNumber) -Level $Level
        }
        if ($ii.Line) {
            Write-Log ("Failing statement            : {0}" -f $ii.Line.Trim()) -Level $Level
        }
    }

    if ($ErrorRecord.ScriptStackTrace) {
        foreach ($frame in ($ErrorRecord.ScriptStackTrace -split "`r?`n")) {
            Write-Log ("Stack                        : {0}" -f $frame) -Level $Level
        }
    }
}

# ---------------------------------------------------------------------------
# CM Connection
# ---------------------------------------------------------------------------

function Resolve-ConfigurationManagerModulePath {
    <#
    .SYNOPSIS
        Locates ConfigurationManager.psd1 from the console install.

    .DESCRIPTION
        SMS_ADMIN_UI_PATH points at ...\AdminConsole\bin\i386; the module
        manifest lives at ...\AdminConsole\bin\ConfigurationManager.psd1.
        Split-Path gives a normalized parent: a literal '..' in the module
        path breaks the CM manifest's relative resolution of its nested
        submodules, and the first Get-CM* autoload then fails with
        "module could not be loaded".
    #>
    $candidates = @()

    if ($env:SMS_ADMIN_UI_PATH) {
        $candidates += (Join-Path (Split-Path -Parent $env:SMS_ADMIN_UI_PATH) 'ConfigurationManager.psd1')
    }

    $candidates += @(
        'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1',
        'C:\Program Files\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1',
        'C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin\ConfigurationManager.psd1',
        'C:\Program Files\Microsoft Endpoint Manager\AdminConsole\bin\ConfigurationManager.psd1'
    )

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Connect-CMSite {
    <#
    .SYNOPSIS
        Imports the ConfigurationManager module, ensures the site PSDrive,
        and sets location onto it.

    .DESCRIPTION
        The PSDrive is created with -Scope Global: a drive created inside
        this module's session state is invisible to callers and to sibling
        tool modules resolving the CMSite location (current location is
        runspace-shared; drive visibility is session-state-scoped). An
        existing drive that fails Set-Location (provider restart) is torn
        down and rebuilt from the provider. Saves the original location for
        Disconnect-CMSite. Returns $true on success, $false on failure.

    .PARAMETER SMSProvider
        SMS Provider machine. Optional: falls back to the SUITE_CM_PROVIDER
        environment variable, then to an existing drive's root.
    #>
    param(
        [Parameter(Mandatory)][string]$SiteCode,
        [Alias('ProviderMachineName')][string]$SMSProvider = '',
        [string]$CMModulePath = '',
        [switch]$SkipSiteVerification
    )

    # Capture only on a fresh connect: a reconnect/site-switch without an
    # intervening Disconnect-CMSite would otherwise overwrite the saved
    # location with the previous site's drive and lose the real origin.
    if (-not $script:ConnectedSiteCode) {
        $script:OriginalLocation = Get-Location
    }

    if (-not (Get-Module ConfigurationManager -ErrorAction SilentlyContinue)) {
        $resolved = if (-not [string]::IsNullOrWhiteSpace($CMModulePath)) { $CMModulePath } else { Resolve-ConfigurationManagerModulePath }

        if (-not $resolved -or -not (Test-Path -LiteralPath $resolved)) {
            Write-Log "ConfigurationManager module not found. Ensure the CM console is installed." -Level ERROR
            return $false
        }

        try {
            # -Global: this import runs in SuiteCommon's session state; without
            # it the CM cmdlets are visible only inside SuiteCommon, and every
            # consumer tool module's own Get-CM* calls fail with "term not
            # recognized" - the same visibility rule that forces -Scope Global
            # on the PSDrive below.
            Import-Module $resolved -Force -DisableNameChecking -Global -ErrorAction Stop
            Write-Log "Imported ConfigurationManager module from $resolved"
        }
        catch {
            Write-Log "Failed to import ConfigurationManager module: $_" -Level ERROR
            return $false
        }
    }

    $provider = $SMSProvider
    if ([string]::IsNullOrWhiteSpace($provider) -and -not [string]::IsNullOrWhiteSpace($env:SUITE_CM_PROVIDER)) {
        $provider = $env:SUITE_CM_PROVIDER.Trim()
    }

    # The CM module auto-creates the site PSDrive on import when the install
    # baked in DefaultSiteServerName. Only fall back to New-PSDrive when the
    # drive truly is not registered yet -- creating it while the CM module
    # is still half-initialized races the module's own provider setup and
    # surfaces as the Get-CM* autoload failure.
    $siteDrive = Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue

    if ($siteDrive -and -not [string]::IsNullOrWhiteSpace($provider) -and ([string]$siteDrive.Root -ne $provider)) {
        # Same site code bound to a different SMS Provider (the provider was
        # changed in a tool's options): rebind to the requested one. Stepping
        # off the drive first is mandatory - the drive you are located in
        # cannot be removed.
        Write-Log "PSDrive ${SiteCode}: points at '$($siteDrive.Root)', not '$provider' -- recreating." -Level WARN
        try { Set-Location -LiteralPath "$env:SystemDrive\" -ErrorAction SilentlyContinue } catch { $null = $_ }
        Remove-PSDrive -Name $SiteCode -PSProvider CMSite -Force -ErrorAction SilentlyContinue
        $siteDrive = $null
    }

    if ($siteDrive) {
        try {
            Set-Location "${SiteCode}:" -ErrorAction Stop
        }
        catch {
            # Entering an existing drive fails when its provider connection
            # is gone (e.g. provider restart). Tear it down and rebuild.
            Write-Log ("Set-Location {0}: failed on existing drive ({1}); recreating it." -f $SiteCode, $_.Exception.Message) -Level WARN
            if ([string]::IsNullOrWhiteSpace($provider)) { $provider = [string]$siteDrive.Root }
            try { Set-Location -LiteralPath "$env:SystemDrive\" -ErrorAction SilentlyContinue } catch { $null = $_ }
            Remove-PSDrive -Name $SiteCode -Force -ErrorAction SilentlyContinue
            $siteDrive = $null
        }
    }

    if (-not $siteDrive) {
        if ([string]::IsNullOrWhiteSpace($provider)) {
            Write-Log "No CMSite drive '$SiteCode' exists and no SMS provider machine was given (parameter or SUITE_CM_PROVIDER)." -Level ERROR
            return $false
        }

        try {
            New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $provider -Scope Global -ErrorAction Stop | Out-Null
            Write-Log "Created PSDrive for site $SiteCode -> $provider"
        }
        catch {
            Write-Log "Failed to create PSDrive for site $SiteCode : $_" -Level ERROR
            return $false
        }

        try {
            Set-Location "${SiteCode}:" -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to enter site drive $SiteCode : $_" -Level ERROR
            return $false
        }
    }

    if (-not $SkipSiteVerification) {
        try {
            $site = Get-CMSite -SiteCode $SiteCode -ErrorAction Stop
            Write-Log "Connected to site $SiteCode ($($site.SiteName))"
        }
        catch {
            Write-Log "Failed to connect to site $SiteCode : $_" -Level ERROR
            return $false
        }
    }
    else {
        Write-Log "Connected to CM site: $SiteCode"
    }

    if ([string]::IsNullOrWhiteSpace($provider)) {
        $drive = Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue
        if ($drive) { $provider = [string]$drive.Root }
    }

    $script:ConnectedSiteCode    = $SiteCode
    $script:ConnectedSMSProvider = $provider
    $script:ConnectedAt          = Get-Date
    return $true
}

function Disconnect-CMSite {
    <#
    .SYNOPSIS
        Restores the original location saved by Connect-CMSite and clears
        the recorded connection.
    #>
    if ($script:OriginalLocation) {
        try { Set-Location $script:OriginalLocation -ErrorAction SilentlyContinue } catch { $null = $_ }
    }
    $script:ConnectedSiteCode    = $null
    $script:ConnectedSMSProvider = $null
    $script:ConnectedAt          = $null
    Write-Log "Disconnected from CM site"
}

function Test-CMConnection {
    <#
    .SYNOPSIS
        Returns $true if currently connected to a CM site.
    #>
    if (-not $script:ConnectedSiteCode) { return $false }

    try {
        $drive = Get-PSDrive -Name $script:ConnectedSiteCode -PSProvider CMSite -ErrorAction Stop
        return ($null -ne $drive)
    }
    catch {
        return $false
    }
}

function Get-CMConnectionInfo {
    <#
    .SYNOPSIS
        Returns the recorded connection (SiteCode, SMSProvider, ConnectedAt)
        or $null when not connected.

    .DESCRIPTION
        Consumers that need the connected site code or provider for their
        own CIM/WMI queries read it here instead of reaching into module
        state that a module split would hide from them.
    #>
    if (-not $script:ConnectedSiteCode) { return $null }

    return [pscustomobject]@{
        SiteCode    = $script:ConnectedSiteCode
        SMSProvider = $script:ConnectedSMSProvider
        ConnectedAt = $script:ConnectedAt
    }
}

function Test-CMSiteCodeMatchesProvider {
    <#
    .SYNOPSIS
        Asks the SMS Provider which site code(s) it actually serves.

    .DESCRIPTION
        Queries root\sms:SMS_ProviderLocation on the provider machine. A
        CMSite PSDrive whose NAME does not match a real site code on its
        Root server connects fine, but every subsequent CM cmdlet fails
        with "Key cannot be null. Parameter name: key". Returns $null when
        the query itself fails (offline provider, no WMI rights).
    #>
    param(
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$ProviderMachineName
    )

    try {
        $locations = @(Get-CimInstance -ComputerName $ProviderMachineName -Namespace 'root\sms' -ClassName 'SMS_ProviderLocation' -ErrorAction Stop)
        $codes = @($locations | ForEach-Object { [string]$_.SiteCode } | Where-Object { $_ } | Select-Object -Unique)
        if ($codes.Count -eq 0) { return $null }

        return [pscustomobject]@{
            Match     = ($codes -contains $SiteCode)
            SiteCodes = $codes
        }
    }
    catch {
        Write-Log ("Provider site-code query failed for {0}: {1}" -f $ProviderMachineName, $_.Exception.Message) -Level DEBUG
        return $null
    }
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

function Read-SuiteSettings {
    <#
    .SYNOPSIS
        Reads a flat JSON settings file over a defaults hashtable.

    .DESCRIPTION
        Returns a hashtable seeded from Defaults; any top-level key present
        in both the file and Defaults overwrites the default. Keys in the
        file that Defaults does not declare are ignored, so stale settings
        cannot smuggle unexpected state into a tool. A missing or
        unreadable file returns the defaults unchanged.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Reads the full settings hashtable by design.')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Defaults
    )

    $settings = @{}
    foreach ($k in $Defaults.Keys) { $settings[$k] = $Defaults[$k] }

    if (Test-Path -LiteralPath $Path) {
        try {
            # -Encoding UTF8: on 5.1 the default decoder mangles non-ASCII in
            # BOM-less UTF-8 files (hand-edited settings) without any error.
            $loaded = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($k in @($settings.Keys)) {
                $val = $loaded.$k
                if ($null -ne $val) { $settings[$k] = $val }
            }
        } catch { $null = $_ }
    }

    return $settings
}

function Save-SuiteSettings {
    <#
    .SYNOPSIS
        Writes a settings hashtable to a JSON file. Returns $true on
        success, $false on failure (failure is logged, never thrown -
        losing a preference write must not take the tool down).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Writes the full settings hashtable by design.')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Settings,
        [int]$Depth = 5
    )

    try {
        $parentDir = Split-Path -Path $Path -Parent
        if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force -ErrorAction Stop | Out-Null
        }
        # -ErrorAction Stop: Set-Content fails non-terminating by default,
        # which would skip the catch and report success on a failed write.
        $Settings | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log ("Failed to save settings to {0}: {1}" -f $Path, $_.Exception.Message) -Level WARN -Quiet
        return $false
    }
}

# ---------------------------------------------------------------------------
# Module identity
# ---------------------------------------------------------------------------

function Get-SuiteCommonVersion {
    <#
    .SYNOPSIS
        Returns this vendored copy's ModuleVersion string.
    #>
    $psd1 = Join-Path $PSScriptRoot 'SuiteCommon.psd1'
    try {
        return [string](Import-PowerShellDataFile -LiteralPath $psd1).ModuleVersion
    }
    catch {
        return ''
    }
}
