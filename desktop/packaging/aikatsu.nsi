; Windows installer, built by .github/workflows/release.yml:
;   makensis /DVERSION=0.3.2 /DDIST=<windeployqt folder> /DOUTFILE=<setup.exe> aikatsu.nsi
; Per-user, so it needs no admin rights and users can still drop ffmpeg.exe beside aikatsu.exe.
; The app's updater (core/src/update.rs) runs it with /S /UPDATE just before quitting.

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!include MUI2.nsh
!include LogicLib.nsh
!include FileFunc.nsh

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

; Files in use can't be replaced, and a silent install would skip them and leave a mix of versions.
Function WaitForAikatsu
    ${IfNot} ${FileExists} "$INSTDIR\aikatsu.exe"
        Return
    ${EndIf}
    StrCpy $0 0
    ${Do}
        ClearErrors
        FileOpen $1 "$INSTDIR\aikatsu.exe" a
        ${IfNot} ${Errors}
            FileClose $1
            Return
        ${EndIf}
        ${If} ${Silent}
            ; An update: the app is still closing. Give up after 30 s rather than install half of it.
            IntOp $0 $0 + 1
            ${If} $0 > 150
                Quit
            ${EndIf}
            Sleep 200
        ${Else}
            MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Aikatsu is running. Close it, then choose Retry." IDRETRY +2
            Quit
        ${EndIf}
    ${Loop}
FunctionEnd

Section
    SetOutPath "$INSTDIR"
    Call WaitForAikatsu
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

    ${GetParameters} $0
    ClearErrors
    ${GetOptions} $0 "/UPDATE" $1
    ${IfNot} ${Errors}
        Exec '"$INSTDIR\aikatsu.exe"'
    ${EndIf}
SectionEnd

Section "Uninstall"
    Delete "$SMPROGRAMS\Aikatsu.lnk"
    Delete "$DESKTOP\Aikatsu.lnk"
    ; Not $INSTDIR: that is wherever uninstall.exe runs from. History and settings live elsewhere and stay.
    RMDir /r "${DIR}"
    DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
