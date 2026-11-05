; Serein Windows Installer Script (NSIS Modern UI 2)
; Installs per-user (default $LOCALAPPDATA\Programs\Serein, or any folder the owner picks)
; without elevation, which keeps in-app updates writable. A portable copy writes no
; registry keys or shortcuts and keeps its data in a "data" folder beside serein.exe.
; Silent use: setup.exe /S [/PORTABLE] [/DESKTOP] /D=C:\path\to\folder  (/D must be last)

Unicode True
RequestExecutionLevel user
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "Win\COM.nsh"
!include "Win\Propkey.nsh"
!include "nsDialogs.nsh"

!define PRODUCT_NAME "Serein"
!define PRODUCT_PUBLISHER "Serein contributors"
!define PRODUCT_WEB_SITE "https://github.com/ViceVerse-cz/Serein"
!define APP_EXE "serein.exe"
!define APP_ID "cz.viceverse.serein"
; serein.exe looks for this file beside itself to keep its data in "data" there.
!define PORTABLE_MARKER "portable"
!define STANDARD_DIR "$LOCALAPPDATA\Programs\Serein"
!define PORTABLE_DIR "$DESKTOP\Serein Portable"

Var Portable          ; 1 for a portable copy
Var DesktopShortcut   ; 1 to add a desktop shortcut (standard install only)
Var StandardRadio
Var PortableRadio
Var DesktopCheck

!ifndef VERSION
  !define VERSION "0.1.0"
!endif

!ifndef DIST_DIR
  !if /FileExists "dist"
    !define DIST_DIR "dist"
  !else
    !define DIST_DIR "..\..\dist"
  !endif
!endif

!ifndef OUTPUT_DIR
  !if /FileExists "dist"
    !define OUTPUT_DIR "dist-installer"
  !else
    !define OUTPUT_DIR "..\..\dist-installer"
  !endif
!endif

Name "${PRODUCT_NAME} ${VERSION}"
OutFile "${OUTPUT_DIR}\serein-${VERSION}-setup.exe"
InstallDir "${STANDARD_DIR}"
InstallDirRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "InstallLocation"

!if /FileExists "packaging\windows\Serein.ico"
  !define MUI_ICON "packaging\windows\Serein.ico"
  !define MUI_UNICON "packaging\windows\Serein.ico"
!else if /FileExists "${__FILEDIR__}\Serein.ico"
  !define MUI_ICON "${__FILEDIR__}\Serein.ico"
  !define MUI_UNICON "${__FILEDIR__}\Serein.ico"
!else if /FileExists "Serein.ico"
  !define MUI_ICON "Serein.ico"
  !define MUI_UNICON "Serein.ico"
!else
  !define MUI_ICON "${__FILEDIR__}\Serein.ico"
  !define MUI_UNICON "${__FILEDIR__}\Serein.ico"
!endif

!define MUI_ABORTWARNING

; UI Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${DIST_DIR}\LICENSE-MIT"
Page custom InstallTypePage InstallTypeLeave
!define MUI_DIRECTORYPAGE_TEXT_TOP "Choose the folder for ${PRODUCT_NAME}. A portable copy can be moved somewhere else later: move the whole folder."
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DirectoryLeave
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${PRODUCT_NAME}"
!insertmacro MUI_PAGE_FINISH

; Uninstaller UI Pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

; The installer uses the x86 NSIS stub, including on x64 and ARM64 Windows.
!if ${NSIS_PTR_SIZE} != 4
  !error "The process-entry layout requires the x86 NSIS installer stub."
!endif

