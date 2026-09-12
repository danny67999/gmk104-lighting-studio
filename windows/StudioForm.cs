using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace Gmk104LightingStudio
{
    public sealed class StudioForm : Form
    {
        private readonly Color surface = Color.FromArgb(19, 24, 31), ink = Color.FromArgb(232, 239, 246), accent = Color.FromArgb(70, 220, 147);
        private readonly SemaphoreSlim io = new SemaphoreSlim(1, 1);
        private readonly JavaScriptSerializer json = new JavaScriptSerializer();
        private readonly string dataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GMK104RgbController");
        private RGBClient client;
        private KeyGeometry[] keys;
        private MappingFile map, undoMap;
        private LightingProfile profile, applied, savedProfile;
        private readonly bool preview;
        private readonly List<KeyPulse> pulses = new List<KeyPulse>();
        private KeyboardInput input;
        private NativeLightingInputs liveInputs;
        private bool busy, frameInFlight, playing, loading, selecting, retryWanted, quitting, closing;
        private int generation, illuminated = -1;
        private RGB[] beforeMapping;
        private int beforeMappingEffect = -1;
        private int? savedSleep;
        private double previousFrame, nextFrame, measuredFps;
        private readonly System.Windows.Forms.Timer animation = new System.Windows.Forms.Timer { Interval = 1 };
        private readonly System.Windows.Forms.Timer reconnect = new System.Windows.Forms.Timer { Interval = 5000 };
        private readonly System.Windows.Forms.Timer sensors = new System.Windows.Forms.Timer { Interval = 2000 };
        private Label connectionLabel, statusLabel, frameLabel, inputLabel, sensorLabel, selectedLabel, mappingLabel, sleepLabel;
        private ComboBox transportBox, effectBox, blendBox, fpsBox, sleepBox;
        private Button connectButton, applyButton, stopButton, colorButton, chooseButton, inputButton;
        private ListBox layersBox;
        private TextBox layerName;
        private NumericUpDown speed, intensity, opacity, brightness, sensitivity, cold, hot, builtin, ledIndex;
        private CheckBox layerEnabled, affectAll, restoreBox, quickMapping;
        private TabControl tabs;
        private KeyboardView keyboard;
        private NotifyIcon tray;
        private readonly string[] effectNames = { "Ripple", "Rainbow ripple", "Reactive", "Rainbow wave", "Breathing", "Spectrum cycle", "Static color", "Adaptive music", "CPU temperature" };
        private readonly string[] effectIds = { "ripple", "rainbowRipple", "reactive", "wave", "breathing", "spectrum", "staticColor", "adaptiveMusic", "cpuTemperature" };
        private readonly int[] sleepChoices = { 60, 120, 300, 600, 900, 1800, 3600, 0 };
        private string selectedMappingKey;
        private string ProfilePath { get { return Path.Combine(dataPath, "lighting-profile.json"); } }
        private string MapPath { get { return Path.Combine(dataPath, "led-map.json"); } }
        private LightingLayer Selected { get { return profile.layers[Math.Max(0, Math.Min(profile.layers.Count - 1, layersBox.SelectedIndex))]; } }
        private double Now { get { return NativeLightingInputs.MonotonicTime; } }

        public StudioForm(bool preview = false)
        {
            this.preview = preview;
            if (preview) dataPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "preview-state");
            Text = "GMK104 Lighting Studio • Windows"; Width = 1280; Height = 980; MinimumSize = new Size(1100, 820);
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            StartPosition = FormStartPosition.CenterScreen; BackColor = surface; ForeColor = ink;
            Font = new Font("Segoe UI", 9); AutoScaleMode = AutoScaleMode.Dpi;
            keys = json.Deserialize<KeyGeometry[]>(File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "layout.json")));
            Directory.CreateDirectory(dataPath);
            map = MappingFile.Load(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "default-led-map.json"));
            string startupNote = "Ready. Connect to read your keyboard’s current lighting.";
            try { if (File.Exists(MapPath)) { var savedMap = MappingFile.Load(MapPath); savedMap.Validate(keys); map = savedMap; } }
            catch (Exception ex) { startupNote = "Saved map could not be loaded; using the bundled row map. " + ex.Message; }
            map.Validate(keys);
            profile = NewProfile();
            try { LightingProfile saved = LightingProfile.Load(ProfilePath); if (saved != null) { saved.Validate(keys); profile = saved; profile.layers = saved.StudioLayers; } }
            catch (Exception ex) { startupNote = "Saved profile could not be loaded. " + ex.Message; }
            try
            {
                string p = Path.Combine(dataPath, "keyboard-preferences.json");
                if (File.Exists(p)) { var pref = json.Deserialize<SleepPreference>(File.ReadAllText(p)); if (pref.sleepSeconds == 0 || pref.sleepSeconds >= 60 && pref.sleepSeconds <= 3600) savedSleep = pref.sleepSeconds; }
            }
            catch { startupNote += " Sleep preference could not be loaded."; }
            savedProfile = profile.Clone();
            BuildUI(); LoadLayers(0); statusLabel.Text = startupNote;
            liveInputs = new NativeLightingInputs();
            input = new KeyboardInput(Handle); input.KeyPressed += Pressed;
            animation.Tick += Animate; animation.Start();
            reconnect.Tick += async delegate { if (retryWanted && client == null && !busy && !frameInFlight && !closing) await Connect(); }; reconnect.Start();
            sensors.Tick += delegate { if (playing && applied != null && applied.layers.Any(l => l.enabled && l.opacity > 0 && l.settings.effect == "cpuTemperature")) liveInputs.RefreshTemperature(); UpdateInputStatus(); }; sensors.Start();
            Shown += async delegate { if (!preview) await Connect(); };
            FormClosing += OnClosing;
        }
        private LightingProfile NewProfile()
        {
            var p = new LightingProfile(); p.version = 2; p.mode = "studio"; p.restoreOnReconnect = true; p.resume = false; p.frameRate = 60;
            p.settings = new LightingSettings();
            p.layers = new List<LightingLayer> { new LightingLayer() };
            p.layers[0].name = "Rainbow ripple"; p.layers[0].settings.effect = "rainbowRipple"; p.layers[0].affectAllKeys = true;
            return p;
        }
        private Label LabelText(string text, int width = 0)
        {
            return new Label { Text = text, AutoSize = width == 0, Width = width, Height = 25, TextAlign = ContentAlignment.MiddleLeft, Margin = new Padding(4, 6, 4, 2), ForeColor = ink };
        }
        private Button ButtonText(string text, Action action, bool primary = false)
        {
            var b = new Button { Text = text, AutoSize = true, Height = 31, MinimumSize = new Size(65, 31), FlatStyle = FlatStyle.Flat, BackColor = primary ? accent : Color.FromArgb(34, 43, 53), ForeColor = primary ? Color.FromArgb(9, 25, 17) : ink, Margin = new Padding(4) };
            b.FlatAppearance.BorderColor = primary ? accent : Color.FromArgb(60, 73, 86); b.Click += delegate { action(); }; return b;
        }
        private ComboBox Combo(string[] values, int width = 130)
        {
            var c = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, DrawMode = DrawMode.OwnerDrawFixed, ItemHeight = 20, Width = width, BackColor = Color.FromArgb(33, 41, 50), ForeColor = ink, Margin = new Padding(4, 6, 4, 4) };
            c.DrawItem += delegate(object sender, DrawItemEventArgs e) { if (e.Index < 0) return; using (var brush = new SolidBrush((e.State & DrawItemState.Selected) != 0 ? Color.FromArgb(36, 82, 65) : Color.FromArgb(33, 41, 50))) e.Graphics.FillRectangle(brush, e.Bounds); TextRenderer.DrawText(e.Graphics, c.Items[e.Index].ToString(), Font, e.Bounds, ink, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPrefix); };
            c.Items.AddRange(values); c.SelectedIndex = 0; return c;
        }
        private NumericUpDown Number(decimal min, decimal max, decimal value, int decimals = 0, decimal increment = 1)
        {
            return new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Max(min, Math.Min(max, value)), DecimalPlaces = decimals, Increment = increment, Width = decimals == 0 ? 65 : 78, BackColor = Color.FromArgb(33, 41, 50), ForeColor = ink, Margin = new Padding(4, 7, 10, 4) };
        }
        private FlowLayoutPanel Row(params Control[] controls)
        {
            var p = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, WrapContents = true, Padding = new Padding(3) }; p.Controls.AddRange(controls); return p;
        }
        private FlowLayoutPanel Column()
        {
            return new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(8) };
        }
        private void BuildUI()
        {
            var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, Padding = new Padding(20, 10, 20, 8) };
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 63)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 29));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 285)); root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 57));
            Controls.Add(root);
            var header = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1 };
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 340)); header.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            header.Controls.Add(new Label { Text = "GMK104  /  LIGHTING STUDIO", Font = new Font("Segoe UI", 20, FontStyle.Bold), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
            transportBox = Combo(new[] { "Auto", "Bluetooth", "USB", "2.4 GHz" }, 106);
            connectButton = ButtonText("Connect", async delegate { if (client == null) await Connect(); else await Disconnect(); });
            var connectionActions = Row(transportBox, connectButton, ButtonText("Refresh", async delegate { await DeviceAction("Reading current lighting…", c => ReadResult(c), false); }));
            connectionActions.AutoSize = false; connectionActions.Dock = DockStyle.Fill; connectionActions.WrapContents = false;
            header.Controls.Add(connectionActions, 1, 0); root.Controls.Add(header, 0, 0);
            connectionLabel = LabelText("Offline", 225); frameLabel = LabelText("104-key row layout", 740);
            var stateRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Margin = new Padding(0) };
            stateRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 225)); stateRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            connectionLabel.Dock = DockStyle.Fill; frameLabel.Dock = DockStyle.Fill; connectionLabel.Margin = frameLabel.Margin = new Padding(4, 0, 4, 0);
            stateRow.Controls.Add(connectionLabel, 0, 0); stateRow.Controls.Add(frameLabel, 1, 0); root.Controls.Add(stateRow, 0, 1);
            keyboard = new KeyboardView { Keys = keys, Mapping = map, Font = new Font("Segoe UI", 8) }; keyboard.KeyClicked += ClickKey; root.Controls.Add(keyboard, 0, 2);
            tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(18, 6) }; root.Controls.Add(tabs, 0, 3);
            var studio = new TabPage("Effect layers") { BackColor = surface, ForeColor = ink };
            var manual = new TabPage("Manual lighting") { BackColor = surface, ForeColor = ink };
            var mapping = new TabPage("Key mapping") { BackColor = surface, ForeColor = ink };
            tabs.TabPages.AddRange(new[] { studio, manual, mapping });
            tabs.SelectedIndexChanged += async delegate
            {
                selecting = false; keyboard.ShowIndices = tabs.SelectedIndex == 2; keyboard.Selection = null; keyboard.Invalidate(); if (chooseButton != null) UpdateSelection();
                if (tabs.SelectedIndex != 2 && beforeMappingEffect >= 0 && client != null && !busy)
                {
                    RGB[] frame = beforeMapping; int effect = beforeMappingEffect;
                    if (await DeviceAction("Restoring lighting after mapping…", c => { if (frame != null) c.SetFrame(frame); else c.SetEffect(effect); return ReadResult(c, false); })) { beforeMapping = null; beforeMappingEffect = -1; illuminated = -1; }
                }
            };
            var split = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2 };
            split.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 260)); split.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            split.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); split.RowStyles.Add(new RowStyle(SizeType.Absolute, 120)); studio.Controls.Add(split);
            var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, Padding = new Padding(4) };
            left.RowStyles.Add(new RowStyle(SizeType.Absolute, 29)); left.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 88));
            left.Controls.Add(LabelText("TOP LAYER APPEARS ABOVE THE REST"), 0, 0);
            layersBox = new ListBox { Dock = DockStyle.Fill, BackColor = Color.FromArgb(12, 18, 24), ForeColor = ink, BorderStyle = BorderStyle.FixedSingle, ItemHeight = 29, DrawMode = DrawMode.OwnerDrawFixed };
            layersBox.DrawItem += DrawLayer; layersBox.SelectedIndexChanged += delegate { LoadEditor(); }; left.Controls.Add(layersBox, 0, 1);
            var layerActions = Row(ButtonText("+ Add", AddLayer), ButtonText("Copy", DuplicateLayer), ButtonText("Remove", RemoveLayer), ButtonText("↑ Up", () => MoveLayer(-1)), ButtonText("↓ Down", () => MoveLayer(1)));
            foreach (Control action in layerActions.Controls) { action.AutoSize = false; action.MinimumSize = Size.Empty; action.Width = 66; }
            layerActions.AutoSize = false; layerActions.Dock = DockStyle.Fill; left.Controls.Add(layerActions, 0, 2); split.Controls.Add(left, 0, 0);
            var editor = Column(); split.Controls.Add(editor, 1, 0);
            layerName = new TextBox { Width = 225, BackColor = Color.FromArgb(33, 41, 50), ForeColor = ink, Margin = new Padding(4, 7, 4, 4) };
            layerEnabled = new CheckBox { Text = "Enabled", AutoSize = true, Margin = new Padding(12, 7, 4, 4) };
            blendBox = Combo(new[] { "Normal", "Add light" }, 105); effectBox = Combo(effectNames, 170);
            editor.Controls.Add(Row(LabelText("Layer"), layerName, layerEnabled, LabelText("Blend"), blendBox));
            colorButton = ButtonText("Color…", PickColor); speed = Number(.25m, 3, 1, 2, .25m); intensity = Number(0, 100, 100); opacity = Number(0, 100, 100);
            editor.Controls.Add(Row(LabelText("Effect"), effectBox, colorButton, LabelText("Speed"), speed));
            editor.Controls.Add(Row(LabelText("Intensity %"), intensity, LabelText("Opacity %"), opacity));
            sensitivity = Number(.25m, 4, 1, 2, .25m); cold = Number(10, 80, 40); hot = Number(40, 110, 90);
            editor.Controls.Add(Row(LabelText("Music sensitivity"), sensitivity, LabelText("Blue at °C"), cold, LabelText("Red at °C"), hot));
            selectedLabel = LabelText("All 104 keys", 210); chooseButton = ButtonText("Choose keys", delegate { selecting = !selecting; UpdateSelection(); });
            editor.Controls.Add(Row(selectedLabel, chooseButton, ButtonText("All", () => SetSelection(null)), ButtonText("None", () => SetSelection(new List<string>())), ButtonText("WASD", () => SetSelection(new List<string> { "KeyW", "KeyA", "KeyS", "KeyD" })), ButtonText("Arrows", () => SetSelection(keys.Where(k => k.id.StartsWith("Arrow")).Select(k => k.id).ToList()))));
            affectAll = new CheckBox { Text = "Affect all keys — selected keys remain the triggers", AutoSize = true, Margin = new Padding(8) }; editor.Controls.Add(affectAll);
            editor.Controls.Add(LabelText("Click the keyboard to select keys or set a single key’s color."));
            sensorLabel = LabelText("Audio and CPU sensor status appear while layers are running.", 690); sensorLabel.Height = 46; editor.Controls.Add(sensorLabel);
            foreach (Control control in new Control[] { layerName, effectBox, blendBox, speed, opacity, intensity, sensitivity, cold, hot, layerEnabled, affectAll })
            {
                var n = control as NumericUpDown; if (n != null) n.ValueChanged += delegate { SaveEditor(); };
                var c = control as ComboBox; if (c != null) c.SelectedIndexChanged += delegate { SaveEditor(); };
                var check = control as CheckBox; if (check != null) check.CheckedChanged += delegate { SaveEditor(); };
                var t = control as TextBox; if (t != null) t.TextChanged += delegate { SaveEditor(); };
            }
            fpsBox = Combo(new[] { "15", "30", "60", "90", "120" }, 66); fpsBox.SelectedItem = (profile.frameRate ?? 60).ToString();
            brightness = Number(0, 4, profile.settings.brightness); restoreBox = new CheckBox { Text = "Restore saved lighting after reconnect", AutoSize = true, Checked = profile.restoreOnReconnect, Margin = new Padding(8) };
            restoreBox.CheckedChanged += delegate { if (loading) return; profile.restoreOnReconnect = restoreBox.Checked; savedProfile.restoreOnReconnect = restoreBox.Checked; SaveProfile(false); };
            applyButton = ButtonText("Apply & save layers", async delegate { await StartStudio(); }, true); stopButton = ButtonText("Stop", StopPlayback);
            var bottom = Column(); bottom.Controls.Add(Row(LabelText("FPS cap"), fpsBox, LabelText("Brightness"), brightness, applyButton, stopButton, ButtonText("Test pulse", PreviewPulse), ButtonText("Import profile", ImportProfile), ButtonText("Export saved", ExportProfile)));
            inputLabel = LabelText("Key response is off.", 380); inputButton = ButtonText("Enable key response", delegate { if (input.IsRunning) { input.Stop(); pulses.Clear(); inputLabel.Text = input.Status; inputButton.Text = "Enable key response"; } else EnableInput(); });
            bottom.Controls.Add(Row(inputLabel, inputButton, restoreBox)); split.Controls.Add(bottom, 0, 1); split.SetColumnSpan(bottom, 2);
            BuildManual(manual); BuildMapping(mapping);
            statusLabel = new Label { Dock = DockStyle.Fill, ForeColor = Color.FromArgb(177, 195, 207), TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(8), BackColor = Color.FromArgb(25, 32, 40) }; root.Controls.Add(statusLabel, 0, 4);
            tray = new NotifyIcon { Text = "GMK104 Lighting Studio", Icon = Icon ?? SystemIcons.Application, Visible = true };
            tray.DoubleClick += delegate { Show(); WindowState = FormWindowState.Normal; Activate(); };
            var menu = new ContextMenuStrip(); menu.Items.Add("Open Lighting Studio", null, delegate { Show(); WindowState = FormWindowState.Normal; Activate(); });
            menu.Items.Add("Stop lighting animation", null, delegate { StopPlayback(); });
            menu.Items.Add("Quit", null, delegate { quitting = true; Close(); }); tray.ContextMenuStrip = menu;
        }
        private void BuildManual(TabPage page)
        {
            var p = Column(); page.Controls.Add(p);
            p.Controls.Add(LabelText("Choose a color in Effect layers, then apply it here or click an individual key."));
            p.Controls.Add(Row(ButtonText("Set all keys", async delegate { RGB[] f = Enumerable.Repeat(Selected.settings.color, 104).ToArray(); int b = (int)brightness.Value; if (await DeviceAction("Applying full color…", c => { c.SetBrightness(b); c.SetFrame(f); return ReadResult(c, false); })) SaveManual("frame", f); }),
                ButtonText("Clear", async delegate { if (await DeviceAction("Clearing lighting…", c => { c.Clear(); return ReadResult(c, false); })) SaveManual("frame", new RGB[104]); }),
                ButtonText("Apply brightness", async delegate { int b = (int)brightness.Value; if (await DeviceAction("Applying brightness…", c => { c.SetBrightness(b); return ReadResult(c, false); }, false)) { profile.settings.brightness = b; savedProfile.settings.brightness = b; if (applied != null) applied.settings.brightness = b; SaveProfile(false); } })));
            builtin = Number(0, 18, profile.builtInEffect);
            p.Controls.Add(Row(LabelText("Built-in effect"), builtin, ButtonText("Play & save", async delegate { int effect = (int)builtin.Value; int b = (int)brightness.Value; if (await DeviceAction("Applying built-in effect…", c => { c.SetBrightness(b); c.SetEffect(effect); return ReadResult(c); })) { profile.builtInEffect = effect; SaveManual("builtIn", null); } })));
            sleepBox = Combo(sleepChoices.Select(x => x == 0 ? "Never" : (x / 60) + " minutes").ToArray(), 125); sleepBox.SelectedIndex = 2;
            if (savedSleep.HasValue) { int index = Array.IndexOf(sleepChoices, savedSleep.Value); if (index >= 0) sleepBox.SelectedIndex = index; }
            sleepLabel = LabelText("Connect to check adjustable sleep support.", 760);
            p.Controls.Add(Row(LabelText("Wireless sleep after"), sleepBox, ButtonText("Apply sleep time", async delegate
            {
                int seconds = sleepChoices[sleepBox.SelectedIndex];
                if (await DeviceAction("Applying wireless sleep time…", c => { c.SetSleepSeconds(seconds); return new DeviceResult { State = c.Read(), Sleep = c.ReadSleepSeconds() }; }, false))
                { savedSleep = seconds; SaveSleep(); }
            })));
            p.Controls.Add(sleepLabel); p.Controls.Add(LabelText("Sleep applies to Bluetooth and 2.4 GHz; saved settings are reapplied after reconnect."));
            p.Controls.Add(LabelText("Firmware v0.3 and v0.4 use the same verified lighting protocol. Firmware updates require wired USB."));
            p.Controls.Add(LabelText("CPU temperature uses an existing LibreHardwareMonitor/OpenHardwareMonitor CPU sensor provider."));
            p.Controls.Add(LabelText("The Windows app reads system playback for music layers. Audio is processed locally."));
            p.Controls.Add(ButtonText("Apply imported / saved profile", async delegate { await RestoreProfile(); }));
        }
        private void BuildMapping(TabPage page)
        {
            var p = Column(); page.Controls.Add(p);
            p.Controls.Add(LabelText("The Mac row map is included: Escape = LED 0, continuing across each physical row."));
            p.Controls.Add(LabelText("Click a key to test it. To correct an assignment, light an LED, select the glowing key, then save."));
            ledIndex = Number(0, 103, 0); mappingLabel = LabelText("Select a key on the diagram.", 470);
            p.Controls.Add(Row(LabelText("LED"), ledIndex, ButtonText("Light LED", async delegate { await Identify((int)ledIndex.Value); }), ButtonText("Previous", async delegate { ledIndex.Value = Math.Max(0, ledIndex.Value - 1); await Identify((int)ledIndex.Value); }), ButtonText("Next", async delegate { ledIndex.Value = Math.Min(103, ledIndex.Value + 1); await Identify((int)ledIndex.Value); })));
            quickMapping = new CheckBox { Text = "Save and advance on a physical key press", AutoSize = true, Margin = new Padding(8) };
            p.Controls.Add(Row(mappingLabel, ButtonText("Save correction", SaveMappingCorrection, true))); p.Controls.Add(quickMapping);
            p.Controls.Add(Row(ButtonText("Use row layout", delegate { SaveMap(MappingFile.RowOrder(keys)); }), ButtonText("Undo map change", delegate { if (undoMap != null) SaveMap(undoMap); }), ButtonText("Import mapping", ImportMap), ButtonText("Export mapping", ExportMap)));
            p.Controls.Add(LabelText("Key response must be enabled to capture physical keys. Mapping changes have an Undo backup."));
        }
        private void DrawLayer(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0 || e.Index >= profile.layers.Count) return;
            var l = profile.layers[e.Index]; e.DrawBackground();
            using (var b = new SolidBrush((e.State & DrawItemState.Selected) != 0 ? Color.FromArgb(32, 80, 61) : Color.FromArgb(12, 18, 24))) e.Graphics.FillRectangle(b, e.Bounds);
            TextRenderer.DrawText(e.Graphics, (l.enabled ? "●  " : "○  ") + l.name, Font, e.Bounds, l.enabled ? ink : Color.Gray, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis); e.DrawFocusRectangle();
        }
        private void LoadLayers(int selection)
        {
            loading = true; layersBox.Items.Clear(); foreach (var l in profile.layers) layersBox.Items.Add(l.name);
            layersBox.SelectedIndex = Math.Max(0, Math.Min(profile.layers.Count - 1, selection)); loading = false; LoadEditor();
        }
        private void LoadEditor()
        {
            if (loading || layersBox.SelectedIndex < 0) return; loading = true;
            var l = Selected; layerName.Text = l.name; layerEnabled.Checked = l.enabled; effectBox.SelectedIndex = Math.Max(0, Array.IndexOf(effectIds, l.settings.effect)); blendBox.SelectedIndex = l.blendMode == "additive" ? 1 : 0;
            speed.Value = (decimal)l.settings.speed; intensity.Value = (decimal)l.settings.intensity * 100; opacity.Value = (decimal)l.opacity * 100;
            sensitivity.Value = (decimal)l.settings.musicSensitivity; cold.Value = (decimal)l.settings.temperatureCold; hot.Value = (decimal)l.settings.temperatureHot;
            affectAll.Checked = l.affectAllKeys; colorButton.BackColor = Color.FromArgb(l.settings.color.r, l.settings.color.g, l.settings.color.b); colorButton.Text = l.settings.color.ToString(); colorButton.ForeColor = l.settings.color.r + l.settings.color.g + l.settings.color.b > 380 ? Color.Black : Color.White;
            loading = false; UpdateSelection();
        }
        private void SaveEditor()
        {
            if (loading || layersBox.SelectedIndex < 0) return;
            var l = Selected; l.name = layerName.Text; l.enabled = layerEnabled.Checked; l.settings.effect = effectIds[Math.Max(0, effectBox.SelectedIndex)]; l.blendMode = blendBox.SelectedIndex == 1 ? "additive" : "normal";
            l.settings.speed = (double)speed.Value; l.settings.intensity = (double)intensity.Value / 100; l.opacity = (double)opacity.Value / 100;
            l.settings.musicSensitivity = (double)sensitivity.Value; l.settings.temperatureCold = (double)cold.Value; l.settings.temperatureHot = (double)hot.Value; l.affectAllKeys = affectAll.Checked;
            layersBox.Invalidate(); UpdateSelection();
        }
        private void PickColor()
        {
            using (var d = new ColorDialog { FullOpen = true, Color = Color.FromArgb(Selected.settings.color.r, Selected.settings.color.g, Selected.settings.color.b) })
                if (d.ShowDialog(this) == DialogResult.OK) { Selected.settings.color = new RGB(d.Color.R, d.Color.G, d.Color.B); LoadEditor(); }
        }
        private void AddLayer() { if (profile.layers.Count >= 16) return; var l = new LightingLayer(); l.name = "Static color"; l.settings.effect = "staticColor"; profile.layers.Insert(0, l); LoadLayers(0); }
        private void DuplicateLayer() { if (profile.layers.Count >= 16) return; var l = Selected.Clone(); l.id = Guid.NewGuid().ToString(); l.name = l.name.Length > 73 ? l.name.Substring(0, 73) + " copy" : l.name + " copy"; int index = layersBox.SelectedIndex; profile.layers.Insert(index, l); LoadLayers(index); }
        private void RemoveLayer() { if (profile.layers.Count <= 1) return; int i = layersBox.SelectedIndex; profile.layers.RemoveAt(i); LoadLayers(i); }
        private void MoveLayer(int direction) { int a = layersBox.SelectedIndex, b = a + direction; if (b < 0 || b >= profile.layers.Count) return; var l = profile.layers[a]; profile.layers[a] = profile.layers[b]; profile.layers[b] = l; LoadLayers(b); }
        private void SetSelection(List<string> ids) { Selected.keyIDs = ids; UpdateSelection(); }
        private void UpdateSelection()
        {
            selectedLabel.Text = Selected.keyIDs == null ? "All 104 keys" : Selected.keyIDs.Count + " selected / trigger keys";
            chooseButton.Text = selecting ? "Done selecting" : "Choose keys";
            keyboard.Selection = selecting ? new HashSet<string>(Selected.keyIDs ?? keys.Select(k => k.id).ToList()) : null; keyboard.Invalidate();
        }
        private async void ClickKey(string id)
        {
            if (busy) return;
            if (selecting) { var ids = Selected.keyIDs == null ? keys.Select(k => k.id).ToList() : new List<string>(Selected.keyIDs); if (ids.Contains(id)) ids.Remove(id); else ids.Add(id); SetSelection(ids); return; }
            if (tabs.SelectedIndex == 2)
            {
                selectedMappingKey = id; mappingLabel.Text = "Selected: " + id + (illuminated < 0 ? "" : " • Lit LED " + illuminated);
                if (illuminated < 0) { var m = map.mappings.First(x => x.keyId == id); if (m.ledIndex.HasValue) { ledIndex.Value = m.ledIndex.Value; await Identify(m.ledIndex.Value); } }
                return;
            }
            var entry = map.mappings.First(x => x.keyId == id); if (!entry.confirmed || !entry.ledIndex.HasValue) { Status("Map this key before assigning a color."); return; }
            RGB color = Selected.settings.color; int index = entry.ledIndex.Value;
            if (await DeviceAction("Setting " + id + "…", c => { c.SetLED(index, color); return ReadResult(c, false); })) SaveManual("frame", keyboard.Frame);
        }
        private void Pressed(string id)
        {
            if (closing) return;
            if (InvokeRequired) { BeginInvoke(new Action<string>(Pressed), id); return; }
            pulses.Add(new KeyPulse(id, Now)); if (pulses.Count > 48) pulses.RemoveRange(0, pulses.Count - 48);
            inputLabel.Text = "Key response enabled • Last key: " + id;
            if (tabs.SelectedIndex == 2 && ContainsFocus && !busy && illuminated >= 0)
            { selectedMappingKey = id; mappingLabel.Text = "Selected: " + id + " • Lit LED " + illuminated; if (quickMapping.Checked) SaveMappingCorrection(); }
        }
        private void PreviewPulse()
        {
            if (!playing || applied == null) { Status("Apply a reactive layer first, then test its pulse."); return; }
            var layer = applied.layers.FirstOrDefault(l => l.id == Selected.id && l.enabled && l.opacity > 0 && (l.settings.effect == "ripple" || l.settings.effect == "rainbowRipple" || l.settings.effect == "reactive"));
            if (layer == null) layer = applied.layers.FirstOrDefault(l => l.enabled && l.opacity > 0 && (l.settings.effect == "ripple" || l.settings.effect == "rainbowRipple" || l.settings.effect == "reactive"));
            string id = layer == null ? null : map.mappings.Where(m => m.confirmed && m.ledIndex.HasValue && layer.AcceptsTrigger(m.keyId)).Select(m => m.keyId).FirstOrDefault();
            if (id == null) { Status("No mapped trigger keys are enabled in the running reactive layers."); return; }
            Pressed(id);
        }
        private void EnableInput()
        {
            if (client == null) { Status("Connect the keyboard first."); return; }
            bool started = input.Start(client.Transport.ConnectionName, client.Transport.DeviceIdentity);
            inputLabel.Text = input.Status; inputButton.Text = started ? "Disable key response" : "Enable key response";
        }
        private void UpdateInputStatus()
        {
            if (liveInputs == null || closing) return;
            sensorLabel.Text = liveInputs.AudioStatus + "\r\n" + liveInputs.TemperatureStatus;
        }
        private void StartInputs()
        {
            EnableInput();
            if (applied.layers.Any(l => l.enabled && l.opacity > 0 && l.settings.effect == "adaptiveMusic" && (l.keyIDs == null || l.keyIDs.Count > 0))) liveInputs.StartAudio(); else liveInputs.StopAudio();
            if (applied.layers.Any(l => l.enabled && l.opacity > 0 && l.settings.effect == "cpuTemperature")) liveInputs.RefreshTemperature(); UpdateInputStatus();
        }
        private async Task Connect()
        {
            if (preview || busy || closing || client != null) return; busy = true; retryWanted = true; UpdateControls(); Status("Connecting and checking the keyboard…");
            string preferred = transportBox.Text; RGBClient candidate = null; DeviceResult result = null; int epoch = ++generation;
            try
            {
                await io.WaitAsync();
                try { result = await Task.Run(() => { candidate = new RGBClient(KeyboardConnections.Open(preferred)); var r = ReadResult(candidate); r.Sleep = candidate.ReadSleepSeconds(); return r; }); }
                finally { io.Release(); }
                if (closing || epoch != generation) { if (candidate != null) candidate.Dispose(); return; }
                client = candidate; candidate = null; ShowResult(result); Status("Connected over " + client.Transport.ConnectionName + ". Firmware identity verified.");
            }
            catch (Exception ex) { if (candidate != null) candidate.Dispose(); Status(ex.Message); }
            finally { busy = false; UpdateControls(); }
            if (client != null && savedSleep.HasValue) { int seconds = savedSleep.Value; await DeviceAction("Restoring wireless sleep setting…", c => { if (c.ReadSleepSeconds().HasValue) c.SetSleepSeconds(seconds); return new DeviceResult { State = c.Read(), Sleep = c.ReadSleepSeconds() }; }, false); }
            if (client != null && savedProfile.restoreOnReconnect && savedProfile.resume) await RestoreProfile();
        }
        private async Task Disconnect()
        {
            retryWanted = false; playing = false; generation++; busy = true; UpdateControls(); input.Stop(); liveInputs.StopAudio();
            await io.WaitAsync(); try { if (client != null) client.Dispose(); client = null; } finally { io.Release(); busy = false; }
            beforeMapping = null; beforeMappingEffect = -1; illuminated = -1; UpdateControls(); Status("Disconnected. Your saved profile is unchanged.");
        }
        private DeviceResult ReadResult(RGBClient c, bool fresh = true)
        {
            var s = c.Read(); return new DeviceResult { State = s, Frame = s.Effect == 19 ? (fresh ? c.ReadFrame() : c.Shadow ?? c.ReadFrame()) : null };
        }
        private async Task<bool> DeviceAction(string label, Func<RGBClient, DeviceResult> action, bool stop = true)
        {
            if (busy || closing) return false;
            if (client == null) { Status("Connect the keyboard first."); return false; }
            busy = true; if (stop) { playing = false; liveInputs.StopAudio(); } generation++; UpdateControls(); Status(label);
            try
            {
                await io.WaitAsync(); DeviceResult result;
                try { result = await Task.Run(() => action(client)); } finally { io.Release(); }
                if (closing) return false; ShowResult(result); Status("Lighting verified on " + client.Transport.ConnectionName + "."); return true;
            }
            catch (Exception ex)
            {
                Status(ex.Message); playing = false; liveInputs.StopAudio(); input.Stop();
                if (!(ex is LightingVerificationException) && client != null) { client.Dispose(); client = null; }
                return false;
            }
            finally { busy = false; UpdateControls(); }
        }
        private void ShowResult(DeviceResult result)
        {
            if (result == null) return;
            if (result.Frame != null) { keyboard.Frame = result.Frame; keyboard.Invalidate(); }
            if (result.State != null) frameLabel.Text = String.Format("{0} • Brightness {1} • {2}/104 keys mapped", result.State.Effect == 19 ? "Direct RGB" : "Built-in effect " + result.State.Effect, result.State.Brightness, map.mappings.Count(m => m.confirmed));
            if (result.Sleep.HasValue) sleepLabel.Text = "Verified sleep setting: " + (result.Sleep.Value == 0 ? "Never" : result.Sleep.Value / 60.0 + " minutes");
        }
        private async Task StartStudio(LightingProfile restored = null)
        {
            if (busy) return;
            if (restored == null) SaveEditor(); LightingProfile requested = restored == null ? profile.Clone() : restored.Clone(); requested.mode = "studio"; requested.resume = true;
            if (restored == null) { requested.frameRate = Int32.Parse(fpsBox.Text); requested.settings.brightness = (int)brightness.Value; requested.restoreOnReconnect = restoreBox.Checked; }
            try { requested.Validate(keys); } catch (Exception ex) { Status(ex.Message); return; }
            RGB[] frame = LightingEngine.Render(requested.layers, keys, map, new List<KeyPulse>(pulses), Now, liveInputs.Snapshot(Now));
            bool okay = await DeviceAction("Starting layers and verifying all 104 LEDs…", c => { c.SetBrightness(requested.settings.brightness); c.SetFrame(frame); return new DeviceResult { State = c.Read(), Frame = c.Shadow }; });
            if (!okay) return;
            if (restored == null) { profile = requested; SaveProfile(); } else { savedProfile = requested.Clone(); SaveProfile(false); }
            applied = requested.Clone(); beforeMappingEffect = -1; beforeMapping = null;
            playing = true; previousFrame = Now; nextFrame = Now; StartInputs(); UpdateControls();
        }
        private async Task RestoreProfile()
        {
            if (savedProfile.mode == "studio") { await StartStudio(savedProfile); return; }
            var p = savedProfile.Clone();
            if (await DeviceAction("Restoring saved lighting…", c => { c.SetBrightness(p.settings.brightness); if (p.mode == "frame") c.SetFrame(p.colors); else c.SetEffect(p.builtInEffect); return ReadResult(c, false); })) { savedProfile.resume = true; SaveProfile(false); }
        }
        private async void Animate(object sender, EventArgs e)
        {
            if (!playing || busy || frameInFlight || closing || client == null || applied == null || Now < nextFrame) return;
            frameInFlight = true; int epoch = generation; RGBClient target = client; double now = Now;
            if (target.Transport.UsesRollingAnimationVerification)
            {
                double reactiveSpeed = applied.layers.Where(l => l.enabled && l.opacity > 0 && (l.settings.effect == "ripple" || l.settings.effect == "rainbowRipple" || l.settings.effect == "reactive")).Select(l => l.settings.speed).DefaultIfEmpty(1).Max();
                List<KeyPulse> adjusted = LightingEngine.AdjustPulses(pulses, previousFrame, now, .1 / reactiveSpeed); pulses.Clear(); pulses.AddRange(adjusted);
            }
            previousFrame = now; pulses.RemoveAll(p => now - p.time > 20 || p.time > now + 1);
            RGB[] frame = LightingEngine.Render(applied.layers, keys, map, new List<KeyPulse>(pulses), now, liveInputs.Snapshot(now));
            try
            {
                await io.WaitAsync();
                try { if (epoch != generation || !playing) return; await Task.Run(() => target.SetAnimationFrame(frame)); }
                finally { io.Release(); }
                if (epoch != generation || closing || !playing) return;
                double elapsed = Math.Max(.001, Now - now); measuredFps = measuredFps == 0 ? 1 / elapsed : measuredFps * .8 + .2 / elapsed;
                keyboard.Frame = frame; keyboard.Invalidate();
                frameLabel.Text = String.Format("LIVE • {0:F1} fps actual / {1} cap • {2} layers • {3}/104 mapped", Math.Min(applied.frameRate ?? 60, measuredFps), applied.frameRate ?? 60, applied.layers.Count, map.mappings.Count(m => m.confirmed));
                nextFrame = now + 1.0 / (applied.frameRate ?? 60);
            }
            catch (Exception ex)
            {
                if (epoch == generation && !closing)
                {
                    playing = false; generation++; liveInputs.StopAudio(); input.Stop();
                    target.Dispose(); if (client == target) client = null;
                    Status("Playback paused: " + ex.Message + " Wake the keyboard to reconnect."); UpdateControls();
                }
            }
            finally { frameInFlight = false; }
        }
        private void StopPlayback()
        {
            playing = false; generation++; profile.resume = false; savedProfile.resume = false; SaveProfile(false); if (liveInputs != null) liveInputs.StopAudio(); if (input != null) { input.Stop(); pulses.Clear(); inputLabel.Text = input.Status; inputButton.Text = "Enable key response"; } UpdateControls(); Status("Animation stopped. The last verified colors remain on the keyboard.");
        }
        private void SaveManual(string mode, RGB[] colors)
        {
            savedProfile.mode = mode; savedProfile.colors = colors == null ? null : (RGB[])colors.Clone(); savedProfile.builtInEffect = profile.builtInEffect; savedProfile.settings.brightness = (int)brightness.Value; savedProfile.resume = true; savedProfile.restoreOnReconnect = restoreBox.Checked; SaveProfile(false); beforeMapping = null; beforeMappingEffect = -1;
        }
        private void SaveProfile(bool commitDraft = true) { try { var candidate = commitDraft ? profile.Clone() : savedProfile.Clone(); candidate.Save(ProfilePath); savedProfile = candidate; } catch (Exception ex) { Status("Profile could not be saved: " + ex.Message); } }
        private void SaveSleep()
        {
            try { PersistJson.Save(Path.Combine(dataPath, "keyboard-preferences.json"), new SleepPreference { sleepSeconds = savedSleep.Value }); }
            catch (Exception ex) { Status("Sleep setting applied, but the preference could not be saved: " + ex.Message); }
        }
        private async Task Identify(int index)
        {
            RGB[] test = new RGB[104]; test[index] = new RGB(0, 255, 50);
            if (await DeviceAction("Identifying LED " + index + "…", c =>
            {
                if (beforeMappingEffect < 0) { var state = c.Read(); beforeMappingEffect = state.Effect; beforeMapping = state.Effect == 19 ? c.ReadFrame() : null; }
                c.SetFrame(test); return new DeviceResult { State = c.Read(), Frame = c.Shadow };
            })) { illuminated = index; mappingLabel.Text = "Lit LED " + index + ". Select its physical key on the diagram."; }
        }
        private async void SaveMappingCorrection()
        {
            if (busy || illuminated < 0 || String.IsNullOrEmpty(selectedMappingKey)) { Status("Light an LED and select the matching key first."); return; }
            var candidate = map.Clone(); candidate.Assign(selectedMappingKey, illuminated); if (!SaveMap(candidate)) return; Status("Saved " + selectedMappingKey + " → LED " + illuminated + ".");
            if (quickMapping.Checked && illuminated < 103) { ledIndex.Value = illuminated + 1; selectedMappingKey = null; await Identify((int)ledIndex.Value); }
        }
        private bool SaveMap(MappingFile candidate) { try { candidate.Validate(keys); candidate.Save(MapPath); undoMap = map; map = candidate; keyboard.Mapping = map; keyboard.Invalidate(); return true; } catch (Exception ex) { Status(ex.Message); return false; } }
        private void ImportMap()
        {
            using (var d = new OpenFileDialog { Filter = "LED mapping (*.json)|*.json" }) if (d.ShowDialog(this) == DialogResult.OK)
                try { var m = MappingFile.Load(d.FileName); if (SaveMap(m)) Status("Mapping imported. Undo map change restores the previous map."); } catch (Exception ex) { Status(ex.Message); }
        }
        private void ExportMap() { using (var d = new SaveFileDialog { Filter = "LED mapping (*.json)|*.json", FileName = "led-map.json" }) if (d.ShowDialog(this) == DialogResult.OK) try { map.Save(d.FileName); } catch (Exception ex) { Status(ex.Message); } }
        private void ImportProfile()
        {
            using (var d = new OpenFileDialog { Filter = "Mac or Windows profile (*.json)|*.json" }) if (d.ShowDialog(this) == DialogResult.OK)
                try { var p = LightingProfile.Load(d.FileName); p.Validate(keys); StopPlayback(); profile = p; profile.layers = p.StudioLayers; profile.resume = false; brightness.Value = profile.settings.brightness; fpsBox.SelectedItem = (p.frameRate ?? 60).ToString(); builtin.Value = p.builtInEffect; loading = true; restoreBox.Checked = p.restoreOnReconnect; loading = false; LoadLayers(0); SaveProfile(); Status(p.mode == "studio" ? "Profile imported. Apply & save layers to start it." : "Profile imported. Use Apply imported / saved profile in Manual lighting."); } catch (Exception ex) { loading = false; Status(ex.Message); }
        }
        private void ExportProfile() { using (var d = new SaveFileDialog { Filter = "Lighting profile (*.json)|*.json", FileName = "lighting-profile.json" }) if (d.ShowDialog(this) == DialogResult.OK) try { savedProfile.Save(d.FileName); } catch (Exception ex) { Status(ex.Message); } }
        private void Status(string text) { if (!closing && statusLabel != null) statusLabel.Text = text; }
        private void UpdateControls()
        {
            if (closing || tabs == null) return; tabs.Enabled = !busy; connectButton.Enabled = !busy; transportBox.Enabled = !busy && client == null;
            connectButton.Text = client == null ? "Connect" : "Disconnect"; connectionLabel.Text = client == null ? "● Offline" : "● " + client.Transport.ConnectionName + " connected";
            connectionLabel.ForeColor = client == null ? Color.Gray : accent; applyButton.Enabled = client != null && !busy; stopButton.Enabled = playing || frameInFlight;
        }
        private void OnClosing(object sender, FormClosingEventArgs e)
        {
            if (!preview && !quitting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); tray.ShowBalloonTip(2500, "GMK104 Lighting Studio", "Lighting continues in the system tray. Right-click the tray icon to quit.", ToolTipIcon.Info); return; }
            if (busy || frameInFlight) { e.Cancel = true; playing = false; generation++; Status("Finishing the current keyboard operation before quitting…"); var timer = new System.Windows.Forms.Timer { Interval = 250 }; timer.Tick += delegate { if (!busy && !frameInFlight) { timer.Stop(); timer.Dispose(); Close(); } }; timer.Start(); return; }
            closing = true; generation++; animation.Stop(); reconnect.Stop(); sensors.Stop(); input.Dispose(); liveInputs.Dispose(); if (client != null) client.Dispose(); tray.Visible = false; tray.Dispose();
        }
        protected override void WndProc(ref Message m) { if (input != null) input.ProcessMessage(ref m); base.WndProc(ref m); }
        internal void SelectPreviewTab(int index) { tabs.SelectedIndex = Math.Max(0, Math.Min(2, index)); }
        private sealed class DeviceResult { public RGBState State; public RGB[] Frame; public int? Sleep; }
        public sealed class SleepPreference { public int sleepSeconds; }
    }
}
