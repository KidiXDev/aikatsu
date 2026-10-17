; Windows installer, built by .github/workflows/release.yml:
;   makensis /DVERSION=0.3.2 /DDIST=<windeployqt folder> /DOUTFILE=<setup.exe> aikatsu.nsi
; Per-user, so it needs no admin rights and users can still drop ffmpeg.exe beside aikatsu.exe.

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!include MUI2.nsh

; Fixed rather than chosen: the uninstaller deletes this whole folder.
!define DIR "$LOCALAPPDATA\Programs\Aikatsu"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Aikatsu"

Name "Aikatsu"
OutFile "${OUTFILE}"
InstallDir "${DIR}"

!define MUI_ICON "..\assets\icon.ico"
!define MUI_UNICON "..\assets\icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\aikatsu.exe"

!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
    StrCpy $INSTDIR "${DIR}" ; ignore /D=
FunctionEnd

Section
    SetOutPath "$INSTDIR"
    File /r "${DIST}\*"
    WriteUninstaller "$INSTDIR\uninstall.exe"
    CreateShortcut "$SMPROGRAMS\Aikatsu.lnk" "$INSTDIR\aikatsu.exe"
    CreateShortcut "$DESKTOP\Aikatsu.lnk" "$INSTDIR\aikatsu.exe"

    WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "Aikatsu"
    WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "KidiXDev"
    WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\aikatsu.exe"
    WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
    Delete "$SMPROGRAMS\Aikatsu.lnk"
    Delete "$DESKTOP\Aikatsu.lnk"
    ; Not $INSTDIR: that is wherever uninstall.exe runs from. History and settings live elsewhere and stay.
    RMDir /r "${DIR}"
    DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
