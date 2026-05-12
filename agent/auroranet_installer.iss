; Script Inno Setup pour Auroranet Agent
; Téléchargez Inno Setup sur https://jrsoftware.org/isdl.php

[Setup]
AppName=Auroranet Agent
AppVersion=1.0
DefaultDirName={autopf}\Auroranet
DefaultGroupName=Auroranet
LicenseFile=TERMS_OF_USE.txt
OutputDir=.
OutputBaseFilename=Auroranet_Agent_Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Note: Vous devez d'abord compiler l'agent pour Windows avec : 
; GOOS=windows GOARCH=amd64 go build -o agent.exe main.go
Source: "agent.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Auroranet Agent"; Filename: "{app}\agent.exe"
Name: "{autodesktop}\Auroranet Agent"; Filename: "{app}\agent.exe"; Tasks: desktopicon

[Run]
Description: "Lancer Auroranet Agent"; Filename: "{app}\agent.exe"; Flags: nowait postinstall skipifsilent
