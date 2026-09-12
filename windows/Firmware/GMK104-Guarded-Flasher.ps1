[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Inspect', 'DryRun', 'TestConnection', 'Flash')][string]$Mode = 'Inspect',
    [ValidateSet('Custom', 'Wireless', 'Streaming', 'Stock')][string]$Target = 'Custom',
    [string]$Confirmation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$CustomFileName = 'GMK104-custom-RGB-v0.2-experimental.bin'
$StockFileName = 'GMK104-stock-recovery.bin'
$ExpectedCustomHash = '96E431887F574CBE01E900FF08A803D8351EDE421A982809E294F34B1E7F0FD4'
$ExpectedStockHash = 'FD6E3E8B9D67E2E4942634FCB5C44275F1B1B4F6975F1691318C5A1D44E1661F'
$ExpectedCustomCrc = [uint32]0xC6342859L
$RetiredCustomCrc = [uint32]0xC077F2F5L
$ExpectedStockCrc = [uint32]0xB85531A2L
$ExpectedWirelessCrc = [uint32]0x060C4E9EL
$ExpectedStreamingCrc = [uint32]0x6F0AD0C1L
$ExpectedCustomStreamHash = '1565181114783AB9ED0E12EE4A5CC1366DD1412A1F36FEE7628926140377C0A7'
$ExpectedStockStreamHash = '818CF184FCE29532363DF592AAE2ADAAAB0AFEA345D99667240E5BA96302950A'
$ExpectedCustomPaddedHash = 'C68E839209350A16D4802533C204E49DF3201E5F59F6BB74FC1602BB2D5FCB91'
$ExpectedStockPaddedHash = '484FA932018A18A22EA7E536D07F0B19A27DBE5D0F8F8B24E9BFD3A495F3BFD7'
$FirmwareLength = 140244
$ExpectedUsbVersion = [uint16]0x0111
$FlashDeadlineMinutes = 12
$ReportId = [byte]5

# Exact image and independently verified OTA stream identities from the Mac project.
$FirmwareTargets = @{
    Custom = @{ File=$CustomFileName; Hash=$ExpectedCustomHash; Crc=$ExpectedCustomCrc; Length=140244;
        Stream=$ExpectedCustomStreamHash; Padded=$ExpectedCustomPaddedHash;
        Sources=@($ExpectedStockCrc,$ExpectedWirelessCrc,$ExpectedStreamingCrc); Phrase='FLASH GMK104 CUSTOM C6342859' }
    Wireless = @{ File='GMK104-custom-RGB-v0.3-experimental.bin'; Hash='CFB5604E1B861948078C0176801A74EF45727C96225145DA82B25FB81B96DD8A'; Crc=$ExpectedWirelessCrc; Length=142820;
        Stream='D2847D4B445AA3D71DEA6F9479B77ADD70DAFC10BF570704D9793B91E89A9D77'; Padded='439608D8FE9AD55280972047820EC7CD2BB586BEA4F1CB654BB54A3A11B47A1F';
        Sources=@($ExpectedCustomCrc,$ExpectedStreamingCrc); Phrase='TEST GMK104 WIRELESS 060C4E9E' }
    Streaming = @{ File='GMK104-custom-RGB-v0.4-experimental.bin'; Hash='11DB2CD854381021B45C0B025D7FABC5277CDBFED185A4E8AF0E9327D7ACC347'; Crc=$ExpectedStreamingCrc; Length=142820;
        Stream='87005D5D7E249C731B135923A447DA28A30514DD7FDB3BB1546C3471132E2C57'; Padded='1610D752A299D26CEFE6A744FAE900AC3C1EB877210217A808238526542F8976';
        Sources=@($ExpectedWirelessCrc); Phrase='TEST GMK104 BLUETOOTH 6F0AD0C1' }
    Stock = @{ File=$StockFileName; Hash=$ExpectedStockHash; Crc=$ExpectedStockCrc; Length=140244;
        Stream=$ExpectedStockStreamHash; Padded=$ExpectedStockPaddedHash;
        Sources=@($ExpectedCustomCrc,$ExpectedWirelessCrc,$ExpectedStreamingCrc,$RetiredCustomCrc); Phrase='RESTORE GMK104 STOCK B85531A2' }
}

function Test-ApprovedTransition {
    param([uint32]$Source,[ValidateSet('Custom','Wireless','Streaming','Stock')][string]$ImageTarget)
    return $Source -in $FirmwareTargets[$ImageTarget].Sources
}

if (-not ('Gmk104WindowsFirmwareHid' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public static class Gmk104WindowsFirmwareHid {
    const uint PRESENT=2, INTERFACE=16, READ=0x80000000, WRITE=0x40000000;
    const uint SHARE_READ=1, SHARE_WRITE=2, OPEN_EXISTING=3, OVERLAPPED=0x40000000;
    const uint ES_SYSTEM_REQUIRED=1, ES_CONTINUOUS=0x80000000;

    [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA {
        public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved;
    }
    [StructLayout(LayoutKind.Sequential)] struct SP_DEVINFO_DATA {
        public int cbSize; public Guid ClassGuid; public uint DevInst; public IntPtr Reserved;
    }
    [StructLayout(LayoutKind.Sequential)] struct DEVPROPKEY { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Sequential)] public struct HIDD_ATTRIBUTES {
        public int Size; public ushort VendorID, ProductID, VersionNumber;
    }
    [StructLayout(LayoutKind.Sequential)] public struct HIDP_CAPS {
        public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps,
            NumberInputDataIndices, NumberOutputButtonCaps, NumberOutputValueCaps,
            NumberOutputDataIndices, NumberFeatureButtonCaps, NumberFeatureValueCaps,
            NumberFeatureDataIndices;
    }
    public sealed class DeviceInfo {
        public string Path, Product, Manufacturer; public Guid ContainerId;
        public HIDD_ATTRIBUTES Attributes; public HIDP_CAPS Caps;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr SetupDiGetClassDevs(ref Guid g, string e, IntPtr w, uint flags);
    [DllImport("setupapi.dll", SetLastError=true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, uint i,
        ref SP_DEVICE_INTERFACE_DATA x);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true,
        EntryPoint="SetupDiGetDeviceInterfaceDetailW")]
    static extern bool DetailProbe(IntPtr s, ref SP_DEVICE_INTERFACE_DATA x, IntPtr detail,
        int size, out int needed, IntPtr d);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true,
        EntryPoint="SetupDiGetDeviceInterfaceDetailW")]
    static extern bool DetailData(IntPtr s, ref SP_DEVICE_INTERFACE_DATA x, IntPtr detail,
        int size, out int needed, ref SP_DEVINFO_DATA d);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true,
        EntryPoint="SetupDiGetDevicePropertyW")]
    static extern bool GetProperty(IntPtr s, ref SP_DEVINFO_DATA d, ref DEVPROPKEY key,
        out uint type, byte[] buffer, uint size, out uint needed, uint flags);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string n, uint access, uint share, IntPtr sec,
        uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CancelIoEx(SafeFileHandle h, IntPtr o);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern uint SetThreadExecutionState(uint flags);
    [DllImport("hid.dll", SetLastError=true)]
    static extern bool HidD_GetAttributes(SafeFileHandle h, ref HIDD_ATTRIBUTES a);
    [DllImport("hid.dll", SetLastError=true)]
    static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr p);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_FreePreparsedData(IntPtr p);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr p, out HIDP_CAPS c);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_FlushQueue(SafeFileHandle h);
    [DllImport("hid.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool HidD_GetProductString(SafeFileHandle h, StringBuilder b, int n);
    [DllImport("hid.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool HidD_GetManufacturerString(SafeFileHandle h, StringBuilder b, int n);

    static SafeFileHandle Open(string path, bool exclusive) {
        uint share = exclusive ? 0 : SHARE_READ | SHARE_WRITE;
        return CreateFile(path, READ | WRITE, share, IntPtr.Zero, OPEN_EXISTING, OVERLAPPED, IntPtr.Zero);
    }
    static string GetString(SafeFileHandle h, bool product) {
        var b=new StringBuilder(256);
        bool ok=product ? HidD_GetProductString(h,b,b.Capacity*2) : HidD_GetManufacturerString(h,b,b.Capacity*2);
        return ok ? b.ToString() : "";
    }
    static Guid Container(IntPtr s, ref SP_DEVINFO_DATA d) {
        var key=new DEVPROPKEY { fmtid=new Guid("8C7ED206-3F8A-4827-B3AB-AE9E1FAEFC6C"), pid=2 };
        var b=new byte[16]; uint type, needed;
        if (!GetProperty(s,ref d,ref key,out type,b,16,out needed,0) || type!=13 || needed!=16)
            return Guid.Empty;
        return new Guid(b);
    }
    public static List<DeviceInfo> Enumerate() {
        Guid g; HidD_GetHidGuid(out g);
        IntPtr s=SetupDiGetClassDevs(ref g,null,IntPtr.Zero,PRESENT|INTERFACE);
        if (s==new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        var list=new List<DeviceInfo>();
        try {
            for(uint i=0;;i++) {
                var x=new SP_DEVICE_INTERFACE_DATA(); x.cbSize=Marshal.SizeOf(x);
                if(!SetupDiEnumDeviceInterfaces(s,IntPtr.Zero,ref g,i,ref x)) {
                    int e=Marshal.GetLastWin32Error(); if(e==259) break; throw new Win32Exception(e);
                }
                int needed; DetailProbe(s,ref x,IntPtr.Zero,0,out needed,IntPtr.Zero);
                IntPtr detail=Marshal.AllocHGlobal(needed);
                try {
                    Marshal.WriteInt32(detail,IntPtr.Size==8?8:6);
                    var d=new SP_DEVINFO_DATA(); d.cbSize=Marshal.SizeOf(d);
                    if(!DetailData(s,ref x,detail,needed,out needed,ref d))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    string path=Marshal.PtrToStringUni(IntPtr.Add(detail,4));
                    using(var h=Open(path,false)) {
                        if(h.IsInvalid) continue;
                        var a=new HIDD_ATTRIBUTES(); a.Size=Marshal.SizeOf(a);
                        if(!HidD_GetAttributes(h,ref a)) continue;
                        IntPtr p; if(!HidD_GetPreparsedData(h,out p)) continue;
                        try {
                            HIDP_CAPS c; if(HidP_GetCaps(p,out c)<0) continue;
                            list.Add(new DeviceInfo { Path=path, Product=GetString(h,true),
                                Manufacturer=GetString(h,false), ContainerId=Container(s,ref d),
                                Attributes=a, Caps=c });
                        } finally { HidD_FreePreparsedData(p); }
                    }
                } finally { Marshal.FreeHGlobal(detail); }
            }
        } finally { SetupDiDestroyDeviceInfoList(s); }
        return list;
    }

    public sealed class Session : IDisposable {
        SafeFileHandle handle; FileStream stream; int inputLength, outputLength;
        readonly Stopwatch pacing=Stopwatch.StartNew(); long earliest; int afterReply; bool faulted;
        public Session(string path,int input,int output,bool exclusive) {
            afterReply=exclusive?40:0;
            inputLength=input; outputLength=output; handle=Open(path,exclusive);
            if(handle.IsInvalid) { int e=Marshal.GetLastWin32Error(); handle.Dispose();
                throw new Win32Exception(e, exclusive ?
                    "Could not open GMK104 exclusively. Close VIA, RGB tools, and vendor updaters." :
                    "Could not open the GMK104 HID interface."); }
            stream=new FileStream(handle,FileAccess.ReadWrite,1,true);
        }
        static bool Wait(Task t,int ms) { return Task.WaitAny(new Task[]{t},Math.Max(0,ms))==0; }
        static void Observe(Task t) { if(t==null)return; try { if(!t.IsCompleted)Task.WaitAny(new Task[]{t},2000);
            if(t.IsCompleted)t.GetAwaiter().GetResult(); } catch {} }
        void Cancel(Task r,Task w) { try{CancelIoEx(handle,IntPtr.Zero);}catch{} Observe(w); Observe(r); }
        public void FlushInputQueue() { if(!HidD_FlushQueue(handle))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not clear the GMK104 input queue."); }
        public byte[] Exchange(byte[] report,int timeout,bool flushFirst) {
            if(faulted)throw new IOException("This firmware connection is faulted. Automatic retries are prohibited.");
            if(report==null||report.Length!=outputLength)throw new ArgumentException("Output report length mismatch.");
            int delay=(int)Math.Max(0,earliest-pacing.ElapsedMilliseconds); if(delay>0)System.Threading.Thread.Sleep(delay);
            if(flushFirst)FlushInputQueue(); var response=new byte[inputLength];
            Task<int> r=null; Task w=null; var timer=Stopwatch.StartNew();
            try {
                earliest=pacing.ElapsedMilliseconds+16;
                r=stream.ReadAsync(response,0,response.Length); w=stream.WriteAsync(report,0,report.Length);
                if(!Wait(w,timeout))throw new TimeoutException("Timed out writing a GMK104 HID report.");
                w.GetAwaiter().GetResult(); int left=timeout-(int)timer.ElapsedMilliseconds;
                if(!Wait(r,left))throw new TimeoutException("Timed out waiting for a GMK104 HID response.");
                int count=r.GetAwaiter().GetResult();
                if(count!=inputLength)throw new IOException(String.Format("Short HID response: {0}/{1} bytes.",count,inputLength));
                earliest=Math.Max(earliest,pacing.ElapsedMilliseconds+afterReply);
                return response;
            } catch { faulted=true; Cancel(r,w); throw; } finally { timer.Stop(); }
        }
        public void Dispose() { try{if(stream!=null)stream.Dispose();}catch{}
            try{if(handle!=null&&!handle.IsClosed)handle.Dispose();}catch{} }
    }
    public static byte[] QueryVersion(DeviceInfo d,int timeout) {
        var q=new byte[d.Caps.OutputReportByteLength]; q[0]=5;q[1]=1;
        using(var s=new Session(d.Path,d.Caps.InputReportByteLength,d.Caps.OutputReportByteLength,false))
            return s.Exchange(q,timeout,true);
    }
    public static byte[] QueryVia(DeviceInfo d,byte[] payload,int timeout) {
        var q=new byte[d.Caps.OutputReportByteLength]; Array.Copy(payload,0,q,1,Math.Min(payload.Length,q.Length-1));
        using(var s=new Session(d.Path,d.Caps.InputReportByteLength,d.Caps.OutputReportByteLength,false))
            return s.Exchange(q,timeout,true);
    }
    public static void BeginPowerHold() { if(SetThreadExecutionState(ES_CONTINUOUS|ES_SYSTEM_REQUIRED)==0)
        throw new Win32Exception(Marshal.GetLastWin32Error(),"Windows refused to prevent sleep."); }
    public static void EndPowerHold() { SetThreadExecutionState(ES_CONTINUOUS); }
    public static uint VendorCrc(byte[] bytes,int length) { uint c=uint.MaxValue; for(int i=0;i<length;i++){c^=bytes[i];for(int j=0;j<8;j++)c=(c&1)!=0?(c>>1)^0xEDB88320u:c>>1;}return c; }
    public static ushort OtaCrc(byte[] bytes) { ushort c=ushort.MaxValue;foreach(byte b in bytes){c^=b;for(int j=0;j<8;j++)c=(ushort)(((c&1)!=0)?(c>>1)^0xA001:c>>1);}return c; }
}
'@
}

function Get-VendorCrc32 {
    param([byte[]]$Data,[int]$Length)
    return [Gmk104WindowsFirmwareHid]::VendorCrc($Data,$Length)
}

function Get-OtaCrc16 {
    param([byte[]]$Data)
    return [Gmk104WindowsFirmwareHid]::OtaCrc($Data)
}

function Get-Sha256Hex {
    param([byte[]]$Data)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Data))).Replace('-','')}
    finally{$sha.Dispose()}
}

