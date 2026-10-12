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
        private MappingFile map, undoMap, factoryMap;
        private LightingProfile profile, applied, savedProfile, undoLighting;
        private readonly LightingLayer emptyLayer = new LightingLayer { name = "No effects", enabled = false };
        private readonly bool preview;
        private readonly List<KeyPulse> pulses = new List<KeyPulse>();
        private readonly HashSet<string> heldKeys = new HashSet<string>();
        private readonly HashSet<string> toggledKeys = new HashSet<string>();
        private OnboardCapabilities onboard = new OnboardCapabilities();
        private bool onboardPlaying;
        private Button playKeyboardButton, saveKeyboardButton;
        private Label profileLocationLabel;
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
        private ComboBox transportBox, effectBox, blendBox, fpsBox, sleepBox, presetBox;
        private Label effectHint;
        private Button connectButton, applyButton, stopButton, colorButton, chooseButton, inputButton;
        private ListBox layersBox;
        private TextBox layerName;
        private NumericUpDown speed, intensity, opacity, brightness, sensitivity, cold, hot, builtin, ledIndex;
        private CheckBox layerEnabled, affectAll, restoreBox, quickMapping;
        private TabControl tabs;
        private KeyboardView keyboard;
        private NotifyIcon tray;
        private readonly string[] effectIds = LightingEngine.Effects;
        private readonly string[] effectNames = LightingEngine.Effects.Select(LightingEngine.DisplayName).ToArray();
        private readonly int[] sleepChoices = { 60, 120, 300, 600, 900, 1800, 3600, 0 };
        private string selectedMappingKey;
        private string ProfilePath { get { return Path.Combine(dataPath, "lighting-profile.json"); } }
        private string MapPath { get { return Path.Combine(dataPath, "led-map.json"); } }
        private LightingLayer Selected { get { return profile.layers.Count == 0 ? emptyLayer : profile.layers[Math.Max(0, Math.Min(profile.layers.Count - 1, layersBox.SelectedIndex))]; } }
        private double Now { get { return NativeLightingInputs.MonotonicTime; } }

        public StudioForm(bool preview = false)
        {
            this.preview = preview;
            if (preview) dataPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "preview-state");
            Text = "GMK104 Lighting Studio • Windows"; Width = 1280; Height = 980; MinimumSize = new Size(1100, 820);
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            StartPosition = FormStartPosition.CenterScreen; BackColor = surface; ForeColor = ink;
            Font = new Font("Segoe UI", 9); AutoScaleMode = AutoScaleMode.Dpi; AutoScaleDimensions = new SizeF(96, 96);
            keys = json.Deserialize<KeyGeometry[]>(File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "layout.json")));
            Directory.CreateDirectory(dataPath);
            map = MappingFile.Load(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "default-led-map.json"));
            factoryMap = map.Clone();
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
            try { string config = Path.Combine(dataPath, "sensor-provider.json"); if (File.Exists(config)) liveInputs.CpuLogDirectory = PersistJson.String(PersistJson.Read(config), "logDirectory"); }
            catch { startupNote += " CPU log folder setting could not be loaded; use Choose CPU log folder."; statusLabel.Text = startupNote; }
            input = new KeyboardInput(Handle); input.KeyPressed += Pressed; input.KeyReleased += Released;
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
            p.layers[0].name = "Rainbow ripple 1"; p.layers[0].settings.effect = "rainbowRipple"; p.layers[0].affectAllKeys = true;
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
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 175)); root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 45));
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
            keyboard = new KeyboardView { Keys = keys, Mapping = map, Font = new Font("Segoe UI", 8) }; keyboard.KeyClicked += ClickKey; keyboard.SelectionChanged += SetSelection; root.Controls.Add(keyboard, 0, 2);
            tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(18, 6) }; root.Controls.Add(tabs, 0, 3);
            var studio = new TabPage("Effect layers") { BackColor = surface, ForeColor = ink };
            var manual = new TabPage("Manual lighting") { BackColor = surface, ForeColor = ink };
            var mapping = new TabPage("Key mapping") { BackColor = surface, ForeColor = ink };
            tabs.TabPages.AddRange(new[] { studio, manual, mapping });
            tabs.SelectedIndex = 0;
            tabs.SelectedIndexChanged += async delegate
            {
                selecting = tabs.SelectedIndex == 0; keyboard.ShowIndices = tabs.SelectedIndex == 2; keyboard.Selection = null; keyboard.Invalidate(); if (chooseButton != null) UpdateSelection();
                if (tabs.SelectedIndex != 2 && beforeMappingEffect >= 0 && client != null && !busy)
                {
                    RGB[] frame = beforeMapping; int effect = beforeMappingEffect;
                    if (await DeviceAction("Restoring lighting after mapping…", c => { if (frame != null) c.SetFrame(frame); else if (effect == 20) c.SelectOnboardEffect(); else c.SetEffect(effect); return ReadResult(c, false); })) { beforeMapping = null; beforeMappingEffect = -1; illuminated = -1; }
                }
            };
            var split = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2 };
            split.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 260)); split.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            split.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); split.RowStyles.Add(new RowStyle(SizeType.Absolute, 220)); studio.Controls.Add(split);
            var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, Padding = new Padding(4) };
            left.RowStyles.Add(new RowStyle(SizeType.Absolute, 29)); left.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 120));
            left.Controls.Add(LabelText("TOP LAYER APPEARS ABOVE THE REST"), 0, 0);
            layersBox = new ListBox { Dock = DockStyle.Fill, BackColor = Color.FromArgb(12, 18, 24), ForeColor = ink, BorderStyle = BorderStyle.FixedSingle, ItemHeight = 29, DrawMode = DrawMode.OwnerDrawFixed };
            layersBox.DrawItem += DrawLayer; layersBox.SelectedIndexChanged += delegate { LoadEditor(); }; left.Controls.Add(layersBox, 0, 1);
            var layerActions = Row(ButtonText("+ Add", AddLayer), ButtonText("Copy", DuplicateLayer), ButtonText("Remove", RemoveLayer), ButtonText("↑ Up", () => MoveLayer(-1)), ButtonText("↓ Down", () => MoveLayer(1)), ButtonText("Clear all", ClearAllEffects), ButtonText("Undo", UndoLighting));
            foreach (Control action in layerActions.Controls) { action.AutoSize = false; action.MinimumSize = Size.Empty; action.Width = 66; }
            layerActions.AutoSize = false; layerActions.Dock = DockStyle.Fill; left.Controls.Add(layerActions, 0, 2); split.Controls.Add(left, 0, 0);
            var editor = Column(); editor.AutoScrollMinSize = new Size(0, 440); split.Controls.Add(editor, 1, 0);
            presetBox = Combo(LightingPresets.Names, 155);
            editor.Controls.Add(Row(LabelText("Preset"), presetBox, ButtonText("Load preset", LoadPreset), ButtonText("Export draft JSON", ExportDraftProfile)));
            layerName = new TextBox { Width = 225, BackColor = Color.FromArgb(33, 41, 50), ForeColor = ink, Margin = new Padding(4, 7, 4, 4) };
            layerEnabled = new CheckBox { Text = "Enabled", AutoSize = true, Margin = new Padding(12, 7, 4, 4) };
            blendBox = Combo(new[] { "Normal", "Add light" }, 105); effectBox = Combo(effectNames, 170);
            editor.Controls.Add(Row(LabelText("Layer"), layerName, layerEnabled, LabelText("Blend"), blendBox));
            colorButton = ButtonText("Color…", PickColor); speed = Number(.25m, 3, 1, 2, .25m); intensity = Number(0, 100, 100); opacity = Number(0, 100, 100);
            editor.Controls.Add(Row(LabelText("Effect"), effectBox, colorButton, LabelText("Speed"), speed));
            effectHint = LabelText("", 680); effectHint.Height = 38; editor.Controls.Add(effectHint);
            editor.Controls.Add(Row(LabelText("Intensity %"), intensity, LabelText("Opacity %"), opacity));
            sensitivity = Number(.25m, 4, 1, 2, .25m); cold = Number(10, 80, 40); hot = Number(40, 110, 90);
            editor.Controls.Add(Row(LabelText("Music sensitivity"), sensitivity, LabelText("Blue at °C"), cold, LabelText("Red at °C"), hot));
            selectedLabel = LabelText("All 104 keys", 210); chooseButton = ButtonText("Select on keyboard", delegate { keyboard.Focus(); });
            editor.Controls.Add(Row(selectedLabel, chooseButton, ButtonText("All", () => SetSelection(null)), ButtonText("None", () => SetSelection(new List<string>())), ButtonText("WASD", () => SetSelection(new List<string> { "KeyW", "KeyA", "KeyS", "KeyD" })), ButtonText("Arrows", () => SetSelection(keys.Where(k => k.id.StartsWith("Arrow")).Select(k => k.id).ToList()))));
            affectAll = new CheckBox { Text = "Affect all keys — selected keys remain the triggers", AutoSize = true, Margin = new Padding(8) }; editor.Controls.Add(affectAll);
            editor.Controls.Add(LabelText("Drag across keys to paint a selection; drag from a gap for a rectangle. Shift adds; Alt removes.", 690));
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
            applyButton = ButtonText("Play from PC", async delegate { await StartStudio(); }, true); stopButton = ButtonText("Pause PC effects", StopPlayback);
            var bottom = Column(); bottom.Controls.Add(Row(LabelText("FPS cap"), fpsBox, LabelText("Brightness"), brightness, applyButton, stopButton, ButtonText("Test pulse", PreviewPulse), ButtonText("Import profile", ImportProfile), ButtonText("Export saved", ExportProfile)));
            playKeyboardButton = ButtonText("Play on keyboard", async delegate { await RunOnboard(false); });
            saveKeyboardButton = ButtonText("Save to keyboard", async delegate { await RunOnboard(true); }, true);
            bottom.Controls.Add(Row(playKeyboardButton, saveKeyboardButton, ButtonText("Verify keyboard profile", async delegate { await VerifyOnboard(); }), ButtonText("Open profile folder", delegate { System.Diagnostics.Process.Start(dataPath); })));
            profileLocationLabel = LabelText("PC profiles: " + ProfilePath, 920); profileLocationLabel.Height = 25; profileLocationLabel.AutoEllipsis = true; bottom.Controls.Add(profileLocationLabel);
            inputLabel = LabelText("Key response is off.", 380); inputButton = ButtonText("Enable key response", delegate { if (input.IsRunning) { input.Stop(); pulses.Clear(); inputLabel.Text = input.Status; inputButton.Text = "Enable key response"; UpdateControls(); } else EnableInput(); });
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
            p.Controls.Add(Row(ButtonText("Save this manual profile to keyboard", async delegate { await RunOnboard(true, true); })));
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
            p.Controls.Add(LabelText("Persistent lighting v1.0 uses the same firmware on Mac and PC. Profile upload and firmware updates require wired USB."));
            p.Controls.Add(LabelText("CPU temperature requires a separate sensor provider. Current LibreHardwareMonitor uses local logs; older WMI providers also work.", 760));
            p.Controls.Add(Row(ButtonText("CPU setup…", ShowCpuSetup), ButtonText("Choose CPU log folder…", ChooseCpuLogFolder)));
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
            layersBox.SelectedIndex = profile.layers.Count == 0 ? -1 : Math.Max(0, Math.Min(profile.layers.Count - 1, selection)); loading = false; LoadEditor();
        }
        private void LoadEditor()
        {
            if (loading) return;
            bool hasLayer = layersBox.SelectedIndex >= 0;
            foreach (Control control in new Control[] { layerName, layerEnabled, effectBox, blendBox, speed, intensity, opacity, sensitivity, cold, hot, affectAll, colorButton }) control.Enabled = hasLayer;
            if (!hasLayer) { layerName.Text = ""; UpdateSelection(); effectHint.Text = "Add an effect or load a preset to begin. Saving now turns the keyboard lighting off."; return; }
            loading = true;
            var l = Selected; layerName.Text = l.name; layerEnabled.Checked = l.enabled; effectBox.SelectedIndex = Math.Max(0, Array.IndexOf(effectIds, l.settings.effect)); blendBox.SelectedIndex = l.blendMode == "additive" ? 1 : 0;
            speed.Value = (decimal)l.settings.speed; intensity.Value = (decimal)l.settings.intensity * 100; opacity.Value = (decimal)l.opacity * 100;
            sensitivity.Value = (decimal)l.settings.musicSensitivity; cold.Value = (decimal)l.settings.temperatureCold; hot.Value = (decimal)l.settings.temperatureHot;
            affectAll.Checked = l.affectAllKeys; colorButton.BackColor = Color.FromArgb(l.settings.color.r, l.settings.color.g, l.settings.color.b); colorButton.Text = l.settings.color.ToString(); colorButton.ForeColor = l.settings.color.r + l.settings.color.g + l.settings.color.b > 380 ? Color.Black : Color.White;
            loading = false; UpdateSelection(); UpdateEffectHint();
        }
        private void SaveEditor()
        {
            if (loading || layersBox.SelectedIndex < 0) return;
            var l = Selected; string nextEffect = effectIds[Math.Max(0, effectBox.SelectedIndex)];
            string nextName = layerName.Text;
            if (nextEffect != l.settings.effect && LayerNames.IsAutomatic(nextName, l.settings.effect))
            {
                nextName = LayerNames.Next(nextEffect, profile.layers, l); loading = true; layerName.Text = nextName; loading = false;
            }
            if (new[]{"matrixRain","spacedMatrixRain","matrixKeyRain"}.Contains(nextEffect) && l.settings.effect != nextEffect) l.settings.color = new RGB(0, 255, 32);
            l.name = nextName; l.enabled = layerEnabled.Checked; l.settings.effect = nextEffect; l.blendMode = blendBox.SelectedIndex == 1 ? "additive" : "normal";
            l.settings.speed = (double)speed.Value; l.settings.intensity = (double)intensity.Value / 100; l.opacity = (double)opacity.Value / 100;
            l.settings.musicSensitivity = (double)sensitivity.Value; l.settings.temperatureCold = (double)cold.Value; l.settings.temperatureHot = (double)hot.Value; l.affectAllKeys = affectAll.Checked;
            layersBox.Invalidate(); UpdateSelection(); UpdateEffectHint();
        }
        private void PickColor()
        {
            using (var d = new ColorDialog { FullOpen = true, Color = Color.FromArgb(Selected.settings.color.r, Selected.settings.color.g, Selected.settings.color.b) })
                if (d.ShowDialog(this) == DialogResult.OK) { Selected.settings.color = new RGB(d.Color.R, d.Color.G, d.Color.B); LoadEditor(); }
        }
        private void AddLayer() { if (profile.layers.Count >= 16) return; var l = new LightingLayer(); l.settings.effect = "staticColor"; l.name = LayerNames.Next(l.settings.effect, profile.layers); profile.layers.Insert(0, l); LoadLayers(0); }
        private void DuplicateLayer() { if (profile.layers.Count == 0 || profile.layers.Count >= 16) return; var l = Selected.Clone(); l.id = Guid.NewGuid().ToString(); l.name = LayerNames.IsAutomatic(l.name, l.settings.effect) ? LayerNames.Next(l.settings.effect, profile.layers) : (l.name.Length > 73 ? l.name.Substring(0, 73) : l.name) + " copy"; int index = layersBox.SelectedIndex; profile.layers.Insert(index, l); LoadLayers(index); }
        private void UpdateEffectHint()
        {
            if (effectHint == null) return;
            string effect = Selected.settings.effect;
            effectHint.Text = effect == "cpuTemperature" ? "Requires LibreHardwareMonitor + fresh sensor logs (or a WMI provider). See Manual lighting > CPU setup. No readings = no color." :
                effect == "radar" ? "Radar runs with Play from PC. Use Color and Speed to adjust its rotating sweep and fading trail." :
                effect == "adaptiveMusic" ? "Music layers require Play from PC and react to Windows playback audio." :
                effect == "spacedMatrixRain" ? "Fixed key columns carry white heads and fading colored trails; every other column always stays dark. Adjust Speed and Color. Included in firmware 1.0." :
                effect == "matrixKeyRain" ? "Each selected key starts a falling trail at the top of its fixed column. Every column can respond. Affect all keys lets the trail reach beyond the selected triggers. Included in firmware 1.0." :
                effect == "matrixRain" ? "White heads, colored fading tails and moving dark spaces, matching the video rotated vertically. Staggered columns loop downward. Adjust Speed and Color. Included in firmware 1.0." :
                effect == "keyToggle" ? "Press once for on, release, then press again for off. Holding does not repeat. Included in firmware 1.0." :
                effect == "keyHold" ? "On while physically pressed; off immediately on release. Affect all keys lights the board while any selected trigger is held." :
                Array.IndexOf(OnboardProfile.EffectIds, effect) >= 19 ? "New press effect • included in firmware 1.0. Speed changes travel/fade; Affect all keys expands output, keeping selected triggers." :
                LightingEngine.RequiresKeyPresses(effect) ? "Keyboard playback reads keys itself. For Play from PC, enable key response. Key hold follows press and release." : "Play on keyboard previews without saving. Save to keyboard keeps this layout after power-off.";
        }
        private void ShowCpuSetup() { MessageBox.Show(this, CpuSensorLog.SetupHelp, "CPU temperature setup", MessageBoxButtons.OK, MessageBoxIcon.Information); }
        private void ChooseCpuLogFolder()
        {
            using (var dialog = new FolderBrowserDialog { Description = "Choose the LibreHardwareMonitor folder containing its sensor CSV logs.", SelectedPath = liveInputs.CpuLogDirectory })
                if (dialog.ShowDialog(this) == DialogResult.OK)
                    try { if (dialog.SelectedPath.StartsWith(@"\\")) throw new IOException("Choose a local folder, not a network share."); PersistJson.Save(Path.Combine(dataPath, "sensor-provider.json"), new { logDirectory = dialog.SelectedPath }); liveInputs.CpuLogDirectory = dialog.SelectedPath; if (!preview) liveInputs.RefreshTemperature(); Status("CPU log folder saved. Keep LibreHardwareMonitor running with 1-second logging enabled."); }
                    catch (Exception ex) { Status(ex.Message); }
        }
        private void LoadPreset()
        {
            var next = LightingPresets.Create(presetBox.Text); next.Validate(keys);
            playing = false; generation++; liveInputs.StopAudio(); input.Stop(); pulses.Clear();
            undoLighting = profile.Clone(); profile = next; brightness.Value = next.settings.brightness; fpsBox.SelectedItem = (next.frameRate ?? 60).ToString();
            loading = true; restoreBox.Checked = next.restoreOnReconnect; loading = false;
            LoadLayers(0); UpdateControls(); Status(presetBox.Text + " loaded as a draft. Choose Play on keyboard, Save to keyboard or Play from PC. Export draft JSON shares your edits.");
        }
        private void ExportDraftProfile()
        {
            using (var d = new SaveFileDialog { Filter = "Lighting profile (*.json)|*.json", FileName = "gmk104-profile.json" })
                if (d.ShowDialog(this) == DialogResult.OK) try { var draft = profile.Clone(); draft.mapping = map.Clone(); draft.Validate(keys); draft.Save(d.FileName); Status("Draft profile and key mapping exported to " + d.FileName); } catch (Exception ex) { Status(ex.Message); }
        }
        private void RemoveLayer() { if (profile.layers.Count == 0) return; undoLighting = profile.Clone(); int i = layersBox.SelectedIndex; profile.layers.RemoveAt(i); LoadLayers(i); }
        private void MoveLayer(int direction) { int a = layersBox.SelectedIndex, b = a + direction; if (a < 0 || b < 0 || b >= profile.layers.Count) return; var l = profile.layers[a]; profile.layers[a] = profile.layers[b]; profile.layers[b] = l; LoadLayers(b); }
        private void ClearAllEffects() { if (profile.layers.Count == 0) return; undoLighting = profile.Clone(); profile.layers.Clear(); LoadLayers(0); Status("All effects removed from the draft. Undo restores them. Save to keyboard to turn its saved lighting off."); }
        private void UndoLighting() { if (undoLighting == null) return; var previous = profile; profile = undoLighting; undoLighting = previous; LoadLayers(0); Status("Previous lighting draft restored. Apply or save when ready."); }
        private void SetSelection(List<string> ids) { if (profile.layers.Count == 0) return; Selected.keyIDs = ids; UpdateSelection(); }
        private void UpdateSelection()
        {
            selecting = tabs.SelectedIndex == 0 && profile.layers.Count > 0;
            selectedLabel.Text = profile.layers.Count == 0 ? "No effect selected" : Selected.keyIDs == null ? "All 104 keys" : Selected.keyIDs.Count + " selected / trigger keys";
            chooseButton.Text = "Select on keyboard"; chooseButton.Enabled = selecting;
            keyboard.SelectionEnabled = selecting;
            keyboard.Selection = selecting && Selected.keyIDs != null ? new HashSet<string>(Selected.keyIDs) : null; keyboard.Invalidate();
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
            if (id != "Pause" && !heldKeys.Add(id)) return;
            if (!toggledKeys.Add(id)) toggledKeys.Remove(id);
            pulses.Add(new KeyPulse(id, Now)); if (pulses.Count > 48) pulses.RemoveRange(0, pulses.Count - 48);
            inputLabel.Text = "Key response enabled • Last key: " + id;
            if (tabs.SelectedIndex == 2 && ContainsFocus && !busy && illuminated >= 0)
            { selectedMappingKey = id; mappingLabel.Text = "Selected: " + id + " • Lit LED " + illuminated; if (quickMapping.Checked) SaveMappingCorrection(); }
        }
        private void Released(string id)
        {
            if (closing) return;
            if (InvokeRequired) { BeginInvoke(new Action<string>(Released), id); return; }
            heldKeys.Remove(id);
        }
        private void PreviewPulse()
        {
            if (!playing || applied == null) { Status("Apply a reactive layer first, then test its pulse."); return; }
            var layer = applied.layers.FirstOrDefault(l => l.id == Selected.id && l.enabled && l.opacity > 0 && LightingEngine.RequiresKeyPresses(l.settings.effect));
            if (layer == null) layer = applied.layers.FirstOrDefault(l => l.enabled && l.opacity > 0 && LightingEngine.RequiresKeyPresses(l.settings.effect));
            string id = layer == null ? null : map.mappings.Where(m => m.confirmed && m.ledIndex.HasValue && layer.AcceptsTrigger(m.keyId)).Select(m => m.keyId).FirstOrDefault();
            if (id == null) { Status("No mapped trigger keys are enabled in the running reactive layers."); return; }
            Pressed(id);
            var release = new System.Windows.Forms.Timer { Interval = 250 };
            release.Tick += (s, e) => { release.Stop(); release.Dispose(); Released(id); }; release.Start();
        }
        private void EnableInput()
        {
            if (client == null) { Status("Connect the keyboard first."); return; }
            bool started = input.Start(client.Transport.ConnectionName, client.Transport.DeviceIdentity);
            inputLabel.Text = input.Status; inputButton.Text = started ? "Disable key response" : "Enable key response"; UpdateControls();
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
                client = candidate; candidate = null; onboard = result.Onboard ?? new OnboardCapabilities(); ShowResult(result); Status("Connected over " + client.Transport.ConnectionName + ". Firmware identity verified.");
            }
            catch (Exception ex) { if (candidate != null) candidate.Dispose(); Status(ex.Message); }
            finally { busy = false; UpdateControls(); }
            if (client != null && savedSleep.HasValue) { int seconds = savedSleep.Value; await DeviceAction("Restoring wireless sleep setting…", c => { if (c.ReadSleepSeconds().HasValue) c.SetSleepSeconds(seconds); return new DeviceResult { State = c.Read(), Sleep = c.ReadSleepSeconds() }; }, false); }
            if (client != null && !onboardPlaying && savedProfile.restoreOnReconnect && savedProfile.resume) await RestoreProfile();
            if (onboardPlaying) Status("The keyboard is playing its own profile. Your PC draft has not replaced it.");
        }
        private async Task Disconnect()
        {
            retryWanted = false; playing = false; generation++; busy = true; UpdateControls(); input.Stop(); liveInputs.StopAudio();
            await io.WaitAsync(); try { if (client != null) client.Dispose(); client = null; } finally { io.Release(); busy = false; }
            beforeMapping = null; beforeMappingEffect = -1; illuminated = -1; onboard = new OnboardCapabilities(); onboardPlaying = false; heldKeys.Clear(); toggledKeys.Clear(); UpdateControls(); Status("Disconnected. Your saved profile is unchanged.");
        }
        private DeviceResult ReadResult(RGBClient c, bool fresh = true)
        {
            var s = c.Read(); return new DeviceResult { State = s, Frame = s.Effect == 19 ? (fresh ? c.ReadFrame() : c.Shadow ?? c.ReadFrame()) : null, Onboard = fresh ? new OnboardUploader(c.Transport).SupportedModes() : null };
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
            if (result.Onboard != null) onboard = result.Onboard;
            if (result.State != null) onboardPlaying = result.State.Effect == 20;
            if (result.Frame != null) { keyboard.Frame = result.Frame; keyboard.Invalidate(); }
            if (result.State != null) frameLabel.Text = String.Format("{0} • Brightness {1} • {2}/104 keys mapped", result.State.Effect == 19 ? "Direct RGB" : result.State.Effect == 20 ? "Playing on keyboard" : "Built-in effect " + result.State.Effect, result.State.Brightness, map.mappings.Count(m => m.confirmed));
            if (result.Sleep.HasValue) sleepLabel.Text = "Verified sleep setting: " + (result.Sleep.Value == 0 ? "Never" : result.Sleep.Value / 60.0 + " minutes");
        }
        private async Task StartStudio(LightingProfile restored = null)
        {
            if (busy) return;
            if (restored == null) SaveEditor(); LightingProfile requested = restored == null ? profile.Clone() : restored.Clone(); requested.mode = "studio"; requested.resume = true;
            if (restored == null) { requested.frameRate = Int32.Parse(fpsBox.Text); requested.settings.brightness = (int)brightness.Value; requested.restoreOnReconnect = restoreBox.Checked; }
            try { requested.Validate(keys); } catch (Exception ex) { Status(ex.Message); return; }
            heldKeys.Clear(); toggledKeys.Clear(); pulses.Clear();
            RGB[] frame = LightingEngine.Render(requested.layers, keys, map, new List<KeyPulse>(pulses), Now, liveInputs.Snapshot(Now), new HashSet<string>(heldKeys), new HashSet<string>(toggledKeys));
            onboardPlaying = false;
            bool okay = await DeviceAction("Starting layers and verifying all 104 LEDs…", c => { c.SetBrightness(requested.settings.brightness); c.SetFrame(frame); return new DeviceResult { State = c.Read(), Frame = c.Shadow }; });
            if (!okay) return;
            if (restored == null) { profile = requested; SaveProfile(); } else { savedProfile = requested.Clone(); SaveProfile(false); }
            applied = requested.Clone(); beforeMappingEffect = -1; beforeMapping = null;
            playing = true; previousFrame = Now; nextFrame = Now; StartInputs(); UpdateControls();
        }
        private async Task RunOnboard(bool persistent, bool manual = false)
        {
            if (busy || client == null) { Status("Connect by wired USB first."); return; }
            if (!manual) SaveEditor();
            LightingProfile requested = manual ? savedProfile.Clone() : profile.Clone();
            if (!manual) { requested.mode = "studio"; requested.frameRate = Int32.Parse(fpsBox.Text); requested.settings.brightness = (int)brightness.Value; }
            requested.mapping = map.Clone(); requested.resume = false;
            OnboardProfile encoded;
            try { encoded = OnboardProfile.Compile(requested, keys, map, factoryMap); }
            catch (Exception ex) { Status(ex.Message); return; }
            OnboardReceipt receipt = null;
            bool okay = await DeviceAction(persistent ? "Saving and verifying the keyboard profile…" : "Sending a temporary profile to the keyboard…", c => {
                receipt = new OnboardUploader(c.Transport).Transfer(encoded, persistent);
                return ReadResult(c);
            });
            if (!okay) return;
            playing = false; input.Stop(); heldKeys.Clear(); toggledKeys.Clear(); pulses.Clear(); liveInputs.StopAudio(); onboardPlaying = true;
            if (!manual) profile = requested.Clone(); savedProfile = requested.Clone(); SaveProfile(false); applied = requested.Clone();
            inputLabel.Text = "Key effects run directly on the keyboard."; inputButton.Text = "Enable key response";
            Status(String.Format("{0} • {1} bytes • CRC {2:X8} • complete readback verified. {3}", persistent ? "Saved to keyboard" : "Playing on keyboard temporarily", receipt.Length, receipt.CRC, persistent ? "Turn the keyboard fully off and on to check persistence." : "This preview expires when the keyboard loses power."));
            profileLocationLabel.Text = "PC backup: " + ProfilePath + (persistent ? " • Also saved on the keyboard" : " • Keyboard preview is temporary"); UpdateControls();
        }
        private async Task VerifyOnboard()
        {
            byte[] bytes = null;
            if (await DeviceAction("Reading the complete keyboard profile…", c => { bytes = new OnboardUploader(c.Transport).ReadActive(); return ReadResult(c); }, false))
                Status(String.Format("Keyboard profile verified • {0} bytes • CRC {1:X8}. To check persistence, verify again after turning the keyboard fully off and on.", bytes.Length, OnboardProfile.CRC32(bytes)));
        }
        private async Task RestoreProfile()
        {
            if (savedProfile.mode == "studio") { await StartStudio(savedProfile); return; }
            var p = savedProfile.Clone();
            if (await DeviceAction("Restoring saved lighting…", c => { c.SetBrightness(p.settings.brightness); if (p.mode == "frame") c.SetFrame(p.colors); else if (p.builtInEffect == 20) c.SelectOnboardEffect(); else c.SetEffect(p.builtInEffect); return ReadResult(c, false); })) { savedProfile.resume = true; SaveProfile(false); }
        }
        private async void Animate(object sender, EventArgs e)
        {
            if (!playing || busy || frameInFlight || closing || client == null || applied == null || Now < nextFrame) return;
            frameInFlight = true; int epoch = generation; RGBClient target = client; double now = Now;
            if (target.Transport.UsesRollingAnimationVerification)
            {
                double reactiveSpeed = applied.layers.Where(l => l.enabled && l.opacity > 0 && LightingEngine.RequiresKeyPresses(l.settings.effect)).Select(l => l.settings.speed).DefaultIfEmpty(1).Max();
                List<KeyPulse> adjusted = LightingEngine.AdjustPulses(pulses, previousFrame, now, .1 / reactiveSpeed); pulses.Clear(); pulses.AddRange(adjusted);
            }
            previousFrame = now; pulses.RemoveAll(p => now - p.time > 20 || p.time > now + 1);
            RGB[] frame = LightingEngine.Render(applied.layers, keys, map, new List<KeyPulse>(pulses), now, liveInputs.Snapshot(now), new HashSet<string>(heldKeys), new HashSet<string>(toggledKeys));
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
            heldKeys.Clear(); toggledKeys.Clear();
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
                try { var p = LightingProfile.Load(d.FileName); p.Validate(keys); StopPlayback(); if (p.mapping != null && !SaveMap(p.mapping.Clone())) return; profile = p; profile.layers = p.StudioLayers; profile.resume = false; brightness.Value = profile.settings.brightness; fpsBox.SelectedItem = (p.frameRate ?? 60).ToString(); builtin.Value = Math.Min(18, p.builtInEffect); loading = true; restoreBox.Checked = p.restoreOnReconnect; loading = false; LoadLayers(0); SaveProfile(); Status(p.mode == "studio" ? "Profile opened. Choose Play on keyboard, Save to keyboard or Play from PC." : "Profile imported. Use Apply imported / saved profile in Manual lighting."); } catch (Exception ex) { loading = false; Status(ex.Message); }
        }
        private void ExportProfile() { using (var d = new SaveFileDialog { Filter = "Lighting profile (*.json)|*.json", FileName = "lighting-profile.json" }) if (d.ShowDialog(this) == DialogResult.OK) try { var portable = savedProfile.Clone(); portable.mapping = map.Clone(); portable.Save(d.FileName); Status("Profile exported to " + d.FileName); } catch (Exception ex) { Status(ex.Message); } }
        private void Status(string text) { if (!closing && statusLabel != null) statusLabel.Text = text; }
        private void UpdateControls()
        {
            if (closing || tabs == null) return; tabs.Enabled = !busy; connectButton.Enabled = !busy; transportBox.Enabled = !busy && client == null;
            connectButton.Text = client == null ? "Connect" : "Disconnect"; connectionLabel.Text = client == null ? "● Offline" : "● " + client.Transport.ConnectionName + " connected";
            connectionLabel.ForeColor = client == null ? Color.Gray : accent; applyButton.Enabled = client != null && !busy; stopButton.Enabled = playing || frameInFlight;
            playKeyboardButton.Enabled = client != null && !busy && onboard.Volatile;
            saveKeyboardButton.Enabled = client != null && !busy && onboard.Persistent;
            inputButton.BackColor = input != null && input.IsRunning ? accent : Color.FromArgb(34, 43, 53);
            inputButton.ForeColor = input != null && input.IsRunning ? Color.FromArgb(9, 25, 17) : ink;
        }
        private void OnClosing(object sender, FormClosingEventArgs e)
        {
            if (!preview && !quitting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); tray.ShowBalloonTip(2500, "GMK104 Lighting Studio", "Lighting continues in the system tray. Right-click the tray icon to quit.", ToolTipIcon.Info); return; }
            if (busy || frameInFlight) { e.Cancel = true; playing = false; generation++; Status("Finishing the current keyboard operation before quitting…"); var timer = new System.Windows.Forms.Timer { Interval = 250 }; timer.Tick += delegate { if (!busy && !frameInFlight) { timer.Stop(); timer.Dispose(); Close(); } }; timer.Start(); return; }
            closing = true; generation++; animation.Stop(); reconnect.Stop(); sensors.Stop(); input.Dispose(); liveInputs.Dispose(); if (client != null) client.Dispose(); tray.Visible = false; tray.Dispose();
        }
        protected override void WndProc(ref Message m) { if (input != null) input.ProcessMessage(ref m); base.WndProc(ref m); }
        internal void SelectPreviewTab(int index) { tabs.SelectedIndex = Math.Max(0, Math.Min(2, index)); }
        private sealed class DeviceResult { public RGBState State; public RGB[] Frame; public int? Sleep; public OnboardCapabilities Onboard; }
        public sealed class SleepPreference { public int sleepSeconds; }
    }
}