; Returns 0 when absent, 1 when running, 2 when the snapshot cannot be checked.
!macro SereinProcessCheck PREFIX
Function ${PREFIX}CheckSereinRunning
  System::Store "s"
  StrCpy $R0 2
  System::Call 'kernel32::CreateToolhelp32Snapshot(i 2, i 0) p .r0'
  ${If} $0 != -1
    System::Alloc 556
    Pop $1
    ${If} $1 != 0
      ; PROCESSENTRY32W: dwSize followed by 32 bytes of fields and WCHAR[260].
      System::Call '*$1(i 556)'
      System::Call 'kernel32::Process32FirstW(p r0, p r1) i .r2 ?e'
      Pop $3
      ${DoWhile} $2 != 0
        System::Call '*$1(&v36, &w260 .r4)'
        ${If} $4 == "${APP_EXE}"
          StrCpy $R0 1
          ${Break}
        ${EndIf}
        System::Call 'kernel32::Process32NextW(p r0, p r1) i .r2 ?e'
        Pop $3
      ${Loop}
      ${If} $2 == 0
      ${AndIf} $3 == 18 ; ERROR_NO_MORE_FILES, not an enumeration failure.
        StrCpy $R0 0
      ${EndIf}
      System::Free $1
    ${EndIf}
    System::Call 'kernel32::CloseHandle(p r0)'
  ${EndIf}
  Push $R0
  System::Store "l"
FunctionEnd
!macroend
!insertmacro SereinProcessCheck ""
!insertmacro SereinProcessCheck "un."

Function RegisterNotificationShortcut
  System::Store "s"
  StrCpy $R0 2
  StrCpy $1 0
  ; CreateShortcut initializes COM. Update the saved shortcut's native property store.
  System::Call 'shell32::SHGetPropertyStoreFromParsingName(w "$SMPROGRAMS\${PRODUCT_NAME}.lnk", p 0, i 2, g "${IID_IPropertyStore}", *p .r1) i .r0'
  ${If} $0 >= 0
    StrCpy $4 0
    System::Call 'shlwapi::SHStrDupW(w "${APP_ID}", *p .r4) i .r0'
    ${If} $0 >= 0
      System::Call '*${SYSSTRUCT_PROPERTYKEY}(${PKEY_AppUserModel_ID}) p .r2'
      System::Alloc ${SYSSIZEOF_PROPVARIANT}
      Pop $3
      ${If} $2 != 0
      ${AndIf} $3 != 0
        System::Call '*$3(&i2 ${VT_LPWSTR}, &i6 0, p r4)'
        ${IPropertyStore::SetValue} $1 '($2, $3) .r0'
        ${If} $0 >= 0
          ${IPropertyStore::Commit} $1 '() .r0'
          ${If} $0 >= 0
            StrCpy $R0 0
          ${EndIf}
        ${EndIf}
      ${EndIf}
      System::Free $3
      System::Free $2
    ${EndIf}
    System::Call 'ole32::CoTaskMemFree(p r4)'
    ${IUnknown::Release} $1 ''
  ${EndIf}
  Push $R0
  System::Store "l"
FunctionEnd

Function InstallTypePage
  !insertmacro MUI_HEADER_TEXT "Installation type" "Choose how ${PRODUCT_NAME} is set up on this PC."
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateRadioButton} 0 0 100% 12u "&Standard install"
  Pop $StandardRadio
  ${NSD_CreateLabel} 12u 13u -12u 20u "Adds a Start menu shortcut and an entry in Installed Apps so it can be uninstalled normally. Your data is kept in your user profile."
  Pop $0
  ${NSD_CreateCheckbox} 12u 36u -12u 12u "Also create a &desktop shortcut"
  Pop $DesktopCheck
  ${NSD_CreateRadioButton} 0 60u 100% 12u "&Portable"
  Pop $PortableRadio
  ${NSD_CreateLabel} 12u 73u -12u 30u "Puts everything, including your settings and cache, in one folder you can move or copy anywhere (another drive, a USB stick). No shortcuts or registry entries; delete the folder to remove it."
  Pop $0
  ${NSD_CreateLabel} 0 108u 100% 20u "Saved logins stay in Windows Credential Manager in both modes, so a portable copy moved to another PC asks you to sign in again."
  Pop $0
  ${NSD_OnClick} $StandardRadio InstallTypeClicked
  ${NSD_OnClick} $PortableRadio InstallTypeClicked
  ${If} $Portable == 1
    ${NSD_Check} $PortableRadio
  ${Else}
    ${NSD_Check} $StandardRadio
  ${EndIf}
  ${If} $DesktopShortcut == 1
    ${NSD_Check} $DesktopCheck
  ${EndIf}
  Call InstallTypeChanged
  nsDialogs::Show
