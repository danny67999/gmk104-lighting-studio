#ifndef PayloadDir
  #error PayloadDir is required
#endif
#ifndef ArtifactDir
  #error ArtifactDir is required
#endif
#define ProductVersion "1.5.2.2"
[Setup]
#ifdef SmokeTest
AppId={{8057B21A-7C40-4F0F-A56D-14BFCA2CC104}
#else
AppId={{6057B21A-7C40-4F0F-A56D-14BFCA2CC104}
#endif
AppName=GMK104 Lighting Studio
AppVersion={#ProductVersion}
AppPublisher=GMK104 community project
AppPublisherURL=https://github.com/danny67999/gmk104-lighting-studio
DefaultDirName={localappdata}\Programs\GMK104 Lighting Studio
DefaultGroupName=GMK104 Lighting Studio
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
SetupIconFile={#PayloadDir}\gmk104.ico
UninstallDisplayIcon={app}\GMK104 Lighting Studio.exe
OutputDir={#ArtifactDir}
OutputBaseFilename=GMK104-Lighting-Studio-Windows-Setup-{#ProductVersion}
Compression=lzma2
SolidCompression=yes
DisableProgramGroupPage=yes
CloseApplications=no
RestartApplications=no
#ifdef SmokeTest
AppMutex=Local\GMK104InstallerSmokeTest
#else
AppMutex=Local\GMK104LightingStudio
#endif
UninstallDisplayName=GMK104 Lighting Studio and Guarded Firmware Flasher
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: checkedonce
[Files]
Source: "{#PayloadDir}\GMK104 Lighting Studio.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\GMK104 Firmware Flasher.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\layout.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\default-led-map.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\gmk104.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\VERIFICATION.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\Firmware-README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\GMK104 Lighting Studio"; Filename: "{app}\GMK104 Lighting Studio.exe"; WorkingDir: "{app}"
Name: "{group}\GMK104 Guarded Firmware Flasher"; Filename: "{app}\GMK104 Firmware Flasher.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\GMK104 Lighting Studio"; Filename: "{app}\GMK104 Lighting Studio.exe"; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{app}\GMK104 Lighting Studio.exe"; Description: "Open GMK104 Lighting Studio"; Flags: postinstall nowait skipifsilent unchecked
; No firmware actions, auto-start registration, or profile deletion occur during install/uninstall.
