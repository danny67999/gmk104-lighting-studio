param([Parameter(Mandatory=$true)][string]$InnoCompiler,[string]$Version='1.0.2')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$build=Join-Path $root ('outputs\windows-installer-'+$Version)
$payload=Join-Path $build 'portable'
$smoke=Join-Path $root ('outputs\installer-smoke-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $smoke|Out-Null
$install=Join-Path $smoke 'installed'
& $InnoCompiler /DSmokeTest ("/DProductVersion=$Version") ("/DPayloadDir=$payload") ("/DArtifactDir=$smoke") (Join-Path $PSScriptRoot 'GMK104.iss')
if($LASTEXITCODE-ne 0){throw 'Isolated installer compilation failed'}
$setup=Join-Path $smoke ('GMK104-Lighting-Studio-Windows-Setup-'+$Version+'.exe')
$p=Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/NOICONS',('/DIR="'+$install+'"')) -Wait -PassThru
if($p.ExitCode-ne 0){throw ('Isolated install failed: '+$p.ExitCode)}
foreach($file in (Get-ChildItem -LiteralPath $payload -File -Recurse)){
    $relative=$file.FullName.Substring($payload.Length+1)
    $actual=Join-Path $install $relative
    if(-not(Test-Path -LiteralPath $actual)){throw "Missing installed file: $relative"}
    if((Get-FileHash -LiteralPath $file.FullName).Hash-ne(Get-FileHash -LiteralPath $actual).Hash){throw "Installed file differs: $relative"}
}
$expected=$Version+'.0'
foreach($name in @('GMK104 Lighting Studio.exe','GMK104 Firmware Flasher.exe')){
    if([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $install $name)).FileVersion-ne$expected){throw "Wrong installed version: $name"}
}
$preview=Join-Path $root 'outputs\Windows-1.0.2-Preview.png'
$p=Start-Process -FilePath (Join-Path $install 'GMK104 Lighting Studio.exe') -ArgumentList @('--preview',('"'+$preview+'"')) -Wait -PassThru
if($p.ExitCode-ne 0-or-not(Test-Path -LiteralPath $preview)){throw 'Installed Lighting Studio offline preview failed'}
$p=Start-Process -FilePath (Join-Path $install 'GMK104 Firmware Flasher.exe') -ArgumentList @('--self-test',('"'+$smoke+'\offline-flasher"')) -Wait -PassThru
if($p.ExitCode-ne 0){throw 'Installed firmware tool offline startup/packet checks failed'}
$p=Start-Process -FilePath (Join-Path $install 'unins000.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -Wait -PassThru
if($p.ExitCode-ne 0){throw 'Isolated uninstall failed'}
foreach($name in @('GMK104 Lighting Studio.exe','GMK104 Firmware Flasher.exe')){
    if(Test-Path -LiteralPath (Join-Path $install $name)){throw "Uninstall retained executable: $name"}
}
@{Version=$Version;InstalledFilesMatch=$true;StudioPreviewPassed=$true;FirmwareOfflineStartupPassed=$true;UninstallPassed=$true;KeyboardOpened=$false}|ConvertTo-Json|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $root 'outputs\Windows-Package-Verification.json')
Write-Output 'COMPLETE PACKAGE TEST PASS: both installed apps, exact payload hashes, offline GUI startup/packet plans and isolated uninstall. No keyboard opened.'