function Assert-ImageBytes {
    param([byte[]]$Data,[int]$Offset,[byte[]]$Expected,[string]$Name)
    for($i=0;$i-lt$Expected.Length;$i++) {
        if($Data[$Offset+$i]-ne$Expected[$i]){throw ('{0} marker mismatch at 0x{1:X}.' -f $Name,($Offset+$i))}
    }
}

function Read-ApprovedFirmware {
    param([ValidateSet('Custom','Wireless','Streaming','Stock')][string]$ImageTarget)
    $definition=$FirmwareTargets[$ImageTarget]
    $name=$definition.File
    $wantedHash=$definition.Hash
    $wantedCrc=$definition.Crc
    $path=Join-Path $PSScriptRoot $name
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing approved image: $path"}
    [byte[]]$data=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path))
    $hash=Get-Sha256Hex $data
    if($hash-cne$wantedHash){throw "Refusing modified $ImageTarget image. SHA-256 was $hash"}
    if($data.Length-ne$definition.Length){throw "Unexpected $ImageTarget image length: $($data.Length)"}
    if((($data.Length-4)%16)-ne 0){throw "$ImageTarget CRC boundary is not OTA-block aligned."}
    if([BitConverter]::ToUInt32($data,0x18)-ne$data.Length){throw "$ImageTarget internal length is invalid."}
    Assert-ImageBytes $data 0x20 ([Text.Encoding]::ASCII.GetBytes('KNLT')) "$ImageTarget KNLT"
    $stored=[BitConverter]::ToUInt32($data,$data.Length-4)
    $computed=Get-VendorCrc32 $data ($data.Length-4)
    if($stored-ne$wantedCrc-or$computed-ne$wantedCrc){throw ('{0} CRC mismatch: stored=0x{1:X8}, computed=0x{2:X8}' -f $ImageTarget,$stored,$computed)}
    if((Get-VendorCrc32 $data $data.Length)-ne 0){throw "$ImageTarget full-image CRC residue is invalid."}
    if($ImageTarget-eq'Custom') {
        Assert-ImageBytes $data 0x1BA38 ([byte[]](0x6F,0x50,0xCE,0xE6,0x13,0,0,0)) 'Custom SET hook'
        Assert-ImageBytes $data 0x1BD48 ([byte[]](0x6F,0x50,0xCE,0xC4,0x13,0,0,0)) 'Custom GET hook'
        Assert-ImageBytes $data 0x1F654 ([byte[]](0x90,0x11,0,0x20)) 'Custom effect pointer'
        Assert-ImageBytes $data 0x1120 ([byte[]](0x0B,0x1E,0x42,0x3D,0x13,0,0,0)) 'GP-relative SET framebuffer'
        Assert-ImageBytes $data 0x1164 ([byte[]](0x0B,0x1E,0x42,0x3D,0x13,0,0,0)) 'GP-relative clear framebuffer'
        Assert-ImageBytes $data 0x1190 ([byte[]](0x6F,0xC0,0x50,0x34)) 'Effect 19 stock-tail wrapper'
        Assert-ImageBytes $data 0x121C ([byte[]](0x8B,0x13,0x42,0x3D,0x13,0,0,0)) 'GP-relative GET framebuffer'
        Assert-ImageBytes $data 0x1270 ([byte[]](0x6F,0xA0,0x91,0x03,0x6F,0xA0,0xD1,0x2D)) 'Custom GET exits'
        Assert-ImageBytes $data 0x1278 ([byte[]](0,0,0,0,0,0,0,0)) 'Custom cave margin'
        Assert-ImageBytes $data 0x12A0 ([byte[]](0x00,0xE0,0x0F,0x00,0x97,0x04,0,0)) 'Custom cave hard stop'
    } elseif($ImageTarget-eq'Stock') {
        Assert-ImageBytes $data 0x1BA38 ([byte[]](0x8B,0x97,0x1F,0xD2,0x03,0x47,0x16,0)) 'Stock SET entry'
        Assert-ImageBytes $data 0x1BD48 ([byte[]](0x8B,0x97,0x1F,0xD2,0x03,0x47,0x16,0)) 'Stock GET entry'
        Assert-ImageBytes $data 0x1F654 ([byte[]](0x5C,0xE8,0,0x20)) 'Stock effect pointer'
    }
    return [pscustomobject]@{Target=$ImageTarget;Path=$path;Hash=$hash;Crc=$stored;Data=$data}
}

