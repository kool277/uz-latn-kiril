; Inno Setup 6 script of the Windows installer. CI runs it after packaging/windows/deploy.ps1:
;   iscc /DAppVersion=1.2.0 /DDeployDir=<deploy folder> /DOutputDir=<folder> platforms\qt-desktop\packaging\installer\uztranslit.iss
; The installer installs per user by default (no administrator rights); "all users" can be chosen in the wizard.
; Its own interface is English or Russian (Inno Setup ships no Uzbek messages file).

#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif
#ifndef DeployDir
  #define DeployDir "..\..\build\deploy"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build"
#endif

[Setup]
AppId={{CAB1990F-C1AE-4036-9F63-E0DFADBFD8FD}
AppName=UzTranslit
AppVersion={#AppVersion}
AppVerName=UzTranslit {#AppVersion}
AppPublisher=UzTranslit
AppPublisherURL=https://latin.jaybi.uz
AppSupportURL=https://latin.jaybi.uz
AppUpdatesURL=https://latin.jaybi.uz
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\UzTranslit
DefaultGroupName=UzTranslit
DisableProgramGroupPage=yes
LicenseFile=..\..\..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=UzTranslit-{#AppVersion}-Windows-x64-setup
SetupIconFile=..\windows\uztranslit.ico
UninstallDisplayIcon={app}\uztranslit.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ChangesEnvironment=yes
CloseApplications=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[CustomMessages]
en.AddToPath=Add uztranslit to PATH (command line: uztranslit --to new file.txt)
ru.AddToPath=Добавить uztranslit в PATH (командная строка: uztranslit --to new file.txt)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "addtopath"; Description: "{cm:AddToPath}"; Flags: unchecked

[Files]
Source: "{#DeployDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\UzTranslit"; Filename: "{app}\uztranslit.exe"
Name: "{autodesktop}\UzTranslit"; Filename: "{app}\uztranslit.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; \
    Tasks: addtopath; Check: NeedsAddPath(ExpandConstant('{app}'))

[Run]
Filename: "{app}\uztranslit.exe"; Description: "{cm:LaunchProgram,UzTranslit}"; Flags: nowait postinstall skipifsilent

[Code]
function NeedsAddPath(Dir: string): Boolean;
var
  Path: string;
begin
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Path) then
    Path := '';
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Path) + ';') = 0;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Path, Dir: string;
  P: Integer;
begin
  if CurUninstallStep <> usPostUninstall then
    exit;
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Path) then
    exit;
  Dir := ExpandConstant('{app}');
  P := Pos(';' + Uppercase(Dir), Uppercase(Path));
  if P > 0 then
  begin
    Delete(Path, P, Length(Dir) + 1);
    RegWriteExpandStringValue(HKCU, 'Environment', 'Path', Path);
  end;
end;
