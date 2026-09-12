param([string]$DesktopProject)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'build.ps1') -Tests
$buildOutput = Join-Path $projectPath 'outputs\GMK104-Lighting-Studio-Windows'
$releaseRoot = Join-Path $projectPath ('outputs\windows-release-' + [Guid]::NewGuid().ToString('N'))
$portablePath = Join-Path $releaseRoot 'GMK104 Lighting Studio'
$sourceRoot = Join-Path $releaseRoot 'source'
$sourceWindows = Join-Path $sourceRoot 'windows'
New-Item -ItemType Directory -Path $portablePath,$sourceWindows | Out-Null
foreach ($name in @('GMK104 Lighting Studio.exe','layout.json','default-led-map.json','README.md','VERIFICATION.md')) {
    Copy-Item -LiteralPath (Join-Path $buildOutput $name) -Destination $portablePath
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Firmware') -Destination (Join-Path $portablePath 'Optional firmware - USB only') -Recurse
$sourceFiles = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File | Where-Object { $_.Extension -in @('.cs','.ps1','.md','.json','.bin','.iss','.ico','.png','.txt') }
foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($PSScriptRoot.Length).TrimStart('\')
    $destination = Join-Path $sourceWindows $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
}
$portableZip = Join-Path $releaseRoot 'GMK104-Windows-1.5.2.zip'
$sourceZip = Join-Path $releaseRoot 'GMK104-Windows-Source-1.5.2.zip'
Compress-Archive -LiteralPath $portablePath -DestinationPath $portableZip
Compress-Archive -LiteralPath $sourceWindows -DestinationPath $sourceZip
if ($DesktopProject) {
    $desktopRoot = (Resolve-Path -LiteralPath $DesktopProject).Path
    $desktopApp = Join-Path $desktopRoot 'Windows Lighting Studio'
    $desktopSource = Join-Path $desktopRoot 'windows'
    $desktopZip = Join-Path $desktopRoot 'GMK104-Windows-1.5.2.zip'
    $desktopSourceZip = Join-Path $desktopRoot 'GMK104-Windows-Source-1.5.2.zip'
    foreach ($target in @($desktopApp,$desktopSource,$desktopZip,$desktopSourceZip)) { if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite existing desktop files: $target" } }
    Copy-Item -LiteralPath $portablePath -Destination $desktopApp -Recurse
    Copy-Item -LiteralPath $sourceWindows -Destination $desktopSource -Recurse
    Copy-Item -LiteralPath $portableZip -Destination $desktopZip
    Copy-Item -LiteralPath $sourceZip -Destination $desktopSourceZip
    Write-Output "DESKTOP APP: $desktopApp"
    Write-Output "DESKTOP SOURCE: $desktopSource"
}
Get-FileHash -LiteralPath $portableZip,$sourceZip -Algorithm SHA256 | Select-Object Hash,Path
Write-Output "PACKAGE PASS: $releaseRoot"