function New-OtaReport {
    [byte[]]$r=New-Object byte[] 64
    for($i=0;$i-lt 64;$i++){$r[$i]=0xFF}
    $r[0]=$ReportId
    return ,$r
}

function New-FlashPlan {
    param([pscustomobject]$Image)
    $chunks=[int][Math]::Ceiling($Image.Data.Length/16.0)
    [byte[]]$padded=New-Object byte[] ($chunks*16)
    for($i=0;$i-lt$padded.Length;$i++){$padded[$i]=0xFF}
    [Array]::Copy($Image.Data,$padded,$Image.Data.Length)
    [byte[]]$start=New-OtaReport
    $start[1]=2;$start[2]=2;$start[3]=0;$start[4]=1;$start[5]=0xFF
    $reports=New-Object Collections.ArrayList
    for($first=0;$first-lt$chunks;$first+=3) {
        [byte[]]$r=New-OtaReport
        $count=[Math]::Min(3,$chunks-$first);$r[1]=2;$r[2]=[byte](20*$count);$r[3]=0
        for($slot=0;$slot-lt$count;$slot++) {
            $index=$first+$slot;[byte[]]$crcBytes=New-Object byte[] 18
            $crcBytes[0]=[byte]($index-band 0xFF);$crcBytes[1]=[byte](($index-shr 8)-band 0xFF)
            [Array]::Copy($padded,$index*16,$crcBytes,2,16);$crc=Get-OtaCrc16 $crcBytes;$base=4+20*$slot
            [Array]::Copy($crcBytes,0,$r,$base,18);$r[$base+18]=[byte]($crc-band 0xFF);$r[$base+19]=[byte](($crc-shr 8)-band 0xFF)
        }
        [void]$reports.Add($r)
    }
    [byte[]]$end=New-OtaReport
    [uint16]$last=$chunks-1;[uint16]$inverse=(0x10000L-$last)-band 0xFFFF
    $end[1]=2;$end[2]=6;$end[3]=0;$end[4]=2;$end[5]=0xFF
    $end[6]=[byte]($last-band 0xFF);$end[7]=[byte](($last-shr 8)-band 0xFF)
    $end[8]=[byte]($inverse-band 0xFF);$end[9]=[byte](($inverse-shr 8)-band 0xFF)
    $stream=New-Object IO.MemoryStream
    try{$stream.Write($start,0,64);foreach($r in $reports){$stream.Write($r,0,64)};$stream.Write($end,0,64);$streamHash=Get-Sha256Hex $stream.ToArray()}
    finally{$stream.Dispose()}
    return [pscustomobject]@{Image=$Image;ChunkCount=$chunks;Padded=$padded;Start=$start;
        DataReports=$reports;End=$end;LastIndex=$last;PaddingCount=$padded.Length-$Image.Data.Length;
        PaddedHash=(Get-Sha256Hex $padded);StreamHash=$streamHash}
}

