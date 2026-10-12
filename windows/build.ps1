param([switch]$Tests)
$ErrorActionPreference = 'Stop'
$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$projectPath = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $projectPath 'outputs\GMK104-Lighting-Studio-Windows'
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$sources = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.cs' | Where-Object { $_.Name -notlike '*Tests.cs' } | Sort-Object Name | ForEach-Object { $_.FullName }
$references = @('/r:System.dll','/r:System.Core.dll','/r:System.Drawing.dll','/r:System.Windows.Forms.dll','/r:System.Web.Extensions.dll','/r:System.Management.dll')
$exePath = Join-Path $outputPath 'GMK104 Lighting Studio.exe'
$iconOptions=@()
$iconPath=Join-Path $PSScriptRoot 'Resources\gmk104.ico'
if(Test-Path -LiteralPath $iconPath){$iconOptions+=('/win32icon:'+$iconPath)}
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /checked+ /main:Gmk104LightingStudio.Program "/out:$exePath" $iconOptions $references $sources
if ($LASTEXITCODE -ne 0) { throw 'Windows Lighting Studio build failed.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Resources\layout.json'),(Join-Path $PSScriptRoot 'Resources\default-led-map.json') -Destination $outputPath -Force
$profileOutput=Join-Path $outputPath 'Profiles'
if(Test-Path -LiteralPath $profileOutput){Remove-Item -LiteralPath $profileOutput -Recurse -Force}
New-Item -ItemType Directory -Path $profileOutput|Out-Null
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Resources\Profiles') -Filter '*.json' -File|Where-Object{$_.Name-notlike '._*'}|Copy-Item -Destination $profileOutput
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'README.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $outputPath -Force }
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'VERIFICATION.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VERIFICATION.md') -Destination $outputPath -Force }
Write-Output "BUILD PASS: $exePath"
Get-FileHash -LiteralPath $exePath -Algorithm SHA256 | Select-Object Hash,Path
if ($Tests) {
    $testRoot = Join-Path $projectPath ('outputs\windows-test-results\' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $suites = @(
        @{Name='OnboardTests';Main='Gmk104LightingStudio.OnboardTests';Source='tests\OnboardTests.cs'},
        @{Name='LightingTests';Main='Gmk104LightingStudio.LightingTests';Source='tests\LightingTests.cs'},
        @{Name='TransportTests';Main='Gmk104LightingStudio.TransportTests';Source='TransportTests.cs'},
        @{Name='FeatureTests';Main='Gmk104LightingStudio.FeatureTests';Source='tests\FeatureTests.cs'},
        @{Name='NativeInputsTests';Main='NativeInputsTests';Source='tests\NativeInputsTests.cs'},
        @{Name='StudioTests';Main='Gmk104LightingStudio.StudioTests';Source='tests\StudioTests.cs'}
    )
    Push-Location -LiteralPath $projectPath
    try {
        foreach ($suite in $suites) {
            $testDirectory = Join-Path $testRoot $suite.Name
            New-Item -ItemType Directory -Path $testDirectory | Out-Null
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Resources\layout.json'),(Join-Path $PSScriptRoot 'Resources\default-led-map.json') -Destination $testDirectory
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tests\Fixtures\onboard-profile-all-effects-v1.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\onboard-profile-reactive-v1.2.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\onboard-capabilities-v1.2.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\onboard-profile-matrix-v1.3.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\matrix-native-frames-v1.6.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\onboard-capabilities-v1.3.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\spaced-matrix-native-v1.7.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\key-matrix-native-v1.7.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\onboard-profile-spaced-matrix-v1.7.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\onboard-profile-key-matrix-v1.7.bin'),(Join-Path $PSScriptRoot 'tests\Fixtures\onboard-capabilities-v1.7.bin') -Destination $testDirectory
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Resources\Profiles') -Destination $testDirectory -Recurse
            $testExe = Join-Path $testDirectory ($suite.Name + '.exe')
            $testSources = @($sources) + (Join-Path $PSScriptRoot $suite.Source)
            & $compiler /nologo /target:exe /platform:x64 /optimize+ /checked+ ('/main:' + $suite.Main) ('/out:' + $testExe) $references $testSources
            if ($LASTEXITCODE -ne 0) { throw ('Test build failed: ' + $suite.Name) }
            & $testExe
            if ($LASTEXITCODE -ne 0) { throw ('Tests failed: ' + $suite.Name) }
        }
        & (Join-Path $PSScriptRoot 'Firmware\Test-Firmware.ps1')
    } finally { Pop-Location }
    Write-Output "ALL TEST SUITES PASS: $testRoot"
}
