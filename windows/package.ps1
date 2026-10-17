param([string]$InnoCompiler,[switch]$SkipTests,[string]$Version="1.0.2")
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Installer\build-installer.ps1') -InnoCompiler $InnoCompiler -SkipTests:$SkipTests -Version $Version
$build=Join-Path $project ('outputs\windows-installer-'+$Version)
$release=Join-Path $project ('outputs\release-'+$Version)
New-Item -ItemType Directory -Path $release -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $build ('GMK104-Lighting-Studio-Windows-Setup-'+$Version+'.exe')) -Destination (Join-Path $release ('GMK104-Lighting-Studio-Windows-Setup-'+$Version+'.exe')) -Force
$portable=Join-Path $build 'portable'
& (Join-Path $PSScriptRoot 'Installer\Zip-Payload.ps1') -Source $portable -Destination (Join-Path $release ('GMK104-Lighting-Studio-'+$Version+'-Windows-x64.zip'))
$standalone=Join-Path $build 'standalone-firmware'
if(Test-Path -LiteralPath $standalone){Remove-Item -LiteralPath $standalone -Recurse -Force}
New-Item -ItemType Directory -Path $standalone|Out-Null
foreach($name in @('GMK104 Firmware Flasher.exe','Firmware','Firmware-README.md','LICENSE.txt','THIRD_PARTY_NOTICES.md')){Copy-Item -LiteralPath (Join-Path $portable $name) -Destination $standalone -Recurse -Force}
& (Join-Path $PSScriptRoot 'Installer\Zip-Payload.ps1') -Source $standalone -Destination (Join-Path $release ('GMK104-Firmware-Installer-'+$Version+'-Windows-x64.zip'))
Get-FileHash -LiteralPath (Get-ChildItem -LiteralPath $release -File).FullName -Algorithm SHA256|Select-Object Hash,Path
Write-Output "WINDOWS PACKAGES READY: $release"
