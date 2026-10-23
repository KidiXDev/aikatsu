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

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Aikatsu"
!define LINK_KEY "Software\Classes\aikatsu"

; Generate exact file removals so a custom folder's other files survive uninstall.
!tempfile UNINSTALL_FILES
!system 'python "installer_files.py" "${DIST}" "${UNINSTALL_FILES}"' = 0
!include "${UNINSTALL_FILES}"
!delfile "${UNINSTALL_FILES}"

Name "Aikatsu"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\Aikatsu"
InstallDirRegKey HKCU "${UNINST_KEY}" "InstallLocation"

!define MUI_ICON "..\assets\icon.ico"
!define MUI_UNICON "..\assets\icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\aikatsu.exe"

!insertmacro MUI_PAGE_LICENSE "..\..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

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

    ; Watch-together links (aikatsu://party?...)
    WriteRegStr HKCU "${LINK_KEY}" "" "URL:Aikatsu"
    WriteRegStr HKCU "${LINK_KEY}" "URL Protocol" ""
    WriteRegStr HKCU "${LINK_KEY}\DefaultIcon" "" "$INSTDIR\aikatsu.exe,0"
    WriteRegStr HKCU "${LINK_KEY}\shell\open\command" "" '"$INSTDIR\aikatsu.exe" "%1"'

    ${GetParameters} $0
    ClearErrors
    ${GetOptions} $0 "/UPDATE" $1
    ${IfNot} ${Errors}
        Exec '"$INSTDIR\aikatsu.exe"'
    ${EndIf}
SectionEnd

Section "Uninstall"
    SetOutPath "$TEMP"
    Delete "$SMPROGRAMS\Aikatsu.lnk"
    Delete "$DESKTOP\Aikatsu.lnk"
    !insertmacro UninstallFiles
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"
    DeleteRegKey HKCU "${UNINST_KEY}"
    DeleteRegKey HKCU "${LINK_KEY}"
SectionEnd
