using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Drawing;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

[assembly: AssemblyTitle("GMK104 Guarded Firmware Flasher 1.0.2")]
[assembly: AssemblyProduct("GMK104 Guarded Firmware Flasher 1.0.2")]
[assembly: AssemblyVersion("1.0.2.0")]
[assembly: AssemblyFileVersion("1.0.2.0")]
internal sealed class FirmwareLauncher : Form
{
    private static readonly string[] Targets={"Release","Custom","Wireless","Streaming","Stock"};
    private static readonly string[] Phrases={"INSTALL GMK104 LIGHTING 7F2F4310","FLASH GMK104 CUSTOM C6342859","TEST GMK104 WIRELESS 060C4E9E","TEST GMK104 BLUETOOTH 6F0AD0C1","RESTORE GMK104 STOCK B85531A2"};
    private static readonly string[] Files={"GMK104-Guarded-Flasher.ps1","Run-Flasher.ps1","GMK104-firmware-1.0.bin","GMK104-custom-RGB-v0.2-experimental.bin","GMK104-custom-RGB-v0.3-experimental.bin","GMK104-custom-RGB-v0.4-experimental.bin","GMK104-stock-recovery.bin"};
    private static readonly string[] Hashes={"4bdc3e9729a0583f2daea150fa1ccf4374c5115046f3b8f0655a4758b1dfe22e","96e431887f574cbe01e900ff08a803d8351ede421a982809e294f34b1e7f0fd4","cfb5604e1b861948078c0176801a74ef45727c96225145da82b25fb81b96dd8a","11db2cd854381021b45c0b025d7fabc5277cdbfed185a4e8af0e9327d7acc347","fd6e3e8b9d67e2e4942634fcb5c44275f1b1b4f6975f1691318c5a1d44e1661f"};
    private ComboBox target;private TextBox phrase;private CheckBox ready;private Label expected,status;private Button flash;private FlowLayoutPanel panel;private bool running;
    private static string PowerShell {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");}}
    private static string Hash(byte[] data){using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(data)).Replace("-","").ToLowerInvariant();}
    private static string Extract(string root)
    {
        string path=Path.Combine(root,Guid.NewGuid().ToString("N"));Directory.CreateDirectory(path);
        for(int i=0;i<Files.Length;i++)
        {
            string installed=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Firmware",Files[i]);
            byte[] data=File.ReadAllBytes(installed);
            string expectedHash=i<2 ? FirmwareScriptPins.Hashes[i] : Hashes[i-2];
            if(Hash(data)!=expectedHash)throw new InvalidDataException("Firmware package hash mismatch: "+Files[i]+". Nothing was sent.");
            using(var dest=new FileStream(Path.Combine(path,Files[i]),FileMode.CreateNew,FileAccess.Write,FileShare.Read))dest.Write(data,0,data.Length);
        }
        return path;
    }
    private static ProcessStartInfo StartInfo(string path,string mode,string chosen,string confirmation,bool offline)
    {
        // Only closed-list values enter arguments. No free-form shell command or uploaded script is accepted.
        if(Array.IndexOf(Targets,chosen)<0||Array.IndexOf(new[]{"DryRun","Inspect","TestConnection","Flash"},mode)<0)throw new ArgumentException("Unknown operation");
        if(mode=="Flash"&&confirmation!=Phrases[Array.IndexOf(Targets,chosen)])throw new ArgumentException("Typed confirmation mismatch");
        return new ProcessStartInfo(PowerShell,"-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(path,"Run-Flasher.ps1")+"\" -Mode "+mode+" -Target "+chosen+(mode=="Flash"?" -Confirmation \""+confirmation+"\"":"")+(offline?" -NoPause":""))
        {WorkingDirectory=path,UseShellExecute=!offline,CreateNoWindow=offline,RedirectStandardOutput=offline,RedirectStandardError=offline,WindowStyle=offline?ProcessWindowStyle.Hidden:ProcessWindowStyle.Normal};
    }
    [STAThread] private static int Main(string[] args)
    {
        if(args.Length>0)
        {
            if(args.Length!=2||args[0]!="--self-test")return 2;
            try
            {
                using(var window=new FirmwareLauncher())
                {
                    if(window.Icon==null||!window.Text.Contains("1.0.2"))throw new InvalidOperationException("Installer window failed offline startup validation");
                    if(window.flash.Enabled)throw new InvalidOperationException("Flash must be disabled at startup");
                }
                string session=Extract(Path.GetFullPath(args[1]));
                foreach(string chosen in Targets)using(var p=Process.Start(StartInfo(session,"DryRun",chosen,"",true)))
                {
                    var output=p.StandardOutput.ReadToEndAsync();var error=p.StandardError.ReadToEndAsync();
                    if(!p.WaitForExit(60000))throw new TimeoutException("Offline validation timed out");
                    Task.WaitAll(output,error);
                    string result=output.Result+error.Result;File.WriteAllText(Path.Combine(session,chosen+"-offline.txt"),result);
                    if(p.ExitCode!=0||!result.Contains("OFFLINE DRY RUN COMPLETE"))throw new InvalidOperationException(chosen+" offline validation failed: "+result);
                }
                File.WriteAllText(Path.Combine(session,"PASS.txt"),"All five published firmware images and packet plans passed offline. No HID device was opened.");return 0;
            }catch(Exception e){Directory.CreateDirectory(args[1]);File.WriteAllText(Path.Combine(args[1],"FAIL.txt"),e.ToString());return 1;}
        }
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new FirmwareLauncher());return 0;
    }
    private static Icon LoadWindowIcon()
    {
        // ExtractAssociatedIcon rejects UNC paths such as Parallels \Mac shares.
        // Read the embedded icon without asking the shell to resolve the EXE path.
        try
        {
            using(var stream=typeof(FirmwareLauncher).Assembly.GetManifestResourceStream("Gmk104.FirmwareIcon"))
                if(stream!=null)using(var icon=new Icon(stream))return (Icon)icon.Clone();
        }
        catch { /* A cosmetic icon failure must not prevent startup. */ }
        return (Icon)SystemIcons.Application.Clone();
    }
    private FirmwareLauncher()
    {
        Text="GMK104 • Guarded Firmware Flasher 1.0.2";ClientSize=new Size(800,610);MinimumSize=new Size(800,650);StartPosition=FormStartPosition.CenterScreen;
        Font=new Font("Segoe UI",10);BackColor=Color.FromArgb(19,24,31);ForeColor=Color.FromArgb(235,240,247);Icon=LoadWindowIcon();
        panel=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Padding=new Padding(22)};Controls.Add(panel);
        AddLabel("GMK104  /  FIRMWARE",40,18);
        AddLabel("WIRED USB ONLY • Persistent lighting and guarded rollback",32,11);
        AddLabel("Opening this app does not contact or flash the keyboard. Complete firmware 1.0 includes per-key RGB, sixteen persistent layers, reactive effects, Matrix rain and corrected Aurora. The other choices are the four legacy images already released on GitHub. Switching between Mac and PC does not require reflashing.",56,10);
        target=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Width=710};target.Items.AddRange(new[]{"Complete lighting firmware 1.0 — all effects and persistent layers","GitHub legacy custom v0.2 — host RGB playback","GitHub legacy wireless v0.3","GitHub legacy Bluetooth v0.4","GitHub stock recovery — responding wired USB required"});target.SelectedIndex=0;panel.Controls.Add(target);
        var actions=new FlowLayoutPanel{Width=740,Height=48};actions.Controls.Add(Button("Validate files (offline)","DryRun"));actions.Controls.Add(Button("Inspect USB keyboard","Inspect"));actions.Controls.Add(Button("Test USB connection","TestConnection"));panel.Controls.Add(actions);
        AddLabel("Before flashing: close Lighting Studio and other keyboard utilities. Connect one GMK104 in wired mode. Keep the cable and computer power connected. Never retry an uncertain upload automatically.",74,10);
        ready=new CheckBox{Text="I understand the risk and have a stable wired USB connection.",AutoSize=true,Margin=new Padding(3,8,3,8)};panel.Controls.Add(ready);
        expected=AddLabel("",32,10);phrase=new TextBox{Width=710};panel.Controls.Add(phrase);flash=Button("Flash selected firmware…","Flash");flash.BackColor=Color.FromArgb(248,179,71);flash.ForeColor=Color.Black;panel.Controls.Add(flash);
        status=AddLabel("Ready. Start with offline validation; no device operation has run.",70,10);
        target.SelectedIndexChanged+=delegate{phrase.Clear();ready.Checked=false;UpdateGate();};phrase.TextChanged+=delegate{UpdateGate();};ready.CheckedChanged+=delegate{UpdateGate();};UpdateGate();
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(running){e.Cancel=true;MessageBox.Show(this,"Finish the operation and close its results window before exiting. Do not disconnect a keyboard during flashing.");}};
    }
    private Label AddLabel(string text,int height,int size){var l=new Label{Text=text,Width=730,Height=height,Font=new Font("Segoe UI",size),Margin=new Padding(3,4,3,4)};panel.Controls.Add(l);return l;}
    private Button Button(string text,string mode){var b=new Button{Text=text,AutoSize=true,Height=34,BackColor=Color.FromArgb(42,54,68),ForeColor=ForeColor,FlatStyle=FlatStyle.Flat,Margin=new Padding(3,7,8,7)};b.Click+=async delegate{await Run(mode);};return b;}
    private void UpdateGate(){expected.Text="Type exactly: "+Phrases[target.SelectedIndex];flash.Enabled=!running&&ready.Checked&&phrase.Text==Phrases[target.SelectedIndex];}
    private async Task Run(string mode)
    {
        if(running)return;string chosen=Targets[target.SelectedIndex],confirmation=phrase.Text;
        if(mode=="Flash")
        {
            if(!ready.Checked||confirmation!=Phrases[target.SelectedIndex])return;
            if(MessageBox.Show(this,"Flash "+chosen+" firmware over wired USB? An interrupted or incompatible update can disable the keyboard. Permanent storage uses a reverse-engineered layout; failed boot may require hardware recovery. The guarded flasher will also request confirmation in its console.","Confirm firmware operation",MessageBoxButtons.YesNo,MessageBoxIcon.Warning,MessageBoxDefaultButton.Button2)!=DialogResult.Yes)return;
        }
        running=true;panel.Enabled=false;status.Text="Operation running. Read the separate results window; keep USB connected during flashing.";
        try
        {
            string path=Extract(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"GMK104FirmwareLauncher","sessions"));
            using(var process=Process.Start(StartInfo(path,mode,chosen,confirmation,false)))
            {
                await Task.Run(()=>process.WaitForExit());status.Text=process.ExitCode==0?"Operation finished. Logs and session files: "+path:"Operation stopped or failed. Read the results; do not retry an uncertain flash. Session: "+path;
            }
        }catch(Exception e){status.Text="Could not complete operation: "+e.Message;}
        finally{running=false;panel.Enabled=true;phrase.Clear();ready.Checked=false;UpdateGate();}
    }
}
