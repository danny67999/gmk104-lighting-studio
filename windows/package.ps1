param([string]$InnoCompiler,[switch]$SkipTests)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Installer\build-installer.ps1') -InnoCompiler $InnoCompiler -SkipTests:$SkipTests
$build=Join-Path $project 'outputs\windows-installer-1.0.0'
$release=Join-Path $project 'outputs\release-1.0'
New-Item -ItemType Directory -Path $release -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $build 'GMK104-Lighting-Studio-Windows-Setup-1.0.0.exe') -Destination (Join-Path $release 'GMK104-Lighting-Studio-Windows-Setup-1.0.exe') -Force
$portable=Join-Path $build 'portable'
& (Join-Path $PSScriptRoot 'Installer\Zip-Payload.ps1') -Source $portable -Destination (Join-Path $release 'GMK104-Lighting-Studio-1.0-Windows-x64.zip')
$standalone=Join-Path $build 'standalone-firmware'
if(Test-Path -LiteralPath $standalone){Remove-Item -LiteralPath $standalone -Recurse -Force}
New-Item -ItemType Directory -Path $standalone|Out-Null
foreach($name in @('GMK104 Firmware Flasher.exe','Firmware','Firmware-README.md','LICENSE.txt','THIRD_PARTY_NOTICES.md')){Copy-Item -LiteralPath (Join-Path $portable $name) -Destination $standalone -Recurse -Force}
& (Join-Path $PSScriptRoot 'Installer\Zip-Payload.ps1') -Source $standalone -Destination (Join-Path $release 'GMK104-Firmware-Installer-1.0-Windows-x64.zip')
Get-FileHash -LiteralPath (Get-ChildItem -LiteralPath $release -File).FullName -Algorithm SHA256|Select-Object Hash,Path
Write-Output "WINDOWS PACKAGES READY: $release"