function Assert-Prefix {
    param([byte[]]$Data,[byte[]]$Expected,[string]$Name)
    if($null-eq$Data-or$Data.Length-lt$Expected.Length){throw "$Name is too short."}
    for($i=0;$i-lt$Expected.Length;$i++){if($Data[$i]-ne$Expected[$i]){throw "$Name mismatch at byte $i."}}
}

function Test-FlashPlan {
    param([pscustomobject]$Plan)
    [byte[]]$rebuilt=New-Object byte[] $Plan.Padded.Length;$expected=0
    foreach($r in $Plan.DataReports) {
        if($r.Length-ne 64-or$r[0]-ne 5-or$r[1]-ne 2-or$r[2]-notin 20,40,60){throw 'Malformed OTA data report.'}
        for($slot=0;$slot-lt($r[2]/20);$slot++) {
            $base=4+20*$slot;$index=[int]$r[$base]+([int]$r[$base+1]-shl 8)
            if($index-ne$expected){throw "OTA index gap at $expected."}
            [byte[]]$crcBytes=New-Object byte[] 18;[Array]::Copy($r,$base,$crcBytes,0,18)
            $stored=[uint16]([int]$r[$base+18]+([int]$r[$base+19]-shl 8))
            if($stored-ne(Get-OtaCrc16 $crcBytes)){throw "OTA CRC16 mismatch at chunk $index."}
            [Array]::Copy($r,$base+2,$rebuilt,$index*16,16);$expected++
        }
    }
    if($expected-ne$Plan.ChunkCount-or-not(Test-ByteArrayEqual $rebuilt $Plan.Padded)){throw 'OTA reconstruction failed.'}
    $endLast=[uint16]([int]$Plan.End[6]+([int]$Plan.End[7]-shl 8));$endInv=[uint16]([int]$Plan.End[8]+([int]$Plan.End[9]-shl 8))
    if($endLast-ne$Plan.LastIndex-or((([int]$endLast+[int]$endInv)-band 0xFFFF)-ne 0)){throw 'OTA END index check failed.'}
}