FunctionEnd

Function InstallTypeClicked
  Pop $0 ; the clicked control, pushed by NSD_OnClick
  Call InstallTypeChanged
FunctionEnd

Function InstallTypeChanged
  ${NSD_GetState} $PortableRadio $0
  ${If} $0 == ${BST_CHECKED}
    EnableWindow $DesktopCheck 0
  ${Else}
    EnableWindow $DesktopCheck 1
  ${EndIf}
FunctionEnd

Function InstallTypeLeave
  ${NSD_GetState} $PortableRadio $0
  ${NSD_GetState} $DesktopCheck $1
  ${If} $1 == ${BST_CHECKED}
    StrCpy $DesktopShortcut 1
  ${Else}
    StrCpy $DesktopShortcut 0
  ${EndIf}
  ; Swap the suggested folder only while it is still the other mode's default.
  ${If} $0 == ${BST_CHECKED}
    StrCpy $Portable 1
    StrCpy $DesktopShortcut 0
    ${If} $INSTDIR == "${STANDARD_DIR}"
      StrCpy $INSTDIR "${PORTABLE_DIR}"
    ${EndIf}
  ${Else}
    StrCpy $Portable 0
    ${If} $INSTDIR == "${PORTABLE_DIR}"
      StrCpy $INSTDIR "${STANDARD_DIR}"
    ${EndIf}
  ${EndIf}
FunctionEnd

; A drive root is never a sensible target, and a folder this user cannot write
; (such as Program Files, without elevation) would fail halfway through copying.
Function DirectoryLeave
  StrLen $0 $INSTDIR
  ${If} $0 <= 3
    MessageBox MB_OK|MB_ICONEXCLAMATION "Choose a folder, not the root of a drive (for example D:\Apps\Serein)."
    Abort
  ${EndIf}
  ClearErrors
  CreateDirectory "$INSTDIR"
  FileOpen $1 "$INSTDIR\.serein-write-test" w
  ${If} ${Errors}
    MessageBox MB_OK|MB_ICONEXCLAMATION "Setup cannot write to $INSTDIR.$\r$\n$\r$\nFolders such as Program Files need administrator rights. Choose a folder in your user profile or on another drive."
    Abort
  ${EndIf}
  FileClose $1
  Delete "$INSTDIR\.serein-write-test"
FunctionEnd

Function .onInit
  SetShellVarContext current
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}

  StrCpy $Portable 0
  StrCpy $DesktopShortcut 0
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/PORTABLE" $R1
  ${IfNot} ${Errors}
    StrCpy $Portable 1
  ${EndIf}
  ClearErrors
  ${GetOptions} $R0 "/DESKTOP" $R1
  ${IfNot} ${Errors}
    StrCpy $DesktopShortcut 1
  ${EndIf}
  ; A silent portable install without /D= goes to the portable default, not to a previous
  ; standard installation's folder.
  ${If} $Portable == 1
  ${AndIf} $INSTDIR == "${STANDARD_DIR}"
    StrCpy $INSTDIR "${PORTABLE_DIR}"
  ${EndIf}

  ${Do}
    Call CheckSereinRunning
    Pop $0
    ${If} $0 == 2
      MessageBox MB_OK|MB_ICONSTOP "Cannot check whether ${PRODUCT_NAME} is running. Setup cannot continue safely." /SD IDOK
      SetErrorLevel 2
      Abort
    ${EndIf}
    ${If} $0 != 0
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "${PRODUCT_NAME} is currently running. Please close Serein before continuing." /SD IDCANCEL IDRETRY retry_init IDCANCEL cancel_init
      retry_init:
        ${Continue}
      cancel_init:
        SetErrorLevel 1
        Abort
    ${Else}
      ${Break}
    ${EndIf}
  ${Loop}
FunctionEnd

