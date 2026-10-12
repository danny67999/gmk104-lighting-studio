$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$checked = 0
function Assert-Check([bool]$Condition,[string]$Message) { if(-not$Condition){throw $Message}; $script:checked++ }
function Assert-Reject([scriptblock]$Action,[string]$Message) { $rejected=$false;try{& $Action}catch{$rejected=$true};Assert-Check $rejected $Message }
foreach($firmwareTarget in @('Release','Custom','Wireless','Streaming','Stock')) {
    . (Join-Path $PSScriptRoot 'GMK104-Guarded-Flasher.ps1') -Mode DryRun -Target $firmwareTarget
    Assert-Check ($plan.StreamHash -ceq $FirmwareTargets[$firmwareTarget].Stream) "$firmwareTarget stream did not match Mac golden hash"
    [byte[]]$changed=$image.Data.Clone();$changed[4096]=$changed[4096]-bxor 1
    $corrupted=[pscustomobject]@{Target=$image.Target;Path=$image.Path;Hash=$image.Hash;Crc=$image.Crc;Data=$changed}
    $bad=New-FlashPlan $corrupted
    Assert-Reject {Test-GoldenManifest $bad} "$firmwareTarget altered image packet stream was accepted"
    $copy=New-FlashPlan $image
    $copy.DataReports[1][4]=$copy.DataReports[1][4]-bxor 1
    Assert-Reject {Test-FlashPlan $copy} "$firmwareTarget reordered OTA block was accepted"
}
[byte[]]$vector=[Text.Encoding]::ASCII.GetBytes('123456789')
Assert-Check ((Get-VendorCrc32 $vector 9)-eq[uint32]0x340BC6D9L) 'Vendor CRC32 independent known vector failed'
Assert-Check ((Get-OtaCrc16 $vector)-eq 0x4B37) 'OTA CRC16 independent known vector failed'
$expected=@{
    Release=@([uint32]0xB85531A2L,[uint32]0xC6342859L,[uint32]0x060C4E9EL,[uint32]0x6F0AD0C1L,[uint32]0xD51110C3L,[uint32]0x938EFC28L,[uint32]0x37E8F32BL,[uint32]0x9066E8DBL,[uint32]0xB27DBFBEL,[uint32]0xA86B6815L,[uint32]0xD725D89AL,[uint32]0x193BCBFAL)
    Custom=@([uint32]0x7F2F4310L,[uint32]0xB85531A2L,[uint32]0x060C4E9EL,[uint32]0x6F0AD0C1L)
    Wireless=@([uint32]0x7F2F4310L,[uint32]0xC6342859L,[uint32]0x6F0AD0C1L)
    Streaming=@([uint32]0x7F2F4310L,[uint32]0x060C4E9EL)
    Stock=@([uint32]0x7F2F4310L,[uint32]0x193BCBFAL,[uint32]0xD725D89AL,[uint32]0xA86B6815L,[uint32]0xB27DBFBEL,[uint32]0xC6342859L,[uint32]0x060C4E9EL,[uint32]0x6F0AD0C1L,[uint32]0xC077F2F5L,[uint32]0xD51110C3L,[uint32]0xB6EA62D8L,[uint32]0x938EFC28L,[uint32]0x37E8F32BL,[uint32]0x9066E8DBL)
}

foreach($destination in @('Release','Custom','Wireless','Streaming','Stock')) {
    foreach($source in @([uint32]0x7F2F4310L,[uint32]0xC6342859L,[uint32]0x060C4E9EL,[uint32]0x6F0AD0C1L,[uint32]0xB85531A2L,[uint32]0xC077F2F5L,[uint32]0xD51110C3L,[uint32]0xB6EA62D8L,[uint32]0x938EFC28L,[uint32]0x37E8F32BL,[uint32]0x9066E8DBL,[uint32]0xB27DBFBEL,[uint32]0xA86B6815L,[uint32]0xD725D89AL,[uint32]0x193BCBFAL,[uint32]0x12345678L)) {
        Assert-Check ((Test-ApprovedTransition $source $destination)-eq($source-in$expected[$destination])) "Wrong transition decision for $source to $destination"
    }
}
[byte[]]$ack=New-Object byte[] 64;$ack[0]=5;$ack[1]=2
Test-OtaIntermediateAck $ack 'test'
[byte[]]$final=New-Object byte[] 64;[Array]::Copy(([byte[]](5,2,3,0,6,255,0)),$final,7)
Assert-Check (Test-OtaFinalResponse $final) 'Exact final success rejected'
Assert-Reject {Test-OtaIntermediateAck $final 'test'} 'Final status accepted as data acknowledgment'
$final[6]=1;Assert-Reject {Test-OtaFinalResponse $final} 'Failed activation accepted'
Assert-Check (-not(Test-OtaFinalResponse ([byte[]](5,2)))) 'Short final response accepted'
Assert-Reject {Test-OtaIntermediateAck ([byte[]](5,2)) 'test'} 'Short upload response accepted'
$badEnd=New-FlashPlan $image;$badEnd.End[8]=$badEnd.End[8]-bxor 1
Assert-Reject {Test-FlashPlan $badEnd} 'Invalid end complement accepted'
Write-Output "FIRMWARE OFFLINE TESTS PASS ($checked assertions; all five published golden image and packet hashes verified)."


[byte[]]$blank=New-Object byte[] 4096
for($i=0;$i-lt 4096;$i++){$blank[$i]=255}
Assert-Check (Test-StorageReservation $blank) 'Blank allocation rejected'
$blank[42]=0;Assert-Check (-not(Test-StorageReservation $blank)) 'Foreign storage accepted'
[byte[]]$owner=[Text.Encoding]::ASCII.GetBytes('GMK104-PROFILE-1')+[byte[]](0,0xC0,8,0,0,0xD0,8,0,0x85,0x60,0x14,0,0x47,0x4D,0x4B,0x4F)
[Array]::Copy($owner,0,$blank,3968,32)
Assert-Check (Test-StorageReservation $blank) 'Exact owned reservation rejected'
$blank[3968]=0;Assert-Check (-not(Test-StorageReservation $blank)) 'Foreign marker accepted'
Write-Output 'READ-ONLY STORAGE RESERVATION TESTS PASS'