function Test-ByteArrayEqual {
    param([byte[]]$First,[byte[]]$Second)
    if($null-eq$First-or$null-eq$Second-or$First.Length-ne$Second.Length){return $false}
    for($i=0;$i-lt$First.Length;$i++){if($First[$i]-ne$Second[$i]){return $false}}
    return $true
}

function Test-GoldenManifest {
    param([pscustomobject]$Plan)
    $definition=$FirmwareTargets[$Plan.Image.Target]
    $stream=$definition.Stream;$padded=$definition.Padded
    $chunks=[int][Math]::Ceiling($definition.Length/16.0);$reports=[int][Math]::Ceiling($definition.Length/48.0)
    if($Plan.ChunkCount-ne$chunks-or$Plan.DataReports.Count-ne$reports-or$Plan.LastIndex-ne($chunks-1)-or$Plan.PaddingCount-ne 12){throw 'OTA dimensions differ from golden manifest.'}
    if($Plan.StreamHash-cne$stream-or$Plan.PaddedHash-cne$padded){throw 'OTA hash differs from golden manifest.'}
    Assert-Prefix $Plan.Start ([byte[]](5,2,2,0,1,0xFF)) 'OTA START'
    Assert-Prefix $Plan.End ([byte[]](5,2,6,0,2,0xFF)) 'OTA END'
    for($i=6;$i-lt 64;$i++){if($Plan.Start[$i]-ne 0xFF){throw 'START padding mismatch.'}}
    for($i=10;$i-lt 64;$i++){if($Plan.End[$i]-ne 0xFF){throw 'END padding mismatch.'}}
    $first=$Plan.DataReports[0];$last=$Plan.DataReports[$Plan.DataReports.Count-1]
    [uint16]$a=[int]$first[22]+([int]$first[23]-shl 8);[uint16]$b=[int]$last[62]+([int]$last[63]-shl 8)
    if($Plan.Image.Target-eq'Custom'-and($a-ne 0xCC80-or$b-ne 0x28EE)){throw 'v0.2 OTA boundary CRC differs from golden manifest.'}
    if($Plan.Image.Target-eq'Stock'-and($a-ne 0xCC80-or$b-ne 0x4EFD)){throw 'Stock OTA boundary CRC differs from golden manifest.'}
}

function Convert-VersionResponse {
    param([byte[]]$Response)
    if($null-eq$Response-or$Response.Length-ne 64){throw 'OTA version response length is invalid.'}
    Assert-Prefix $Response ([byte[]](5,1,8,0)) 'OTA version response'
    return [pscustomobject]@{Version=[BitConverter]::ToUInt32($Response,4);Crc=[BitConverter]::ToUInt32($Response,8)}
}

function Get-VerifiedVersionFromDevice {
    param([object]$Device)
    [byte[]]$a=[Gmk104WindowsFirmwareHid]::QueryVersion($Device,3000)
    [byte[]]$b=[Gmk104WindowsFirmwareHid]::QueryVersion($Device,3000)
    if(-not(Test-ByteArrayEqual $a $b)){throw 'Keyboard returned inconsistent version responses.'}
    return Convert-VersionResponse $a
}

function Get-VerifiedVersionFromSession {
    param([object]$Session)
    [byte[]]$q=New-Object byte[] 64;$q[0]=5;$q[1]=1
    [byte[]]$a=$Session.Exchange($q,3000,$true);[byte[]]$b=$Session.Exchange($q,3000,$true)
    if(-not(Test-ByteArrayEqual $a $b)){throw 'Exclusive keyboard handle returned inconsistent version responses.'}
    return Convert-VersionResponse $a
}

function Assert-NormalViaResponse {
    param([object]$Via)
    [byte[]]$r=[Gmk104WindowsFirmwareHid]::QueryVia($Via,([byte[]](1)),3000)
    if($r.Length-ne 33){throw 'VIA protocol response length is invalid.'}
    Assert-Prefix $r ([byte[]](0,1,0,0x0B)) 'VIA protocol response'
}

function Assert-CustomViaSignature {
    param([object]$Via,[ValidateSet(1,2)][int]$Revision=2)
    [byte[]]$r=[Gmk104WindowsFirmwareHid]::QueryVia($Via,([byte[]](8,3,5)),3000)
    if($r.Length-ne 33){throw 'Custom VIA signature response length is invalid.'}
    if($Revision-eq 1) {
        Assert-Prefix $r ([byte[]](0,8,3,5,1,0x68,9,3,0x47,0x4D,0x4B,1)) 'Retired v0.1 custom VIA signature'
    } else {
        Assert-Prefix $r ([byte[]](0,8,3,5,2,0x68,9,0x0F,0x47,0x4D,0x4B,2,0)) 'Custom v0.2 VIA signature'
    }
}