Section "MainSection" SEC01
  SetOutPath "$INSTDIR"
  SetOverwrite on

  ; Copy all package payload files
  File /r /x install-notifications.ps1 /x setup.ps1 "${DIST_DIR}\*.*"
  ; Remove legacy installer utilities when upgrading an existing installation.
  Delete "$INSTDIR\setup.ps1"

  ${If} $Portable == 1
    ; serein.exe keeps its data in "data" beside itself while this marker exists.
    FileOpen $0 "$INSTDIR\${PORTABLE_MARKER}" w
    FileWrite $0 "Serein keeps its data in the data folder next to serein.exe while this file exists.$\r$\n"
    FileClose $0
    CreateDirectory "$INSTDIR\data"
    ; Optional: registers a Start menu shortcut so Windows shows Serein's notifications.
    File "${DIST_DIR}\install-notifications.ps1"
    Return
  ${EndIf}

  ; A standard install never inherits a portable copy's marker.
  Delete "$INSTDIR\${PORTABLE_MARKER}"
  Delete "$INSTDIR\install-notifications.ps1"

  ; Create uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Write Add/Remove Programs uninstall registry keys
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "EstimatedSize" "$0"

  ; Keep uninstall registration available even if shortcut creation fails.
  ClearErrors
  CreateDirectory "$SMPROGRAMS"
  CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  StrCpy $0 2
  ${IfNot} ${Errors}
    Call RegisterNotificationShortcut
    Pop $0
  ${EndIf}
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "Cannot register the ${PRODUCT_NAME} notification shortcut. You can remove the incomplete installation from Windows Installed Apps." /SD IDOK
    SetErrorLevel 2
    Abort
  ${EndIf}

  ${If} $DesktopShortcut == 1
    CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  ${EndIf}
SectionEnd

Function un.onInit
  SetShellVarContext current
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}

  ${Do}
    Call un.CheckSereinRunning
    Pop $0
    ${If} $0 == 2
      MessageBox MB_OK|MB_ICONSTOP "Cannot check whether ${PRODUCT_NAME} is running. Uninstall cannot continue safely." /SD IDOK
      SetErrorLevel 2
      Abort
    ${EndIf}
    ${If} $0 != 0
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "${PRODUCT_NAME} is currently running. Please close Serein before uninstalling." /SD IDCANCEL IDRETRY retry_uninit IDCANCEL cancel_uninit
      retry_uninit:
        ${Continue}
      cancel_uninit:
        SetErrorLevel 1
        Abort
    ${Else}
      ${Break}
    ${EndIf}
  ${Loop}
FunctionEnd

Section "Uninstall"
  ; Remove Start Menu shortcut
  Delete "$SMPROGRAMS\${PRODUCT_NAME}.lnk"

  ; Remove Desktop shortcut if present
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"

  ; Remove Run registry key if startup was configured
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${PRODUCT_NAME}"

  ; Remove Uninstall registry keys
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

  ; Remove installed files
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\LICENSE-MIT"
  Delete "$INSTDIR\LICENSE-APACHE"
  Delete "$INSTDIR\THIRD_PARTY_NOTICES.md"
  Delete "$INSTDIR\install-notifications.ps1"
  Delete "$INSTDIR\setup.ps1"
  Delete "$INSTDIR\uninstall.exe"
  Delete "$INSTDIR\${PORTABLE_MARKER}"
  RMDir /r "$INSTDIR\docs"
  RMDir /r "$INSTDIR\licenses"
  RMDir /r "$INSTDIR\source"
  RMDir /r "$INSTDIR\serein.exe.WebView2"

  ; Leftover in-app update staging (.serein-update.lock and .serein-update-<pid>).
  Delete "$INSTDIR\.serein-update.lock"
  FindFirst $0 $1 "$INSTDIR\.serein-update-*"
  ${DoWhile} $1 != ""
    RMDir /r "$INSTDIR\$1"
    FindNext $0 $1
  ${Loop}
  FindClose $0

  ; Only an empty folder is removed: the owner may have installed into a folder that also
  ; holds their own files, and those must survive an uninstall.
  RMDir "$INSTDIR"
SectionEnd
