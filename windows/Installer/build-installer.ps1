param([string]$InnoCompiler,[switch]$SkipTests,[string]$Version="1.0.2")
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Version must be major.minor.patch'}
$windowsRoot=Split-Path -Parent $PSScriptRoot
$projectRoot=Split-Path -Parent $windowsRoot
$csc='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$artifacts=Join-Path $projectRoot ('outputs\windows-installer-'+$Version)
$payload=Join-Path $artifacts 'portable'
$icons=Join-Path $windowsRoot 'Resources'
if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload -Recurse -Force}
New-Item -ItemType Directory -Path $artifacts,$payload -Force | Out-Null
& $csc /nologo /target:exe /checked+ /r:System.Drawing.dll ('/out:'+(Join-Path $artifacts 'IconBuilder.exe')) (Join-Path $PSScriptRoot 'IconBuilder.cs')
if($LASTEXITCODE-ne 0){throw 'Icon tool compilation failed'}
& (Join-Path $artifacts 'IconBuilder.exe') $icons
if($LASTEXITCODE-ne 0){throw 'Icon generation failed'}
if($SkipTests){& (Join-Path $windowsRoot 'build.ps1')}else{& (Join-Path $windowsRoot 'build.ps1') -Tests}
$studioBuild=Join-Path $projectRoot 'outputs\GMK104-Lighting-Studio-Windows'
foreach($name in @('GMK104 Lighting Studio.exe','layout.json','default-led-map.json','README.md','VERIFICATION.md')){Copy-Item -LiteralPath (Join-Path $studioBuild $name) -Destination $payload -Force}
Copy-Item -LiteralPath (Join-Path $studioBuild 'Profiles') -Destination $payload -Recurse -Force
Copy-Item -LiteralPath (Join-Path $icons 'gmk104.ico') -Destination $payload -Force
Copy-Item -LiteralPath (Join-Path $windowsRoot 'Firmware\README.md') -Destination (Join-Path $payload 'Firmware-README.md') -Force
Copy-Item -LiteralPath (Join-Path $windowsRoot 'LICENSE.txt'),(Join-Path $windowsRoot 'THIRD_PARTY_NOTICES.md') -Destination $payload -Force
# Ship inspectable firmware/script files beside the small launcher.
$firmwarePayload=Join-Path $payload 'Firmware'
New-Item -ItemType Directory -Path $firmwarePayload -Force|Out-Null
foreach($name in @('GMK104-Guarded-Flasher.ps1','GMK104-firmware-1.0.bin','GMK104-custom-RGB-v0.2-experimental.bin','GMK104-custom-RGB-v0.3-experimental.bin','GMK104-custom-RGB-v0.4-experimental.bin','GMK104-stock-recovery.bin')){Copy-Item -LiteralPath (Join-Path $windowsRoot ('Firmware\'+$name)) -Destination $firmwarePayload -Force}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Run-Flasher.ps1') -Destination $firmwarePayload -Force
$pinsSource=Join-Path $artifacts 'FirmwareScriptPins.cs'
$scriptHashes=@('GMK104-Guarded-Flasher.ps1','Run-Flasher.ps1') | ForEach-Object{(Get-FileHash -LiteralPath (Join-Path $firmwarePayload $_) -Algorithm SHA256).Hash.ToLowerInvariant()}
('internal static class FirmwareScriptPins { internal static readonly string[] Hashes = {"'+($scriptHashes -join '","')+'"}; }') | Set-Content -Encoding UTF8 -LiteralPath $pinsSource
$flasher=Join-Path $payload 'GMK104 Firmware Flasher.exe'
& $csc /nologo /target:winexe /platform:x64 /checked+ /optimize+ /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll ('/win32icon:'+(Join-Path $icons 'gmk104-firmware.ico')) ('/resource:'+(Join-Path $icons 'gmk104-firmware.ico')+',Gmk104.FirmwareIcon') ('/out:'+$flasher) $pinsSource (Join-Path $PSScriptRoot 'FirmwareLauncher.cs')
if($LASTEXITCODE-ne 0){throw 'Firmware EXE compilation failed'}
$selfTestRoot=Join-Path $artifacts ('flasher-tests-'+[Guid]::NewGuid().ToString('N'))
$test=Start-Process -FilePath $flasher -ArgumentList @('--self-test',('"'+$selfTestRoot+'"')) -WindowStyle Hidden -PassThru -Wait
if($test.ExitCode-ne 0){throw "Embedded flasher self-test failed: $selfTestRoot"}
Write-Output 'Packaged firmware EXE self-test PASS (all five public offline target plans)'
if(-not $InnoCompiler){$InnoCompiler=Join-Path $projectRoot 'work\packaging-tools\inno-6.7.3\ISCC.exe'}
if(-not(Test-Path -LiteralPath $InnoCompiler)){throw 'Supply -InnoCompiler with the installed Inno Setup 6 ISCC.exe path.'}
& $InnoCompiler ("/DProductVersion=$Version") ("/DPayloadDir=$payload") ("/DArtifactDir=$artifacts") (Join-Path $PSScriptRoot 'GMK104.iss')
if($LASTEXITCODE-ne 0){throw 'Installer compilation failed'}
Copy-Item -LiteralPath $flasher -Destination $artifacts -Force
Write-Output "INSTALLER BUILD PASS: $artifacts"
