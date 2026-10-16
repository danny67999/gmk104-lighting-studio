$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$scriptText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'GMK104-Guarded-Flasher.ps1') -Raw
$native=[regex]::Match($scriptText,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if(-not $native.Success){throw 'Native uploader source was not found'}
$tests=@'
public static class Gmk104TransportTests {
    static int checks;
    static void Check(bool value,string name) { checks++;if(!value)throw new System.Exception("FAILED: "+name); }
    sealed class Mock : Gmk104WindowsFirmwareHid.IFirmwareSession {
        public readonly System.Collections.Generic.List<byte[]> Sent=new System.Collections.Generic.List<byte[]>();
        public int FailAt=-1,ShortAt=-1,FinalAt=-1;public bool BadAck,WrongFinal;public int Timeouts;
        public byte[] Exchange(byte[] report,int timeout,bool flush) {
            int index=Sent.Count;Sent.Add((byte[])report.Clone());Check(timeout==60000&&flush,"same timeout and queue policy");Timeouts++;
            if(index==FailAt)throw new System.IO.IOException("Injected connection loss");
            if(index==ShortAt)return new byte[0];
            var reply=new byte[64];reply[0]=(byte)(BadAck?0:5);reply[1]=2;
            if(index==FinalAt||WrongFinal){reply[2]=3;reply[4]=6;reply[5]=255;}
            return reply;
        }
    }
    static byte[] Packet(int tag) { var p=new byte[64];p[0]=5;p[1]=2;p[4]=(byte)(tag&255);p[5]=(byte)(tag>>8);return p; }
    static void Reject(System.Action action,string name) { bool rejected=false;try{action();}catch(System.IO.IOException){rejected=true;}Check(rejected,name); }
    public static void Run() {
        var start=Packet(65534);var end=Packet(65535);var data=new byte[3633][];for(int i=0;i<data.Length;i++)data[i]=Packet(i);
        var mock=new Mock();mock.FinalAt=3634;
        var success=Gmk104WindowsFirmwareHid.Transfer(mock,start,data,end,null,12);
        Check(success.Acknowledged==3633&&mock.Sent.Count==3635,"full 3633-packet transfer includes exactly one START and END");
        for(int i=0;i<data.Length;i++)Check(System.Linq.Enumerable.SequenceEqual(mock.Sent[i+1],data[i]),"every data packet is unchanged and in order");
        Check(success.FinalResponse[4]==6&&success.EndError==null,"END result retained for mandatory postboot proof");
        foreach(int at in new[]{0,1,20,2559,2560,3494,3495,3633}) {
            var failed=new Mock{FailAt=at};
            Reject(()=>Gmk104WindowsFirmwareHid.Transfer(failed,start,data,end,null,12),"uncertain transfer stops");
            Check(failed.Sent.Count==at+1,"no automatic packet retry or activation after failure");
            Check(!System.Linq.Enumerable.Any(failed.Sent,p=>System.Linq.Enumerable.SequenceEqual(p,end)),"END withheld after missing ACK");
        }
        foreach(int at in new[]{0,1,2560,3495}) {
            var shortRead=new Mock{ShortAt=at};Reject(()=>Gmk104WindowsFirmwareHid.Transfer(shortRead,start,data,end,null,12),"empty ACK rejected");Check(shortRead.Sent.Count==at+1,"empty ACK never advances the stream");
        }
        var bad=new Mock{BadAck=true};Reject(()=>Gmk104WindowsFirmwareHid.Transfer(bad,start,data,end,null,12),"wrong report ID rejected");Check(bad.Sent.Count==1,"bad START sends no data");
        var unexpected=new Mock{WrongFinal=true};Reject(()=>Gmk104WindowsFirmwareHid.Transfer(unexpected,start,data,end,null,12),"final-status frame rejected as intermediate ACK");
        var endLoss=new Mock{FailAt=3634};var uncertain=Gmk104WindowsFirmwareHid.Transfer(endLoss,start,data,end,null,12);Check(uncertain.EndError!=null&&uncertain.Acknowledged==3633&&uncertain.FinalResponse==null,"END disconnect remains indeterminate pending exact reboot checks");
        var pacing=new Gmk104WindowsFirmwareHid.ReportPacer(true);var clock=System.Diagnostics.Stopwatch.StartNew();
        for(int i=0;i<50;i++){pacing.Sent();pacing.Acknowledged();pacing.Wait();}
        Check(clock.Elapsed.TotalMilliseconds>=750,"post-ACK settling never removed");
        System.Console.WriteLine("NATIVE TRANSPORT TESTS PASS: {0} checks; pacing-only sample {1:F2} ms/report, projected {2:F1}s for 3633; no HID device was opened.",checks,clock.Elapsed.TotalMilliseconds/50,clock.Elapsed.TotalSeconds/50*3633);
    }
}

'@
Add-Type -TypeDefinition ($native.Groups[1].Value+[Environment]::NewLine+$tests)
[Gmk104TransportTests]::Run()
