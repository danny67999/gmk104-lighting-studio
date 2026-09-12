using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace Gmk104LightingStudio
{
    // Run in a fresh directory containing this executable and the two bundled
    // JSON resources. Preview mode isolates persistence and cannot connect.
    public static class StudioTests
    {
        private const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
        private static int checks;
        private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
        private static void Check(bool condition, string message) { checks++; if (!condition) throw new Exception("FAILED: " + message); }
        private static T Get<T>(object target, string field) { return (T)target.GetType().GetField(field, Private).GetValue(target); }
        private static void Set(object target, string field, object value) { target.GetType().GetField(field, Private).SetValue(target, value); }
        private static object Call(object target, string name, params object[] args)
        {
            try { return target.GetType().GetMethod(name, Private | BindingFlags.DeclaredOnly).Invoke(target, args); }
            catch (TargetInvocationException error) { throw error.InnerException ?? error; }
        }
        private static StudioForm NewForm()
        {
            var form = new StudioForm(true);
            foreach (string field in new[] { "animation", "reconnect", "sensors" }) Get<Timer>(form, field).Stop();
            return form;
        }
        private static void DisposeForm(StudioForm form)
        {
            if (form == null) return;
            Set(form, "playing", false);
            Call(form, "OnClosing", form, new FormClosingEventArgs(CloseReason.ApplicationExitCall, false));
            form.Dispose();
        }
        [STAThread]
        public static int Main(string[] args)
        {
            StudioForm form = null;
            bool ownsState = false;
            string directory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "preview-state");
            string profilePath = Path.Combine(directory, "lighting-profile.json"), mapPath = Path.Combine(directory, "led-map.json");
            try
            {
                if (Directory.Exists(directory)) throw new Exception("Use a fresh test fixture: preview-state already exists. No existing state was touched.");
                ownsState = true;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                form = NewForm();
                var keys = Get<KeyGeometry[]>(form, "keys"); var map = Get<MappingFile>(form, "map"); map.Validate(keys);
                Check(keys.Length == 104 && map.mappings.Count(x => x.confirmed) == 104, "validated full Mac keyboard layout and map");
                Check(Get<string>(form, "dataPath") == directory, "preview state is isolated beside test executable");
                Check(!File.Exists(profilePath), "construction does not overwrite saved lighting");
                var draft = Get<LightingProfile>(form, "profile"); var saved = Get<LightingProfile>(form, "savedProfile");
                Check(draft.layers.Count == 1 && draft.layers[0].settings.effect == "rainbowRipple" && draft.layers[0].affectAllKeys && !draft.resume, "default whole-board rainbow ripple is initially stopped");
                Check(!Object.ReferenceEquals(draft, saved) && !Object.ReferenceEquals(draft.layers[0], saved.layers[0]), "draft and saved layers have separate ownership");
                Call(form, "Connect");
                typeof(Form).GetMethod("OnShown", Private).Invoke(form, new object[] { EventArgs.Empty });
                Check(Get<RGBClient>(form, "client") == null && !Get<bool>(form, "busy") && !Get<bool>(form, "retryWanted"), "explicit connect and Shown remain offline in preview");

                string savedName = saved.layers[0].name;
                Get<TextBox>(form, "layerName").Text = "Unsaved edit";
                Get<NumericUpDown>(form, "speed").Value = 2.5m;
                Check(draft.layers[0].name == "Unsaved edit" && draft.layers[0].settings.speed == 2.5, "editor changes update only draft");
                Call(form, "StopPlayback");
                var disk = LightingProfile.Load(profilePath);
                Check(disk.layers[0].name == savedName && disk.layers[0].settings.speed == 1 && !disk.resume, "Stop preserves saved effect while persisting resume off");
                Get<TextBox>(form, "layerName").Text = "";
                Get<CheckBox>(form, "restoreBox").Checked = false;
                disk = LightingProfile.Load(profilePath);
                Check(!disk.restoreOnReconnect && disk.layers[0].name == savedName, "restore preference saves despite invalid unfinished draft; restore=" + disk.restoreOnReconnect + ", name=" + disk.layers[0].name + ", loading=" + Get<bool>(form, "loading") + ", status=" + Get<Label>(form, "statusLabel").Text);
                Check(draft.layers[0].name == "", "preference change does not discard unfinished editor text");
                Get<TextBox>(form, "layerName").Text = "Draft rainbow";
                Call(form, "SaveProfile", true);
                Check(LightingProfile.Load(profilePath).layers[0].name == "Draft rainbow", "explicit draft commit persists editor content");
                draft.layers[0].settings.color = new RGB(4, 5, 6);
                Check(Get<LightingProfile>(form, "savedProfile").layers[0].settings.color != draft.layers[0].settings.color, "committing still isolates future draft color changes");

                Call(form, "SetSelection", new List<string>());
                Set(form, "selecting", true); Call(form, "UpdateSelection"); Call(form, "ClickKey", "KeyA");
                Check(draft.layers[0].keyIDs.SequenceEqual(new[] { "KeyA" }) && Get<KeyboardView>(form, "keyboard").Selection.SetEquals(new[] { "KeyA" }), "onscreen selection changes draft trigger mask");
                Call(form, "ClickKey", "KeyA"); Check(draft.layers[0].keyIDs.Count == 0, "selecting same key toggles off");
                var tabs = Get<TabControl>(form, "tabs"); IntPtr tabHandle = tabs.Handle; tabs.SelectedIndex = 2;
                Check(!Get<bool>(form, "selecting") && Get<KeyboardView>(form, "keyboard").ShowIndices && Get<KeyboardView>(form, "keyboard").Selection == null, "mapping tab exits layer selection");
                tabs.SelectedIndex = 0;
                Check(!Get<KeyboardView>(form, "keyboard").ShowIndices && Get<Button>(form, "chooseButton").Text == "Choose keys", "returning from mapping resets selection button");
                Check(Get<RGBClient>(form, "client") == null, "tab switching does not acquire a keyboard");

                Call(form, "SetSelection", new List<string> { "KeyW", "KeyA", "KeyS", "KeyD" });
                Set(form, "applied", draft.Clone()); Set(form, "playing", true);
                var pulses = Get<List<KeyPulse>>(form, "pulses"); pulses.Clear(); Call(form, "PreviewPulse");
                Check(pulses.Count == 1 && draft.layers[0].keyIDs.Contains(pulses[0].keyID), "test pulse respects WASD trigger mask");
                Get<LightingProfile>(form, "applied").layers[0].keyIDs.Clear(); pulses.Clear(); Call(form, "PreviewPulse");
                Check(pulses.Count == 0, "test pulse does not invent an empty trigger");
                for (int i = 0; i < 100; i++) Call(form, "Pressed", "KeyA");
                Check(pulses.Count == 48, "keyboard events retain newest 48 pulses");
                Set(form, "playing", false);

                Call(form, "AddLayer"); Check(draft.layers.Count == 2 && Get<ListBox>(form, "layersBox").SelectedIndex == 0 && draft.layers[0].settings.effect == "staticColor", "adding selects new top layer");
                Call(form, "DuplicateLayer"); Check(draft.layers.Count == 3 && draft.layers[0].id != draft.layers[1].id && !Object.ReferenceEquals(draft.layers[0].settings, draft.layers[1].settings), "copy layer has independent settings and identity");
                string moved = draft.layers[0].id; Call(form, "MoveLayer", 1); Check(draft.layers[1].id == moved && Get<ListBox>(form, "layersBox").SelectedIndex == 1, "reordering keeps selected layer");
                Call(form, "RemoveLayer"); Check(draft.layers.Count == 2, "remove retains valid stack");

                string mapBefore = Json.Serialize(Get<MappingFile>(form, "map"));
                var candidate = Get<MappingFile>(form, "map").Clone(); candidate.Assign("KeyA", 0);
                Directory.CreateDirectory(mapPath);
                bool result = (bool)Call(form, "SaveMap", candidate);
                Check(!result && Json.Serialize(Get<MappingFile>(form, "map")) == mapBefore, "failed mapping write preserves live map");
                Set(form, "illuminated", 1); Set(form, "selectedMappingKey", "KeyA"); Get<NumericUpDown>(form, "ledIndex").Value = 1; Get<CheckBox>(form, "quickMapping").Checked = true;
                Call(form, "SaveMappingCorrection");
                Check(Get<NumericUpDown>(form, "ledIndex").Value == 1 && Get<int>(form, "illuminated") == 1 && Json.Serialize(Get<MappingFile>(form, "map")) == mapBefore, "failed quick mapping does not advance or modify map");
                Check(!Get<Label>(form, "statusLabel").Text.StartsWith("Saved "), "failed quick mapping preserves error message");
                Directory.Delete(mapPath); Set(form, "illuminated", -1); Get<CheckBox>(form, "quickMapping").Checked = false;
                Check((bool)Call(form, "SaveMap", candidate), "valid map persists");
                Check(MappingFile.Load(mapPath).mappings.Single(x => x.keyId == "KeyA").ledIndex == 0, "persisted map contains correction");
                Check((bool)Call(form, "SaveMap", Get<MappingFile>(form, "undoMap")), "undo map persists");
                Check(Json.Serialize(Get<MappingFile>(form, "map")) == mapBefore, "undo restores exact previous assignments");
                DisposeForm(form); form = null;

                var badMap = MappingFile.Load(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "default-led-map.json")); badMap.mappings[0].keyId = "NotAKeyboardKey";
                File.WriteAllText(mapPath, Json.Serialize(badMap)); File.Delete(profilePath); string badBytes = File.ReadAllText(mapPath);
                form = NewForm(); Get<MappingFile>(form, "map").Validate(Get<KeyGeometry[]>(form, "keys"));
                Check(Get<MappingFile>(form, "map").mappings.Any(x => x.keyId == "Escape") && Get<Label>(form, "statusLabel").Text.Contains("Saved map could not be loaded"), "invalid saved map falls back without poisoning bundled map");
                Check(File.ReadAllText(mapPath) == badBytes, "loading invalid map does not overwrite source");
                DisposeForm(form); form = null; File.Delete(mapPath);

                File.WriteAllText(profilePath, "{\"version\":"); form = NewForm();
                Check(Get<LightingProfile>(form, "profile").layers[0].settings.effect == "rainbowRipple" && Get<Label>(form, "statusLabel").Text.Contains("Saved profile could not be loaded"), "invalid profile falls back with a readable notice");
                Check(File.ReadAllText(profilePath) == "{\"version\":", "invalid profile source remains recoverable");
                DisposeForm(form); form = null;
                var legacy = new LightingProfile { version = 1, settings = new LightingSettings { effect = "reactive", color = new RGB(30, 160, 240) }, layers = null, resume = true };
                legacy.Save(profilePath); form = NewForm();
                Check(Get<LightingProfile>(form, "profile").layers[0].id == "00000000-0000-4000-8000-000000000001" && Get<ComboBox>(form, "effectBox").SelectedIndex == 2, "legacy Mac profile loads stable editable layer");
                Check(Get<RGBClient>(form, "client") == null && !Get<bool>(form, "playing"), "preview never auto-resumes an imported profile");
                DisposeForm(form); form = null;
                Console.WriteLine("PASS: " + checks + " isolated Studio UI integration checks; no device connections or lighting commands.");
                return 0;
            }
            catch (Exception error) { Console.Error.WriteLine(error); return 1; }
            finally
            {
                DisposeForm(form);
                // These exact files and the isolated directory were created by
                // this invocation. Never delete a preexisting preview-state.
                if (ownsState)
                {
                    if (File.Exists(profilePath)) File.Delete(profilePath);
                    if (File.Exists(mapPath)) File.Delete(mapPath);
                    if (Directory.Exists(mapPath) && !Directory.EnumerateFileSystemEntries(mapPath).Any()) Directory.Delete(mapPath);
                    if (Directory.Exists(directory) && !Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
                }
            }
        }
    }
}