function Get-Gmk104State {
    $all=@([Gmk104WindowsFirmwareHid]::Enumerate()|Where-Object{$_.Attributes.VendorID-eq 0x320F-and$_.Attributes.ProductID-eq 0x5055})
    $ota=@($all|Where-Object{$_.Caps.UsagePage-eq 0xFFEF-and$_.Caps.Usage-eq 0})
    $via=@($all|Where-Object{$_.Caps.UsagePage-eq 0xFF60-and$_.Caps.Usage-eq 0x0061})
    if($ota.Count-ne 1){throw "Expected exactly one GMK104 OTA interface; found $($ota.Count)."}
    if($via.Count-ne 1){throw "Expected exactly one GMK104 VIA interface; found $($via.Count)."}
    $o=$ota[0];$v=$via[0]
    if($o.Product-cne'ZUOYA GMK104'-or$v.Product-cne'ZUOYA GMK104'-or$o.Manufacturer-cne'RDR'-or$v.Manufacturer-cne'RDR'){
        throw 'GMK104 USB product/manufacturer identity mismatch.'
    }
    if($o.Attributes.VersionNumber-ne$ExpectedUsbVersion-or$v.Attributes.VersionNumber-ne$ExpectedUsbVersion){throw 'GMK104 USB device version mismatch.'}
    if($o.ContainerId-eq[Guid]::Empty-or$v.ContainerId-eq[Guid]::Empty-or$o.ContainerId-ne$v.ContainerId){throw 'OTA and VIA interfaces are not proven to belong to one physical keyboard.'}
    if($o.Caps.InputReportByteLength-ne 64-or$o.Caps.OutputReportByteLength-ne 64-or$o.Caps.FeatureReportByteLength-ne 64){throw 'Unexpected OTA HID report shape.'}
    if($v.Caps.InputReportByteLength-ne 33-or$v.Caps.OutputReportByteLength-ne 33-or$v.Caps.FeatureReportByteLength-ne 0){throw 'Unexpected VIA HID report shape.'}
    $version=Get-VerifiedVersionFromDevice $o
    if($version.Version-ne 0){throw ('Unexpected firmware version field 0x{0:X8}.' -f $version.Version)}
    if($version.Crc-notin@($ExpectedStockCrc,$ExpectedCustomCrc,$ExpectedWirelessCrc,$ExpectedStreamingCrc,$RetiredCustomCrc)){throw ('Unapproved installed CRC 0x{0:X8}.' -f $version.Crc)}
    Assert-NormalViaResponse $v
    return [pscustomobject]@{Device=$o;ViaDevice=$v;Version=$version.Version;Crc=$version.Crc;ContainerId=$o.ContainerId}
}

function Assert-WirelessSleepSignature {
    param([object]$Via)
    [byte[]]$r=[Gmk104WindowsFirmwareHid]::QueryVia($Via,([byte[]](8,3,6,1)),3000)
    if($r.Length-ne 33){throw 'Sleep-setting response length is invalid.'}
    Assert-Prefix $r ([byte[]](0,8,3,6,1,71,77,75,83)) 'Custom wireless sleep signature'
    Assert-ImageBytes $r 11 ([byte[]](3,3,16,14,60,0)) 'Sleep capability bytes'
    $seconds=[int]$r[9]+([int]$r[10]-shl 8)
    if($seconds-ne 0-and($seconds-lt 60-or$seconds-gt 3600)){throw 'Invalid sleep setting.'}
}

function Test-SustainedConnection {
    param([object]$State)
    $check=[Gmk104WindowsFirmwareHid+Session]::new($State.Device.Path,64,64,$false)
    try {
        for($i=0;$i-lt 2000;$i++) {
            $identity=Get-VerifiedVersionFromSession $check
            if($identity.Version-ne 0-or$identity.Crc-ne$State.Crc){throw 'Firmware identity changed during the read-only connection check.'}
            if(($i+1)%50-eq 0){Write-Progress -Activity 'Testing USB connection (read only)' -Status ('{0}/4000 replies' -f (($i+1)*2)) -PercentComplete (($i+1)/20)}
        }
    } finally {$check.Dispose();Write-Progress -Activity 'Testing USB connection (read only)' -Completed}
    $after=Get-Gmk104State
    if($after.Crc-ne$State.Crc-or$after.ContainerId-ne$State.ContainerId-or$after.Device.Path-cne$State.Device.Path-or$after.ViaDevice.Path-cne$State.ViaDevice.Path){throw 'Keyboard attachment changed during the connection check.'}
    Write-Output 'READ-ONLY CONNECTION CHECK: 4000 consistent firmware replies passed.'
}

function Test-OtaIntermediateAck {
    param([byte[]]$Response,[string]$Stage)
    if($null-eq$Response-or$Response.Length-ne 64-or$Response[0]-ne 5-or$Response[1]-ne 2){throw "$Stage returned an invalid OTA acknowledgment."}
    if($Response[2]-eq 3-and$Response[3]-eq 0-and$Response[4]-eq 6-and$Response[5]-eq 0xFF){throw "$Stage returned an unexpected final-status frame."}
}

function Test-OtaFinalResponse {
    param([byte[]]$Response)
    if($null-eq$Response-or$Response.Length-ne 64){return $false}
    if($Response[0]-eq 5-and$Response[1]-eq 2-and$Response[2]-eq 3-and$Response[3]-eq 0-and$Response[4]-eq 6-and$Response[5]-eq 0xFF){
        if($Response[6]-ne 0){throw "OTA END reported failure code $($Response[6])."}
        return $true
    }
    return $false
}

