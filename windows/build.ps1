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
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'README.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $outputPath -Force }
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'VERIFICATION.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VERIFICATION.md') -Destination $outputPath -Force }
Write-Output "BUILD PASS: $exePath"
Get-FileHash -LiteralPath $exePath -Algorithm SHA256 | Select-Object Hash,Path
if ($Tests) {
    $testRoot = Join-Path $projectPath ('outputs\windows-test-results\' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $suites = @(
        @{Name='LightingTests';Main='Gmk104LightingStudio.LightingTests';Source='tests\LightingTests.cs'},
        @{Name='TransportTests';Main='Gmk104LightingStudio.TransportTests';Source='TransportTests.cs'},
        @{Name='NativeInputsTests';Main='NativeInputsTests';Source='tests\NativeInputsTests.cs'},
        @{Name='StudioTests';Main='Gmk104LightingStudio.StudioTests';Source='tests\StudioTests.cs'}
    )
    Push-Location -LiteralPath $projectPath
    try {
        foreach ($suite in $suites) {
            $testDirectory = Join-Path $testRoot $suite.Name
            New-Item -ItemType Directory -Path $testDirectory | Out-Null
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Resources\layout.json'),(Join-Path $PSScriptRoot 'Resources\default-led-map.json') -Destination $testDirectory
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
