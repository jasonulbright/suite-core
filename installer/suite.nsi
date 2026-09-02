; AppPackager Suite all-in-one installer.
; Per-user by design: no elevation, install root under %LOCALAPPDATA%, ARP in HKCU.
; Requires SUITEVERSION, PAYLOADDIR and OUTFILE on the makensis command line.

!ifndef SUITEVERSION
  !error "SUITEVERSION is required (makensis /DSUITEVERSION=...)"
!endif
!ifndef PAYLOADDIR
  !error "PAYLOADDIR is required (makensis /DPAYLOADDIR=...)"
!endif
!ifndef OUTFILE
  !error "OUTFILE is required (makensis /DOUTFILE=...)"
!endif

!define SUITE_NAME    "AppPackager Suite"
!define SUITE_KEY     "AppPackagerSuite"
!define SUITE_PUB     "Jason Ulbright"
!define ARP_ROOT      "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SUITE_KEY}"
!define PS_ARGS_PRE   "-NoProfile -ExecutionPolicy Bypass -File"

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

Name "${SUITE_NAME}"
Caption "${SUITE_NAME} ${SUITEVERSION}"
BrandingText "${SUITE_NAME} ${SUITEVERSION}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\${SUITE_KEY}"
InstallDirRegKey HKCU "${ARP_ROOT}" "InstallLocation"
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "0.0.0.0"
VIAddVersionKey "ProductName"     "${SUITE_NAME}"
VIAddVersionKey "ProductVersion"  "${SUITEVERSION}"
VIAddVersionKey "FileVersion"     "${SUITEVERSION}"
VIAddVersionKey "FileDescription" "${SUITE_NAME} installer"
VIAddVersionKey "CompanyName"     "${SUITE_PUB}"
VIAddVersionKey "LegalCopyright"  "MIT"

!include "MUI2.nsh"
!include "FileFunc.nsh"

; Per-component File, shortcut and shortcut-delete lines, generated into the
; payload directory by tools\build-suite-installer.ps1 from its component table.
!include "${PAYLOADDIR}\components.nsh"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var PSExe
Var StartMenuDir

Function .onInit
  ; 32-bit installer on 64-bit Windows: $SYSDIR redirects to SysWOW64, whose
  ; powershell.exe would run the tools 32-bit. Resolve the native host instead.
  StrCpy $PSExe "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
  IfFileExists "$PSExe" +2 0
    StrCpy $PSExe "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
  StrCpy $StartMenuDir "$SMPROGRAMS\${SUITE_NAME}"
FunctionEnd

; Shipped files are overwritten; files absent from the payload are left in place,
; which is what keeps user state (*.json, Logs\, Packagers\Icons\) across upgrades.
SetOverwrite on

Section "Suite" SecSuite
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "${PAYLOADDIR}\suite-manifest.json"

  !insertmacro SUITE_INSTALL_FILES

  CreateDirectory "$StartMenuDir"
  !insertmacro SUITE_CREATE_SHORTCUTS

  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${ARP_ROOT}" "DisplayName"     "${SUITE_NAME}"
  WriteRegStr HKCU "${ARP_ROOT}" "DisplayVersion"  "${SUITEVERSION}"
  WriteRegStr HKCU "${ARP_ROOT}" "Publisher"       "${SUITE_PUB}"
  WriteRegStr HKCU "${ARP_ROOT}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${ARP_ROOT}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${ARP_ROOT}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${ARP_ROOT}" "NoModify" 1
  WriteRegDWORD HKCU "${ARP_ROOT}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${ARP_ROOT}" "EstimatedSize" "$0"
SectionEnd

Function un.onInit
  StrCpy $StartMenuDir "$SMPROGRAMS\${SUITE_NAME}"
FunctionEnd

Section "Uninstall"
  !insertmacro SUITE_DELETE_SHORTCUTS
  RMDir "$StartMenuDir"

  DeleteRegKey HKCU "${ARP_ROOT}"

  ; Only shipped files are deleted; user state written after install stays,
  ; and every directory removal is non-recursive so a folder holding user
  ; files survives.
  !insertmacro SUITE_UNINSTALL_FILES
  Delete "$INSTDIR\suite-manifest.json"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
