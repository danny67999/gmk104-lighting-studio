using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;

namespace Gmk104LightingStudio
{
    public static class OnboardTests
    {
        static int checks;
        static void Check(bool value, string message) { checks++; if (!value) throw new Exception(message); }
        static void Reject(Action body, string message) { bool rejected = false; try { body(); } catch { rejected = true; } Check(rejected, message); }
        public static int Main()
        {
            try
            {
                string folder = AppDomain.CurrentDomain.BaseDirectory;
                var keys = new JavaScriptSerializer().Deserialize<KeyGeometry[]>(File.ReadAllText(Path.Combine(folder, "layout.json")));
                var map = MappingFile.Load(Path.Combine(folder, "default-led-map.json")); var layers = new List<LightingLayer>();
                for (int i = 0; i < 9; i++)
                {
                    string effect = OnboardProfile.EffectIds[i]; var settings = new LightingSettings { effect = effect, color = new RGB((byte)(i * 20), 72, 183), speed = .25 + i * .2, intensity = .8, brightness = 3, musicSensitivity = 1.75 };
                    layers.Add(new LightingLayer(settings) { id = String.Format("00000000-0000-4000-8000-{0:X12}", i + 1), name = "Layer " + i + " · " + LightingEngine.DisplayName(effect), opacity = (i + 1) / 10.0, blendMode = i % 2 == 0 ? "additive" : "normal", affectAllKeys = i % 3 == 0, keyIDs = i % 2 == 0 ? new List<string> { "KeyW", "KeyA", "KeyS", "KeyD" } : null });
                }
                for (int i = layers.Count; i < 16; i++) { var extra = layers[0].Clone(); extra.id = String.Format("00000000-0000-4000-8000-{0:X12}", i + 1); extra.name = "Extra " + layers.Count; layers.Add(extra); }
                var profile = new LightingProfile { settings = layers[0].settings.Clone(), layers = layers, frameRate = 120 };
                var encoded = OnboardProfile.Compile(profile, keys, map, map);
                Check(encoded.Bytes.SequenceEqual(File.ReadAllBytes(Path.Combine(folder, "onboard-profile-all-effects-v1.bin"))), "Windows and Mac must compile identical profile bytes, including UUID order and rounding.");
                for (int i = 0; i < OnboardProfile.EffectIds.Length; i++) { var p = profile.Clone(); p.layers = new List<LightingLayer> { layers[0].Clone() }; p.layers[0].settings.effect = OnboardProfile.EffectIds[i]; Check(OnboardProfile.Compile(p, keys, map, map).Bytes[344] == i, "All effect IDs retain firmware order."); }
                var reactiveLayers = new List<LightingLayer>();
                for (int i = 18; i < 24; i++) {
                    var layer = layers[0].Clone(); layer.id = String.Format("00000000-0000-4000-8000-{0:X12}", i - 17);
                    layer.name = "Reactive " + (i - 18); layer.settings.effect = OnboardProfile.EffectIds[i]; reactiveLayers.Add(layer);
                }
                var reactiveProfile = new LightingProfile { settings = layers[0].settings.Clone(), layers = reactiveLayers, frameRate = 60 };
                Check(OnboardProfile.Compile(reactiveProfile, keys, map, map).Bytes.SequenceEqual(File.ReadAllBytes(Path.Combine(folder, "onboard-profile-reactive-v1.2.bin"))), "New reactive effects compile identically on Windows and Mac.");
                foreach (string effect in OnboardProfile.EffectIds.Skip(19).Take(5)) {
                    var settings = new LightingSettings { effect = effect };
                    var press = new List<KeyPulse> { new KeyPulse("KeyW", 0) };
                    Check(LightingEngine.RenderEffect(settings, keys, map, new List<KeyPulse>(), .2).All(c => c.Equals(RGB.Black)), "Reactive effect stays transparent when idle.");
                    var first = LightingEngine.RenderEffect(settings, keys, map, press, .2);
                    Check(first.Any(c => !c.Equals(RGB.Black)), "Reactive effect responds to a press.");
                    settings.speed = 2;
                    Check(first.SequenceEqual(LightingEngine.RenderEffect(settings, keys, map, press, .1)), "Reactive speed scales pulse age.");
                }
                var matrixLayer = layers[0].Clone(); matrixLayer.name="Matrix rain";matrixLayer.keyIDs=null;matrixLayer.affectAllKeys=false;matrixLayer.opacity=1;matrixLayer.blendMode="normal";
                matrixLayer.settings=new LightingSettings{effect="matrixRain",color=new RGB(0,255,32)};
                var matrixProfile=new LightingProfile{settings=matrixLayer.settings.Clone(),layers=new List<LightingLayer>{matrixLayer},frameRate=60};
                var matrixBinary=OnboardProfile.Compile(matrixProfile,keys,map,map);
                Check(matrixBinary.Bytes.SequenceEqual(File.ReadAllBytes(Path.Combine(folder,"onboard-profile-matrix-v1.3.bin"))),"Matrix profile matches Mac and native format.");
                byte[] matrixCaps=File.ReadAllBytes(Path.Combine(folder,"onboard-capabilities-v1.3.bin"));
                Check(matrixCaps[20]==24 && matrixCaps[9]==7,"Production v1.3 advertises Matrix support and permanent save.");
                byte[] matrixFrames=File.ReadAllBytes(Path.Combine(folder,"matrix-native-frames-v1.6.bin"));
                for(int tick=0;tick<60;tick++){var frame=LightingEngine.RenderEffect(matrixLayer.settings,keys,map,new List<KeyPulse>(),tick/10.0);Check(frame.SelectMany(c=>new[]{c.r,c.g,c.b}).SequenceEqual(matrixFrames.Skip(tick*312).Take(312)),"Windows Matrix preview matches production native frame.");}
                var initial=LightingEngine.RenderEffect(matrixLayer.settings,keys,map,new List<KeyPulse>(),0);
                foreach(var key in keys){int led=map.mappings.First(x=>x.keyId==key.id).ledIndex.Value;if(!initial[led].Equals(RGB.Black))Check(key.y==0,"Entering heads cannot start below the top row.");}
                int staggered=0,steps=0,wraps=0,lastHead=-1,tails=0;bool entered=false;
                for(int tick=0;tick<1600;tick++){
                    var column=Enumerable.Range(0,6).Select(row=>MatrixRainRaster.Pixel(8,1+row*2,1,11,tick/100.0,matrixLayer.settings)).ToArray();
                    int lit=column.Count(c=>!c.Equals(RGB.Black)),head=Enumerable.Range(0,6).OrderByDescending(row=>column[row].g).First();
                    if(lit>0){if(!entered){Check(head==0&&lit==1,"Stream enters at top without invented tails below it.");entered=true;}if(lastHead>=0&&lastHead!=head){if(head==0){Check(lastHead==5,"Head wraps from the bottom to the top.");wraps++;}else{Check(head==lastHead+1,"White head advances down one row.");steps++;}}lastHead=head;}
                    if(tick>=500){Check(lit>=4&&lit<=5,"Loop has a long tail and a dark space.");int transitions=Enumerable.Range(0,6).Count(row=>column[row].Equals(RGB.Black)!=column[(row+1)%6].Equals(RGB.Black));Check(transitions==2,"Tail is continuous rather than alternating stripes.");for(int age=1;age<4;age++)Check(column[(head+6-age+1)%6].g>=column[(head+6-age)%6].g,"Green tail fades away from the white head.");tails++;}
                    for(int row=1;row<5;row++){var neighbor=MatrixRainRaster.Pixel(10,1+row*2,1,11,tick/100.0,matrixLayer.settings);if(column[row].Equals(RGB.Black)!=neighbor.Equals(RGB.Black))staggered++;}
                }
                Check(entered&&steps>30&&wraps>=6&&tails==1100&&staggered>100,"Video-style vertical loop retains staggered gaps and repeated wraps.");
                using(var fake=new ProfileTransport{MaximumEffectId=23}){Reject(()=>new OnboardUploader(fake).Transfer(matrixBinary,true),"v1.2 refuses Matrix before writes.");Check(fake.Writes==0,"Incompatible firmware receives no Matrix bytes.");}
                foreach(bool save in new[]{false,true})using(var fake=new ProfileTransport{MaximumEffectId=24}){new OnboardUploader(fake).Transfer(matrixBinary,save);Check(fake.Stored.SequenceEqual(matrixBinary.Bytes),"v1.3 Matrix send/save verifies complete profile.");}
                Check(LogicalMatrixRaster.Assignments.Keys.OrderBy(x=>x).SequenceEqual(keys.Select(x=>x.id).OrderBy(x=>x)),"All 104 keys have a logical column.");
                foreach(string id in new[]{"Escape","Backquote","Digit1","Tab","CapsLock","ShiftLeft","ControlLeft"})Check((LogicalMatrixRaster.Assignments[id]&31)==0,"Column 1 follows the explicit key group.");
                foreach(string id in new[]{"F1","Digit2","KeyQ","KeyA","KeyZ","AltLeft"})Check((LogicalMatrixRaster.Assignments[id]&31)==1,"Column 2 follows the explicit key group.");
                foreach(string effect in new[]{"spacedMatrixRain","matrixKeyRain"}){
                    bool reactive=effect=="matrixKeyRain";string label=reactive?"key":"spaced";
                    var settings=new LightingSettings{effect=effect,color=new RGB(0,255,32)};
                    var presses=reactive?new List<KeyPulse>{new KeyPulse("KeyA",0)}:new List<KeyPulse>();
                    byte[] expected=File.ReadAllBytes(Path.Combine(folder,label+"-matrix-native-v1.7.bin"));var reached=new HashSet<string>();
                    for(int tick=0;tick<60;tick++){
                        var frame=LightingEngine.RenderEffect(settings,keys,map,presses,tick/10.0);
                        Check(frame.SelectMany(c=>new[]{c.r,c.g,c.b}).SequenceEqual(expected.Skip(tick*312).Take(312)),"New Matrix Windows/native frame parity.");
                        foreach(var key in keys){int led=map.mappings.First(x=>x.keyId==key.id).ledIndex.Value;if(!frame[led].Equals(RGB.Black)){reached.Add(key.id);int packed=LogicalMatrixRaster.Assignments[key.id];Check(reactive?(packed&31)==1:(packed&1)==0,"Only assigned logical columns light.");if(tick==0)Check((packed>>5)==0,"Trail starts on the top row.");}}
                    }
                    Check(reached.SetEquals(keys.Where(k=>reactive?(LogicalMatrixRaster.Assignments[k.id]&31)==1:(LogicalMatrixRaster.Assignments[k.id]&1)==0).Select(k=>k.id)),"Every eligible assigned key is reached.");
                    var fast=settings.Clone();fast.speed=2;Check(LightingEngine.RenderEffect(settings,keys,map,presses,.8).SequenceEqual(LightingEngine.RenderEffect(fast,keys,map,presses,.4)),"Both new effects scale speed.");
                    var layer=new LightingLayer(settings){keyIDs=new List<string>{"KeyA"},affectAllKeys=true};var selected=new List<LightingLayer>{layer};
                    if(reactive){Check(LightingEngine.Render(selected,keys,map,presses,.2).Any(c=>!c.Equals(RGB.Black)),"Press starts a full logical-column trail.");Check(LightingEngine.Render(selected,keys,map,new List<KeyPulse>{new KeyPulse("KeyW",0)},.2).All(c=>c.Equals(RGB.Black)),"Unselected keys cannot trigger the rain.");Check(LightingEngine.RenderEffect(settings,keys,map,presses,6).All(c=>c.Equals(RGB.Black)),"Reactive rain clears after falling.");}
                    layer.affectAllKeys=false;var restricted=LightingEngine.Render(selected,keys,map,presses,1);int a=map.mappings.First(x=>x.keyId=="KeyA").ledIndex.Value;Check(restricted.Select((color,index)=>index==a||color.Equals(RGB.Black)).All(x=>x),"Output selection remains independent.");
                    var columnProfile=new OnboardProfile(File.ReadAllBytes(Path.Combine(folder,"onboard-profile-"+label+"-matrix-v1.7.bin")));
                    foreach(bool save in new[]{false,true})using(var fake=new ProfileTransport{MaximumEffectId=26}){new OnboardUploader(fake).Transfer(columnProfile,save);Check(fake.Stored.SequenceEqual(columnProfile.Bytes),"New effect send/save verifies complete bytes.");}
                    using(var fake=new ProfileTransport{MaximumEffectId=24}){Reject(()=>new OnboardUploader(fake).Transfer(columnProfile,true),"Old firmware refuses new column effects.");Check(fake.Writes==0,"Unsupported effects stop before every write.");}
                }
                var toggled = new HashSet<string> { "KeyW" };
                Check(LightingEngine.RenderEffect(new LightingSettings { effect = "keyToggle" }, keys, map, new List<KeyPulse>(), 999, false, null, null, toggled).Any(c => !c.Equals(RGB.Black)), "Toggle remains lit without holding or pulses.");
                profile.layers = new List<LightingLayer> { layers[0].Clone() }; profile.layers[0].settings.effect = "keyHold";
                var binary = OnboardProfile.Compile(profile, keys, map, map);
                var remapped = map.Clone(); var w = remapped.mappings.First(x => x.keyId == "KeyW"); var s = remapped.mappings.First(x => x.keyId == "KeyS"); int wi = w.ledIndex.Value, si = s.ledIndex.Value; remapped.Assign("KeyW", si); remapped.Assign("KeyS", wi);
                Check(OnboardProfile.Compile(profile, keys, remapped, map).Bytes[32 + wi] == si, "Factory triggers remain independent of custom LED output.");
                var held = new HashSet<string> { "KeyW" };
                Check(LightingEngine.Render(profile.layers, keys, map, new List<KeyPulse>(), 1, null, held).Any(x => !x.Equals(RGB.Black)), "Held key lights while pressed.");
                Check(LightingEngine.Render(profile.layers, keys, map, new List<KeyPulse>(), 1, null, new HashSet<string>()).All(x => x.Equals(RGB.Black)), "Released key immediately clears.");
                foreach (string effect in OnboardProfile.EffectIds.Skip(9).Take(9)) { var settings = new LightingSettings { effect = effect }; var frame = LightingEngine.RenderEffect(settings, keys, map, new List<KeyPulse>(), 1.23); Check(frame.Length == 104, "Extended effect creates a complete frame."); if (effect != "keyHold") Check(Enumerable.Range(0, 12).Any(i => LightingEngine.RenderEffect(settings, keys, map, new List<KeyPulse>(), i * .37).Any(c => !c.Equals(RGB.Black))), "Extended effect produces visible output."); }
                profile.layers[0].keyIDs = new List<string>(); profile.layers[0].affectAllKeys = true; var empty = OnboardProfile.Compile(profile, keys, map, map); Check(empty.Bytes.Skip(358).Take(26).All(x => x == 0), "Empty selection stays inactive with all-key output.");
                profile.layers[0].name = String.Concat(Enumerable.Repeat("🎨", 21)); Reject(() => OnboardProfile.Compile(profile, keys, map, map), "UTF-8 layer name limit enforced.");
                var bad = binary.Bytes; bad[400] ^= 1; Reject(() => new OnboardProfile(bad), "Corrupt encoded data rejected.");
                var partial = map.Clone(); partial.mappings[0].confirmed = false; Reject(() => OnboardProfile.Compile(new LightingProfile(), keys, partial, map), "Unconfirmed mapping rejected.");
                foreach (bool save in new[] { false, true }) using (var fake = new ProfileTransport())
                {
                    var receipt = new OnboardUploader(fake, 0x12345678).Transfer(binary, save); Check(receipt.Persistent == save && fake.CommitCount == (save ? 1 : 0) && fake.ActivateCount == (save ? 0 : 1), "Persistent and volatile operations are separate and sent once."); Check(fake.Stored.SequenceEqual(binary.Bytes), "Complete upload readback matches."); Check(fake.Effect == 20, "Firmware renderer mode selected."); Check(new OnboardUploader(fake).ReadActive().SequenceEqual(binary.Bytes), "Read-only active profile verified.");
                }
                byte[] actualCaps = File.ReadAllBytes(Path.Combine(folder, "onboard-capabilities-v1.2.bin"));
                Check(actualCaps.Length == 32 && actualCaps[20] == 23 && actualCaps[9] == 7, "Production v1.2 runtime advertises all reactive effects.");
                foreach (byte limit in new byte[] { 0, 9, 17, 18, 23, 24, 26 }) using (var fake = new ProfileTransport { MaximumEffectId = limit }) {
                    var caps = new OnboardUploader(fake).SupportedModes();
                    Check(caps.Volatile && caps.Persistent && caps.MaximumEffectId == (limit == 0 ? 8 : limit), "Known legacy and v1.2 capability replies enable support.");
                    Check(fake.Writes == 0, "Checking capabilities is read-only.");
                }
                var reactiveBinary = OnboardProfile.Compile(reactiveProfile, keys, map, map);
                foreach (bool save in new[] { false, true }) using (var fake = new ProfileTransport { MaximumEffectId = 23 }) {
                    var receipt = new OnboardUploader(fake, 36).Transfer(reactiveBinary, save);
                    Check(receipt.Persistent == save && fake.Stored.SequenceEqual(reactiveBinary.Bytes), "All six reactive effects transfer and verify against v1.2.");
                }
                using (var fake = new ProfileTransport { MaximumEffectId = 17 }) {
                    Reject(() => new OnboardUploader(fake).Transfer(reactiveBinary, true), "Older firmware still blocks new reactive effects.");
                    Check(fake.Writes == 0, "Incompatible effects stop before any write.");
                }
                foreach (byte limit in new byte[] { 8, 25, 255 }) using (var fake = new ProfileTransport { MaximumEffectId = limit }) {
                    Check(!new OnboardUploader(fake).SupportedModes().Volatile, "Unknown effect limit remains unsupported.");
                    Reject(() => new OnboardUploader(fake).Transfer(reactiveBinary, true), "Unknown limit refuses upload.");
                    Check(fake.Writes == 0, "Unknown capabilities cannot start a transfer.");
                }
                using (var fake = new ProfileTransport { MaximumEffectId = 23, ReservedCapabilityByte = 1 }) {
                    Check(!new OnboardUploader(fake).SupportedModes().Persistent, "Malformed v1.2 reserved bytes remain rejected.");
                    Reject(() => new OnboardUploader(fake).Transfer(reactiveBinary, true), "Malformed reply refuses upload.");
                    Check(fake.Writes == 0, "Malformed reply cannot start a transfer.");
                }
                using (var fake = new ProfileTransport { DropCommit = true }) { Reject(() => new OnboardUploader(fake, 1).Transfer(binary, true), "Lost commit reply stops operation."); Check(fake.CommitCount == 1, "Lost commit never retries."); }
                using (var fake = new ProfileTransport { CorruptReadback = true }) Reject(() => new OnboardUploader(fake, 1).Transfer(binary, true), "Altered readback rejected.");
                using (var fake = new ProfileTransport { WrongSession = true }) { Reject(() => new OnboardUploader(fake, 1).Transfer(binary, true), "Wrong session rejected before commit."); Check(fake.CommitCount == 0, "Invalid acknowledgment preserves previous profile."); }
                using (var fake = new ProfileTransport { Connection = "2.4 GHz" }) { Reject(() => new OnboardUploader(fake, 1).Transfer(binary, true), "Receiver profile writes refused."); Check(fake.Writes == 0, "Unsupported transport sends nothing."); }
                using (var fake = new ProfileTransport { Flags = 5 }) { Reject(() => new OnboardUploader(fake, 1).Transfer(binary, true), "RAM-only firmware cannot persist."); Check(fake.Writes == 0, "Missing persistent capability sends no write."); }
                Reject(() => LightingPackets.ValidateAndSplit(new byte[] { 7,3,7,4,1,0,0,0 }, true), "Bluetooth profile commands rejected.");
                Reject(() => LightingPackets.ValidateAndSplit(new byte[] { 7,3,7,2,1,0,0,0,0,0,22 }, false), "Malformed chunk rejected.");
                Console.WriteLine("ONBOARD PROFILE / UPLOAD TESTS PASS (" + checks + " assertions)"); return 0;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
        sealed class ProfileTransport : IReportTransport
        {
            public string Connection = "USB"; public string ConnectionName { get { return Connection; } } public bool UsesRollingAnimationVerification { get { return false; } } public string DeviceIdentity { get { return "offline-profile-fixture"; } }
            public byte Flags = 7, MaximumEffectId = 17, ReservedCapabilityByte = 0; public int Effect = 1, CommitCount, ActivateCount, Writes; public bool DropCommit, CorruptReadback, WrongSession; public byte[] Stored = new byte[0]; private byte[] staged; private uint session, digest; private int offset;
            public void CheckSingleDevice() { } public void Dispose() { } public void WriteFrame(RGB[] frame) { throw new Exception("No frame streaming allowed in onboard uploader."); }
            public byte[] Exchange(byte[] p)
            {
                LightingPackets.ValidateAndSplit(p, false); byte[] r = new byte[32];
                if (p[2] == 5) { new byte[] {8,3,5,2,104,9,15,71,77,75,2}.CopyTo(r,0); r[11] = p[3]; r[15]=(byte)Effect; r[16]=3; return r; }
                if (p[2] == 2) { Effect=p[3]; return r; }
                new byte[] {p[0],3,7,p[3],71,77,75,85,1,0}.CopyTo(r,0);
                int op=p[3];
                if(p[0]==8 && op==0) { r[9]=Flags; OnboardProfile.LE16(2536).CopyTo(r,10);r[12]=21;OnboardProfile.LE16(Stored.Length).CopyTo(r,14);OnboardProfile.LE32(Stored.Length==0?0:OnboardProfile.CRC32(Stored)).CopyTo(r,16);r[20]=MaximumEffectId;r[21]=ReservedCapabilityByte;return r; }
                if(p[0]==8 && op==5) { int start=OnboardProfile.U16(p,4),count=p[6];OnboardProfile.LE16(start).CopyTo(r,10);r[12]=(byte)count;Array.Copy(Stored,start,r,13,count);if(CorruptReadback)r[13]^=1;return r; }
                Writes++;
                if(op==1) { session=OnboardProfile.U32(p,4);digest=OnboardProfile.U32(p,10);staged=new byte[OnboardProfile.U16(p,8)];offset=0; }
                if(op==2) { int start=OnboardProfile.U16(p,8),count=p[10];if(start!=offset)throw new Exception("Wrong chunk offset");Array.Copy(p,11,staged,start,count);offset+=count; }
                if(op==3) Check(OnboardProfile.CRC32(staged)==digest,"Device staging digest verified.");
                if(op==4 || op==7) { if(op==4)CommitCount++;else ActivateCount++;Stored=(byte[])staged.Clone();if(op==4 && DropCommit)throw new IOException("Lost commit response"); }
                OnboardProfile.LE32(WrongSession?session+1:session).CopyTo(r,10);OnboardProfile.LE16(offset).CopyTo(r,14);OnboardProfile.LE32(digest).CopyTo(r,16);return r;
            }
        }
    }
}
