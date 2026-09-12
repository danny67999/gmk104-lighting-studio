param(
    [ValidateSet('DryRun','Inspect','TestConnection','Flash')][string]$Mode='DryRun',
    [ValidateSet('Custom','Wireless','Streaming','Stock')][string]$Target='Wireless',
    [string]$Confirmation,
    [switch]$NoPause
)
$ErrorActionPreference='Stop'
$resultCode=0
try {
    if($NoPause -and $Mode -ne 'DryRun'){throw 'Unattended device operations are not supported by the launcher.'}
    & (Join-Path $PSScriptRoot 'GMK104-Guarded-Flasher.ps1') -Mode $Mode -Target $Target -Confirmation $Confirmation
} catch {
    $resultCode=1
    Write-Host ('Operation stopped: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    Write-Host ''
    Write-Host ('Session files and any flash logs: ' + $PSScriptRoot)
    if(-not $NoPause){Read-Host 'Press Enter to close this results window' | Out-Null}
}
exit $resultCode