function Write-FlashLog {
    param([IO.StreamWriter]$Writer,[string]$Message)
    if($null-eq$Writer){return}
    if(-not$script:FlashLogRequired-and$null-ne$script:FlashLogFault){return}
    try{$Writer.WriteLine(('{0:o} {1}' -f [DateTime]::UtcNow,$Message))}
    catch{
        if($script:FlashLogRequired){throw}
        if($null-eq$script:FlashLogFault){$script:FlashLogFault=$_.Exception.Message}
    }
}

$script:FlashLogRequired=$true
$script:FlashLogFault=$null
$image=Read-ApprovedFirmware $Target
$stockImage=if($Target-eq'Stock'){$image}else{Read-ApprovedFirmware 'Stock'}
Write-Output 'Approved firmware files: PASS'
Write-Output ('  Target SHA-256 {0}, CRC 0x{1:X8}' -f $image.Hash.ToLowerInvariant(),$image.Crc)
Write-Output ('  Stock  SHA-256 {0}, CRC 0x{1:X8}' -f $stockImage.Hash.ToLowerInvariant(),$stockImage.Crc)

$plan=New-FlashPlan $image
Test-FlashPlan $plan
Test-GoldenManifest $plan
Write-Output 'Complete OTA packet validation: PASS'
Write-Output ('  Target={0}, chunks={1}, data reports={2}, last index={3}' -f $Target,$plan.ChunkCount,$plan.DataReports.Count,$plan.LastIndex)
Write-Output ('  Padded-image SHA-256: {0}' -f $plan.PaddedHash.ToLowerInvariant())
Write-Output ('  Packet-stream SHA-256: {0}' -f $plan.StreamHash.ToLowerInvariant())
if($Mode-eq'DryRun'){
    Write-Output 'OFFLINE DRY RUN COMPLETE. No HID device was opened and no report was sent.'
    return
}

