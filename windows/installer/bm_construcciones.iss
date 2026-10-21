; =================================================================
;  Instalador de BM Construcciones para Windows (Inno Setup 6).
;  Se instala para el usuario (no pide permiso de administrador),
;  crea accesos directos en el escritorio y en el menú Inicio, y se
;  puede desinstalar desde "Agregar o quitar programas".
;
;  Compilar (después de `flutter build windows --release`):
;    ISCC.exe /DVersion=1.0.24 /DSalida=C:\Users\<usuario>\Downloads windows\installer\bm_construcciones.iss
; =================================================================

#ifndef Version
  #define Version "1.0.0"
#endif
#ifndef Salida
  #define Salida "..\..\build\installer"
#endif
#define Release "..\..\build\windows\x64\runner\Release"
; Sysnative: la carpeta System32 de 64 bits vista desde el compilador (que es de 32 bits).
#define Sistema GetEnv("WINDIR") + "\Sysnative"

[Setup]
; Mismo AppId siempre: las versiones nuevas se instalan encima de la anterior.
AppId={{49B8FC31-8A44-47D4-963F-6A2337D4E5D1}
AppName=BM Construcciones
AppVersion={#Version}
AppVerName=BM Construcciones {#Version}
AppPublisher=BM Construcciones
DefaultDirName={localappdata}\Programs\BM Construcciones
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#Salida}
OutputBaseFilename=BmVentas.V{#Version}-Instalador
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bm_construcciones.exe
UninstallDisplayName=BM Construcciones
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "escritorio"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Librerías de Visual C++ (para que abra en cualquier Windows sin instalar nada más).
Source: "{#Sistema}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Sistema}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Sistema}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\BM Construcciones"; Filename: "{app}\bm_construcciones.exe"
Name: "{autodesktop}\BM Construcciones"; Filename: "{app}\bm_construcciones.exe"; Tasks: escritorio

[Run]
Filename: "{app}\bm_construcciones.exe"; Description: "Abrir BM Construcciones"; Flags: nowait postinstall skipifsilent