$flashMutex=$null;$mutexHeld=$false;$logWriter=$null
try {
    if($Mode-eq'Flash'){
        $flashMutex=[Threading.Mutex]::new($false,'Local\GMK104GuardedFlasher')
        $mutexHeld=$flashMutex.WaitOne(0)
        if(-not$mutexHeld){throw 'Another guarded GMK104 flash process is already running.'}
    }
    $state=Get-Gmk104State
    Write-Output 'Connected keyboard identity: PASS'
    Write-Output ('  Product={0}; manufacturer={1}; USB version=0x{2:X4}' -f $state.Device.Product,$state.Device.Manufacturer,$state.Device.Attributes.VersionNumber)
    Write-Output ('  Physical container={0}' -f $state.ContainerId)
    Write-Output ('  Installed version=0x{0:X8}, CRC=0x{1:X8}' -f $state.Version,$state.Crc)
    if($state.Crc-in@($ExpectedCustomCrc,$ExpectedWirelessCrc,$ExpectedStreamingCrc)){Assert-CustomViaSignature $state.ViaDevice 2;Write-Output '  Compatible custom RGB signature: PASS'}
    elseif($state.Crc-eq$RetiredCustomCrc){Assert-CustomViaSignature $state.ViaDevice 1;Write-Warning 'Retired custom v0.1 is installed; only stock rollback is permitted.'}
    if($state.Crc-in@($ExpectedWirelessCrc,$ExpectedStreamingCrc)){Assert-WirelessSleepSignature $state.ViaDevice}
    if($Mode-eq'Inspect'){
        Write-Output 'READ-ONLY INSPECTION COMPLETE. Only passive version and VIA queries were sent; OTA START was not sent.'
        return
    }
    if($Mode-eq'TestConnection'){Test-SustainedConnection $state;return}

    if($state.Crc-eq$image.Crc){Write-Output "NO-OP: approved $Target firmware is already installed. No OTA command was sent.";return}
    [uint32[]]$allowedSourceCrcs=$FirmwareTargets[$Target].Sources
    if(-not(Test-ApprovedTransition $state.Crc $Target)){
        $expected=($allowedSourceCrcs|ForEach-Object{'0x{0:X8}'-f$_})-join', '
        throw ('Refusing transition from CRC 0x{0:X8}; expected one of: {1}.' -f $state.Crc,$expected)
    }
    [uint32]$sourceCrc=$state.Crc
    $phrase=$FirmwareTargets[$Target].Phrase
    if($Confirmation-cne$phrase){throw "Typed confirmation mismatch. Required exactly: $phrase"}
    if(-not$PSCmdlet.ShouldProcess(('GMK104 CRC 0x{0:X8}' -f $state.Crc),('Flash {0} CRC 0x{1:X8}' -f $Target,$image.Crc))){
        Write-Output 'Flash cancelled before OTA START.';return
    }

    Test-SustainedConnection $state
    $armed=Get-Gmk104State
    if($armed.Crc-ne$sourceCrc-or$armed.ContainerId-ne$state.ContainerId-or$armed.Device.Path-cne$state.Device.Path-or$armed.ViaDevice.Path-cne$state.ViaDevice.Path){
        throw 'Keyboard identity or firmware changed after confirmation. OTA START was not sent.'
    }

    $session=$null;$powerHeld=$false;$transferStarted=$false;$finalResponse=$null;$endError=$null
    try {
        $session=[Gmk104WindowsFirmwareHid+Session]::new($armed.Device.Path,64,64,$true)
        $exclusive=Get-VerifiedVersionFromSession $session
        if($exclusive.Version-ne 0-or$exclusive.Crc-ne$sourceCrc){throw ('Exclusive preflight changed to CRC 0x{0:X8}. OTA START was not sent.' -f $exclusive.Crc)}
        $logPath=Join-Path $PSScriptRoot ('GMK104-Flash-{0}-{1}-{2}.log' -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss'),$Target.ToLowerInvariant(),[Guid]::NewGuid().ToString('N'))
        $encoding=[Text.UTF8Encoding]::new($false)
        $logStream=[IO.FileStream]::new($logPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$logWriter=[IO.StreamWriter]::new($logStream,$encoding)}catch{$logStream.Dispose();throw}
        $logWriter.AutoFlush=$true
        Write-FlashLog $logWriter ('PRECHECK target={0} source=0x{1:X8} target=0x{2:X8}' -f $Target,$exclusive.Crc,$image.Crc)
        Write-FlashLog $logWriter ('IMAGE sha256={0} padded={1} stream={2}' -f $image.Hash,$plan.PaddedHash,$plan.StreamHash)
        [Gmk104WindowsFirmwareHid]::BeginPowerHold();$powerHeld=$true;$deadline=[Diagnostics.Stopwatch]::StartNew()
        Write-Warning 'FLASH STARTING. Keep the USB cable and computer power connected.'
        Write-Output "  Durable flash log: $logPath"

        Write-FlashLog $logWriter 'START SEND';$transferStarted=$true;$script:FlashLogRequired=$false
        $ack=$session.Exchange($plan.Start,5000,$true);Test-OtaIntermediateAck $ack 'OTA START';Write-FlashLog $logWriter 'START ACK'
        for($i=0;$i-lt$plan.DataReports.Count;$i++){
            if($deadline.Elapsed.TotalMinutes-ge$FlashDeadlineMinutes){throw "Overall $FlashDeadlineMinutes-minute flash deadline exceeded."}
            $first=$i*3;$last=[Math]::Min($first+2,$plan.ChunkCount-1)
            Write-FlashLog $logWriter ('DATA SEND report={0}/{1} chunks={2}-{3}' -f ($i+1),$plan.DataReports.Count,$first,$last)
            $ack=$session.Exchange($plan.DataReports[$i],10000,$true);Test-OtaIntermediateAck $ack ("Data report $($i+1)")
            Write-FlashLog $logWriter ('DATA ACK report={0}/{1}' -f ($i+1),$plan.DataReports.Count)
            if((($i+1)%50)-eq 0-or($i+1)-eq$plan.DataReports.Count){
                $pct=[int](100*($i+1)/$plan.DataReports.Count);Write-Progress -Activity "Flashing GMK104 $Target" -Status "$pct%" -PercentComplete $pct
                Write-Output ('  {0}% ({1}/{2} reports acknowledged)' -f $pct,($i+1),$plan.DataReports.Count)
            }
        }
        if($deadline.Elapsed.TotalMinutes-ge$FlashDeadlineMinutes){throw 'Flash deadline exceeded before OTA END.'}
        Write-FlashLog $logWriter 'END SEND'
        try{$finalResponse=$session.Exchange($plan.End,10000,$true);Write-FlashLog $logWriter 'END RESPONSE RECEIVED'}
        catch{$endError=$_.Exception.Message;Write-FlashLog $logWriter "END RESPONSE ERROR: $endError"}
    }
    catch {
        try{Write-FlashLog $logWriter "ERROR: $($_.Exception.Message)"}catch{}
        if($transferStarted){throw ('FLASH INTERRUPTED OR REJECTED: {0} Do not retry automatically.' -f $_.Exception.Message)}
        throw
    }
    finally {
        Write-Progress -Activity "Flashing GMK104 $Target" -Completed
        if($null-ne$session){$session.Dispose()}
        if($powerHeld){[Gmk104WindowsFirmwareHid]::EndPowerHold()}
    }

    if($null-ne$finalResponse){
        if(Test-OtaFinalResponse $finalResponse){Write-Output 'OTA END returned the exact vendor success result.';Write-FlashLog $logWriter 'END EXACT SUCCESS'}
        else{Write-Warning 'OTA END response was not exact; reboot verification is required.';Write-FlashLog $logWriter 'END UNKNOWN; POSTBOOT PROOF REQUIRED'}
    } elseif($endError){Write-Warning "Device disconnected or timed out after OTA END: $endError"}

    Write-Output 'Waiting for reboot and proof of the target CRC and command interface...';Write-FlashLog $logWriter 'POSTBOOT POLL BEGIN'
    $verified=$false;$lastSeen=$null;$lastError=$null
    for($attempt=1;$attempt-le 45;$attempt++){
        Start-Sleep -Seconds 1
        try{
            $after=Get-Gmk104State;$lastSeen=$after.Crc
            if($after.ContainerId-ne$state.ContainerId-or$after.Device.Path-cne$state.Device.Path-or$after.ViaDevice.Path-cne$state.ViaDevice.Path){throw 'Post-reboot keyboard attachment did not match the confirmed USB port.'}
            if($after.Crc-eq$image.Crc){
                if($Target-ne'Stock'){Assert-CustomViaSignature $after.ViaDevice 2}
                if($Target-in@('Wireless','Streaming')){Assert-WirelessSleepSignature $after.ViaDevice}
                $verified=$true;Write-FlashLog $logWriter ("POSTBOOT VERIFIED attempt=$attempt");break
            }
            $lastError=('Saw CRC 0x{0:X8}.' -f $after.Crc)
        } catch{$lastError=$_.Exception.Message;Write-FlashLog $logWriter "POSTBOOT WAIT attempt=$attempt error=$lastError"}
    }
    if(-not$verified){
        $detail=if($null-eq$lastSeen){'keyboard did not return with a readable approved CRC'}else{('keyboard reported CRC 0x{0:X8}' -f $lastSeen)}
        if($lastError){$detail="$detail; last check: $lastError"};Write-FlashLog $logWriter "POSTBOOT INDETERMINATE: $detail"
        throw "POST-FLASH RESULT INDETERMINATE: $detail. Do not retry automatically."
    }
    Write-Output ('FLASH VERIFIED: approved {0} CRC 0x{1:X8} booted and its command interface responded.' -f $Target,$image.Crc)
}
finally {
    if($null-ne$logWriter){try{$logWriter.Dispose()}catch{}}
    if($null-ne$script:FlashLogFault){Write-Warning "Flash logging failed after OTA START and did not interrupt transfer: $($script:FlashLogFault)"}
    if($mutexHeld-and$null-ne$flashMutex){try{$flashMutex.ReleaseMutex()}catch{}}
    if($null-ne$flashMutex){$flashMutex.Dispose()}
}
