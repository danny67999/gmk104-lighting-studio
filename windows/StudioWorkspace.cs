using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace Gmk104LightingStudio
{
    public sealed partial class StudioForm
    {
        private Panel workspace, gallery, settingsPage, mappingPage, body, keyboardHost, mappingKeyboardHost, editorPanel;
        private FlowLayoutPanel layerCards, galleryCards;
        private Label pageTitle, playbackLabel, actionNotice, sidebarInput, layerCount, emptyEditor;
        private Button addEffectButton, presetButton, profileButton, pcPlaybackButton, removeAllButton, undoButton;
        private StudioButton[] navigation;
        private readonly Dictionary<string, StudioCard> cardById = new Dictionary<string, StudioCard>();
        private readonly List<EffectThumbnail> thumbnails = new List<EffectThumbnail>();
        private readonly System.Windows.Forms.Timer previewTimer = new System.Windows.Forms.Timer { Interval = 50 };
        private ComboBox categoryBox;
        private TextBox searchBox;
        private Control musicOptions, temperatureOptions;
        private readonly string[] featured = { "spacedMatrixRain", "matrixKeyRain", "matrixRain", "rainbowRipple", "wave", "keyToggle", "fire", "crossRipple" };

        private Label LabelText(string text, int width = 0)
        {
            return new Label { Text = text, AutoSize = width == 0, Width = width, Height = 25, TextAlign = ContentAlignment.MiddleLeft, Margin = new Padding(4, 6, 4, 2), ForeColor = ink };
        }
        private Label Heading(string text, float size = 12)
        {
            return new Label { Text = text, AutoSize = false, Height = 34, Font = new Font(Font.FontFamily, size, FontStyle.Bold), ForeColor = ink, Margin = new Padding(4, 6, 4, 5), TextAlign = ContentAlignment.MiddleLeft };
        }
        private Button ButtonText(string text, Action action, bool primary = false)
        {
            var b = new StudioButton { Text = text, Primary = primary }; b.Click += delegate { action(); }; return b;
        }
        private ComboBox Combo(string[] values, int width = 130)
        {
            var c = new StudioCombo { DropDownStyle = ComboBoxStyle.DropDownList, Width = width, BackColor = StudioTheme.Card, ForeColor = ink, Margin = new Padding(4, 6, 4, 4), FlatStyle = FlatStyle.Flat, DrawMode = DrawMode.OwnerDrawFixed, ItemHeight = 21 };
            c.DrawItem += delegate(object sender, DrawItemEventArgs e) { if (e.Index < 0) return; e.DrawBackground(); TextRenderer.DrawText(e.Graphics, c.Items[e.Index].ToString(), Font, e.Bounds, ink, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix); e.DrawFocusRectangle(); };
            c.Items.AddRange(values); c.SelectedIndex = 0; return c;
        }
        private NumericUpDown Number(decimal min, decimal max, decimal value, int decimals = 0, decimal increment = 1)
        {
            return new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Max(min, Math.Min(max, value)), DecimalPlaces = decimals, Increment = increment, Width = 82, BackColor = StudioTheme.Card, ForeColor = ink, Margin = new Padding(4, 7, 4, 4), BorderStyle = BorderStyle.FixedSingle };
        }
        private FlowLayoutPanel Row(params Control[] controls)
        {
            var p = new FlowLayoutPanel { AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, WrapContents = true, Margin = new Padding(0, 2, 0, 3) }; p.Controls.AddRange(controls); return p;
        }
        private FlowLayoutPanel Column()
        {
            var p = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(8), Margin = new Padding(0) };
            p.Layout += delegate {
                int w = Math.Max(100, p.ClientSize.Width - p.Padding.Horizontal - SystemInformation.VerticalScrollBarWidth - 4);
                foreach (Control c in p.Controls) if (c.Width != w) c.Width = w;
            };
            return p;
        }
        private Panel Field(string text, Control control)
        {
            var row = new Panel { Height = 40, Margin = new Padding(0, 0, 0, 2) };
            var label = LabelText(text); label.AutoSize = false; label.SetBounds(0, 0, 90, 36);
            control.Anchor = AnchorStyles.Top | AnchorStyles.Right; control.Margin = new Padding(0); row.Controls.Add(label); row.Controls.Add(control);
            int preferredWidth = control.Width; row.Layout += delegate { control.Width = Math.Max(50, Math.Min(preferredWidth, row.ClientSize.Width - 96)); control.Location = new Point(Math.Max(94, row.ClientSize.Width - control.Width), 7); };
            return row;
        }
        private FlowLayoutPanel Section(FlowLayoutPanel parent, string title)
        {
            parent.Controls.Add(Heading(title));
            var content = Column(); content.Dock = DockStyle.None; content.AutoScroll = false; content.AutoSize = true; content.AutoSizeMode = AutoSizeMode.GrowAndShrink; content.BackColor = StudioTheme.Card; content.Padding = new Padding(14);
            parent.Controls.Add(content); return content;
        }
        private void BuildUI()
        {
            var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, Margin = new Padding(0), Padding = new Padding(0) };
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 200)); root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); Controls.Add(root);
            var side = new Panel { Dock = DockStyle.Fill, BackColor = StudioTheme.Sidebar, Padding = new Padding(12) }; root.Controls.Add(side, 0, 0);
            var sideLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, Margin = new Padding(0) };
            sideLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            sideLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 62)); sideLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 165)); sideLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); sideLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 112)); side.Controls.Add(sideLayout);
            var brand = Heading("Lighting Studio", 14); brand.Dock = DockStyle.Fill; sideLayout.Controls.Add(brand, 0, 0);
            navigation = new StudioButton[3];
            var nav = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(0, 5, 0, 0) };
            string[] names = { "▱   My Lighting", "▦   Effects", "⌨   Keyboard" };
            for (int i = 0; i < 3; i++) { int index = i; var button = new StudioButton { Text = names[i], Width = 166, Height = 42, AutoSize = false, Navigation = true, AccessibleName = names[i].Substring(4) }; button.Click += delegate { Navigate(index); }; navigation[i] = button; nav.Controls.Add(button); }
            sideLayout.Controls.Add(nav, 0, 1);
            var sideStatus = new Panel { Dock = DockStyle.Fill };
            connectionLabel = LabelText("GMK104 · Offline", 164); connectionLabel.SetBounds(3, 6, 164, 40);
            sidebarInput = LabelText("PC key response is off", 164); sidebarInput.ForeColor = StudioTheme.Secondary; sidebarInput.SetBounds(3, 45, 164, 42); sidebarInput.Cursor = Cursors.Hand; sidebarInput.Click += delegate { Navigate(2); };
            sideStatus.Controls.Add(connectionLabel); sideStatus.Controls.Add(sidebarInput); sideLayout.Controls.Add(sideStatus, 0, 3);
            var main = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Margin = new Padding(0), Padding = new Padding(0) };
            main.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); main.RowStyles.Add(new RowStyle(SizeType.Absolute, 70)); main.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); main.RowStyles.Add(new RowStyle(SizeType.Absolute, 122)); root.Controls.Add(main, 1, 0);
            var header = new Panel { Dock = DockStyle.Fill, Padding = new Padding(22, 14, 22, 12) };
            pageTitle = Heading("My Lighting", 18); pageTitle.Dock = DockStyle.Fill;
            var actions = new FlowLayoutPanel { Dock = DockStyle.Right, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Width = 460 };
            presetButton = ButtonText("Presets ▾", ShowPresets); addEffectButton = ButtonText("+ Add Effect", delegate { Navigate(1); }); profileButton = ButtonText("Profiles ▾", ShowProfiles);
            connectButton = ButtonText("Connect", async delegate { if (client == null) await Connect(); else await Disconnect(); });
            actions.Controls.AddRange(new Control[] { presetButton, addEffectButton, profileButton, connectButton }); header.Controls.Add(pageTitle); header.Controls.Add(actions); main.Controls.Add(header, 0, 0);
            body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(22, 0, 22, 8), Margin = new Padding(0) }; main.Controls.Add(body, 0, 1);
            workspace = new Panel { Dock = DockStyle.Fill }; gallery = new Panel { Dock = DockStyle.Fill, Visible = false }; settingsPage = new Panel { Dock = DockStyle.Fill, Visible = false }; mappingPage = new Panel { Dock = DockStyle.Fill, Visible = false };
            body.Controls.AddRange(new Control[] { workspace, gallery, settingsPage, mappingPage });
            keyboard = new KeyboardView { Keys = keys, Mapping = map, Font = new Font(Font.FontFamily, 8), BackColor = surface }; keyboard.KeyClicked += ClickKey; keyboard.SelectionChanged += SetSelection;
            BuildWorkspace(); BuildGallery(); BuildSettings();
            var mappingLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3 };
            mappingLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42)); mappingLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 250)); mappingLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            mappingLayout.Controls.Add(ButtonText("‹ Done mapping", delegate { Navigate(2); }), 0, 0);
            mappingKeyboardHost = new Panel { Dock = DockStyle.Fill }; mappingLayout.Controls.Add(mappingKeyboardHost, 0, 1); var mappingControls = new Panel { Dock = DockStyle.Fill }; BuildMapping(mappingControls); mappingLayout.Controls.Add(mappingControls, 0, 2); mappingPage.Controls.Add(mappingLayout);
            BuildPlaybackBar(main);
            tray = new NotifyIcon { Text = "GMK104 Lighting Studio", Icon = Icon ?? SystemIcons.Application, Visible = !preview };
            tray.DoubleClick += delegate { Show(); WindowState = FormWindowState.Normal; Activate(); };
            var menu = new ContextMenuStrip(); menu.Items.Add("Open Lighting Studio", null, delegate { Show(); WindowState = FormWindowState.Normal; Activate(); }); menu.Items.Add("Stop PC playback", null, delegate { StopPlayback(); }); menu.Items.Add("Quit", null, delegate { quitting = true; Close(); }); tray.ContextMenuStrip = menu;
            previewTimer.Tick += delegate { RenderPreviews(); }; previewTimer.Start(); Navigate(0);
        }
        private void BuildWorkspace()
        {
            var split = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, Margin = new Padding(0) };
            split.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); split.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 300)); split.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); workspace.Controls.Add(split);
            var left = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, Padding = new Padding(0, 0, 18, 0), Margin = new Padding(0) };
            left.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 40)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 220)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 42)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 46)); left.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); split.Controls.Add(left, 0, 0);
            selectedLabel = LabelText("All 104 keys", 180); selectedLabel.Dock = DockStyle.Left;
            chooseButton = ButtonText("Select ▾", ShowSelectionMenu); chooseButton.Dock = DockStyle.Right; var selectionRow = new Panel { Dock = DockStyle.Fill }; selectionRow.Controls.Add(selectedLabel); selectionRow.Controls.Add(chooseButton); left.Controls.Add(selectionRow, 0, 0);
            keyboardHost = new Panel { Dock = DockStyle.Fill }; keyboardHost.Controls.Add(keyboard); left.Controls.Add(keyboardHost, 0, 1);
            var help = LabelText("Click or drag across keys. Drag from a gap for a box. Ctrl-click tests a key.", 200); help.Dock = DockStyle.Fill; help.ForeColor = StudioTheme.Secondary; left.Controls.Add(help, 0, 2);
            layerCount = Heading("Layers", 12); layerCount.Dock = DockStyle.Left;
            removeAllButton = ButtonText("Remove All", ClearAllEffects); undoButton = ButtonText("Undo", UndoLighting);
            var layerActions = new FlowLayoutPanel { Dock = DockStyle.Right, Width = 200, WrapContents = false }; layerActions.Controls.AddRange(new Control[] { undoButton, removeAllButton });
            var layersHeading = new Panel { Dock = DockStyle.Fill }; layersHeading.Controls.Add(layerCount); layersHeading.Controls.Add(layerActions); left.Controls.Add(layersHeading, 0, 3);
            layerCards = Column(); layerCards.Padding = new Padding(0); left.Controls.Add(layerCards, 0, 4);
            var inspector = new StudioCard { Dock = DockStyle.Fill, Padding = new Padding(12) }; split.Controls.Add(inspector, 1, 0);
            var inspectorLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Margin = new Padding(0) };
            inspectorLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); inspectorLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 38)); inspectorLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); inspector.Controls.Add(inspectorLayout);
            var title = Heading("Effect settings", 12); title.Dock = DockStyle.Fill; inspectorLayout.Controls.Add(title, 0, 0);
            var editorHost = new Panel { Dock = DockStyle.Fill, Margin = new Padding(0) }; inspectorLayout.Controls.Add(editorHost, 0, 1);
            editorPanel = new Panel { Dock = DockStyle.Fill }; editorHost.Controls.Add(editorPanel);
            emptyEditor = LabelText("Add an effect or load a preset to get started.", 220); emptyEditor.Dock = DockStyle.Fill; emptyEditor.ForeColor = StudioTheme.Secondary; emptyEditor.Visible = false; editorHost.Controls.Add(emptyEditor);
            var editor = Column(); editor.Padding = new Padding(0); editorPanel.Controls.Add(editor);
            layerName = new TextBox { Width = 210, BackColor = StudioTheme.Card, ForeColor = ink, BorderStyle = BorderStyle.FixedSingle, MaxLength = 80, AccessibleName = "Layer name" };
            layerEnabled = new StudioToggle { AccessibleName = "Enable selected effect" }; blendBox = Combo(new[] { "Normal", "Add light" }, 130); effectBox = Combo(effectNames, 160);
            colorButton = ButtonText("Color…", PickColor); colorButton.Width = 130;
            speed = Number(.25m, 3, 1, 2, .25m); intensity = Number(0, 100, 100); opacity = Number(0, 100, 100);
            editor.Controls.Add(Heading("Name", 10)); editor.Controls.Add(layerName); editor.Controls.Add(Field("Enabled", layerEnabled)); editor.Controls.Add(Field("Effect", effectBox));
            effectHint = LabelText("", 250); effectHint.Height = 76; effectHint.ForeColor = StudioTheme.Secondary; effectHint.TextAlign = ContentAlignment.TopLeft; editor.Controls.Add(effectHint);
            editor.Controls.Add(Field("Color", colorButton)); editor.Controls.Add(Field("Speed", speed)); editor.Controls.Add(Field("Intensity %", intensity)); editor.Controls.Add(Field("Opacity %", opacity)); editor.Controls.Add(Field("Blend", blendBox));
            affectAll = new CheckBox { Text = "Affect all keys", AutoSize = false, Height = 29, Margin = new Padding(2, 10, 0, 0) }; editor.Controls.Add(affectAll);
            var scope = LabelText("Selected keys trigger reactive effects. Turn this on to let the effect reach other keys.", 250); scope.Height = 48; scope.ForeColor = StudioTheme.Secondary; scope.TextAlign = ContentAlignment.TopLeft; editor.Controls.Add(scope); editor.Controls.SetChildIndex(affectAll, 5); editor.Controls.SetChildIndex(scope, 6);
            sensitivity = Number(.25m, 4, 1, 2, .25m); cold = Number(10, 80, 40); hot = Number(40, 110, 90);
            musicOptions = Field("Sensitivity", sensitivity); temperatureOptions = Row(Field("Blue at °C", cold), Field("Red at °C", hot)); editor.Controls.Add(musicOptions); editor.Controls.Add(temperatureOptions);
            foreach (Control control in new Control[] { layerName, effectBox, blendBox, speed, opacity, intensity, sensitivity, cold, hot, layerEnabled, affectAll })
            {
                var n = control as NumericUpDown; if (n != null) n.ValueChanged += delegate { SaveEditor(); };
                var c = control as ComboBox; if (c != null) c.SelectedIndexChanged += delegate { SaveEditor(); };
                var check = control as CheckBox; if (check != null) check.CheckedChanged += delegate { SaveEditor(); };
                var t = control as TextBox; if (t != null) t.TextChanged += delegate { SaveEditor(); };
            }
            presetBox = Combo(LightingPresets.Names, 155); // A preset is a draft until the user plays or saves it.
        }
        private void BuildGallery()
        {
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2 };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 52)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); gallery.Controls.Add(layout);
            categoryBox = Combo(new[] { "All effects", "Automatic", "On key press", "PC inputs" }, 160);
            searchBox = new TextBox { Width = 215, BackColor = StudioTheme.Card, ForeColor = ink, BorderStyle = BorderStyle.FixedSingle, Margin = new Padding(12, 7, 4, 4), AccessibleName = "Search effects" };
            var filters = Row(categoryBox, LabelText("Search"), searchBox); filters.Dock = DockStyle.Fill; layout.Controls.Add(filters, 0, 0);
            galleryCards = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, Padding = new Padding(0, 6, 0, 6), WrapContents = true };
            layout.Controls.Add(galleryCards, 0, 1); categoryBox.SelectedIndexChanged += delegate { RebuildGallery(); }; searchBox.TextChanged += delegate { RebuildGallery(); }; RebuildGallery();
        }
        private LightingLayer Example(string effect)
        {
            return new LightingLayer(new LightingSettings { effect = effect, color = new[] { "matrixRain", "spacedMatrixRain", "matrixKeyRain" }.Contains(effect) ? new RGB(0, 255, 32) : new RGB(70, 140, 255), speed = 1, intensity = 1 }) { affectAllKeys = LightingEngine.RequiresKeyPresses(effect) };
        }
        private void RebuildGallery()
        {
            if (galleryCards == null) return;
            thumbnails.Clear(); foreach (Control c in galleryCards.Controls.Cast<Control>().ToArray()) c.Dispose(); galleryCards.Controls.Clear();
            int category = categoryBox.SelectedIndex; string query = searchBox.Text.Trim();
            var effects = effectIds.Where(e => (category == 0 || category == 1 && !LightingEngine.RequiresKeyPresses(e) && e != "adaptiveMusic" && e != "cpuTemperature" || category == 2 && LightingEngine.RequiresKeyPresses(e) || category == 3 && (e == "adaptiveMusic" || e == "cpuTemperature" || e == "radar")) && LightingEngine.DisplayName(e).IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0)
                .OrderBy(e => Array.IndexOf(featured, e) < 0 ? 99 : Array.IndexOf(featured, e));
            foreach (string effect in effects)
            {
                string id = effect; var card = new StudioCard { Width = 250, Height = 227, Margin = new Padding(0, 0, 15, 16) };
                var title = Heading(LightingEngine.DisplayName(effect), 11); title.SetBounds(14, 8, 222, 32); card.Controls.Add(title);
                var thumb = new EffectThumbnail { Geometry = keys, Map = map, Layer = Example(effect) }; thumb.SetBounds(14, 47, 222, 94); card.Controls.Add(thumb); thumbnails.Add(thumb);
                var kind = LabelText(LightingEngine.RequiresKeyPresses(effect) ? "On key press" : effect == "adaptiveMusic" || effect == "cpuTemperature" || effect == "radar" ? "PC playback" : "Automatic", 130); kind.SetBounds(14, 153, 222, 23); kind.ForeColor = StudioTheme.Secondary; card.Controls.Add(kind);
                var add = ButtonText("+ Add effect", delegate { AddEffect(id); }); add.SetBounds(14, 181, 222, 34); add.AutoSize = false; add.Enabled = profile.layers.Count < 16; card.Controls.Add(add); galleryCards.Controls.Add(card);
            }
            if (galleryCards.Controls.Count == 0) galleryCards.Controls.Add(LabelText("No effects match your search.", 400));
        }
        private void AddEffect(string effect)
        {
            if (busy || profile.layers.Count >= 16) return;
            undoLighting = profile.Clone(); var layer = Example(effect); layer.name = LayerNames.Next(effect, profile.layers); profile.layers.Insert(0, layer); LoadLayers(0); Navigate(0); Status("Effect added to your draft. Play or save when you’re ready.");
        }
        private void RebuildLayerCards()
        {
            if (layerCards == null) return;
            layerCards.SuspendLayout(); foreach (Control c in layerCards.Controls.Cast<Control>().ToArray()) c.Dispose(); layerCards.Controls.Clear(); cardById.Clear();
            foreach (var layer in profile.layers)
            {
                string id = layer.id; var card = new StudioCard { Height = 77, Margin = new Padding(0, 0, 0, 9), Cursor = Cursors.Hand, Selected = layer.id == Selected.id, AccessibleName = "Edit " + layer.name };
                var title = Heading(layer.name, 10.5f); title.AutoEllipsis = true;
                var detail = LabelText("", 300); detail.ForeColor = StudioTheme.Secondary; detail.AutoEllipsis = true;
                var toggle = new StudioToggle { Checked = layer.enabled, AccessibleName = "Enable " + layer.name };
                var more = ButtonText("···", delegate { SelectLayer(id); ShowLayerMenu(card); }); more.AutoSize = false; more.MinimumSize = Size.Empty; more.Size = new Size(32, 30);
                Action select = delegate { SelectLayer(id); }; card.Click += delegate { select(); }; title.Click += delegate { select(); }; detail.Click += delegate { select(); };
                toggle.CheckedChanged += delegate { var found = profile.layers.FirstOrDefault(l => l.id == id); if (found == null || loading) return; found.enabled = toggle.Checked; if (Selected.id == id) LoadEditor(); RefreshLayerCards(); };
                card.Controls.AddRange(new Control[] { title, detail, toggle, more });
                card.Layout += delegate { title.SetBounds(14, 6, Math.Max(100, card.Width - 118), 30); detail.SetBounds(14, 37, Math.Max(100, card.Width - 118), 24); toggle.Location = new Point(card.Width - 94, 25); more.Location = new Point(card.Width - 46, 23); };
                cardById.Add(id, card); layerCards.Controls.Add(card);
            }
            if (profile.layers.Count == 0) { var empty = LabelText("No effects. Add an effect or choose a preset to start.", 500); empty.Height = 70; empty.ForeColor = StudioTheme.Secondary; layerCards.Controls.Add(empty); }
            layerCards.ResumeLayout(); RefreshLayerCards();
        }
        private void SelectLayer(string id) { int index = profile.layers.FindIndex(l => l.id == id); if (index < 0 || busy) return; selectedLayerIndex = index; LoadEditor(); RefreshLayerCards(); }
        private void RefreshLayerCards()
        {
            if (layerCount == null) return;
            layerCount.Text = "Layers · " + profile.layers.Count; undoButton.Enabled = undoLighting != null && !busy; removeAllButton.Enabled = profile.layers.Count > 0 && !busy;
            foreach (var layer in profile.layers)
            {
                StudioCard card; if (!cardById.TryGetValue(layer.id, out card)) continue;
                card.Selected = layer.id == Selected.id; var labels = card.Controls.OfType<Label>().ToArray(); labels[0].Text = layer.name;
                labels[1].Text = LightingEngine.DisplayName(layer.settings.effect) + " · " + (layer.keyIDs == null ? "All keys" : layer.keyIDs.Count + " keys");
                card.Invalidate();
            }
        }
        private void ShowLayerMenu(Control anchor)
        {
            var menu = new ContextMenuStrip(); menu.Items.Add("Duplicate", null, delegate { DuplicateLayer(); }).Enabled = profile.layers.Count < 16; menu.Items.Add("Move up", null, delegate { MoveLayer(-1); }).Enabled = selectedLayerIndex > 0; menu.Items.Add("Move down", null, delegate { MoveLayer(1); }).Enabled = selectedLayerIndex < profile.layers.Count - 1; menu.Items.Add(new ToolStripSeparator()); menu.Items.Add("Remove effect", null, delegate { RemoveLayer(); }); ShowMenu(menu, anchor);
        }
        private void ShowSelectionMenu()
        {
            var menu = new ContextMenuStrip(); menu.Items.Add("All keys", null, delegate { SetSelection(null); }); menu.Items.Add("No keys", null, delegate { SetSelection(new List<string>()); }); menu.Items.Add("WASD", null, delegate { SetSelection(new List<string> { "KeyW", "KeyA", "KeyS", "KeyD" }); }); menu.Items.Add("Arrow keys", null, delegate { SetSelection(keys.Where(k => k.id.StartsWith("Arrow")).Select(k => k.id).ToList()); }); menu.Items.Add("Number pad", null, delegate { SetSelection(keys.Where(k => k.id.StartsWith("Numpad")).Select(k => k.id).ToList()); }); ShowMenu(menu, chooseButton);
        }
        private void ShowPresets()
        {
            var menu = new ContextMenuStrip(); foreach (string name in LightingPresets.Names) { string choice = name; menu.Items.Add(name, null, delegate { presetBox.SelectedItem = choice; LoadPreset(); Navigate(0); }); } ShowMenu(menu, presetButton);
        }
        private void ShowProfiles()
        {
            var menu = new ContextMenuStrip(); menu.Items.Add("Open profile…", null, delegate { ImportProfile(); Navigate(0); }); menu.Items.Add(new ToolStripSeparator()); menu.Items.Add("Save on this PC", null, delegate { SaveDraftOnPC(); }); menu.Items.Add("Export profile…", null, delegate { ExportDraftProfile(); }); menu.Items.Add("Export last saved profile…", null, delegate { ExportProfile(); }); menu.Items.Add("Show saved profile in Explorer", null, delegate { System.Diagnostics.Process.Start(dataPath); }); ShowMenu(menu, profileButton);
        }
        private void SaveDraftOnPC()
        {
            try { SaveEditor(); var draft = profile.Clone(); draft.mapping = map.Clone(); draft.frameRate = Int32.Parse(fpsBox.Text); draft.settings.brightness = (int)brightness.Value; draft.Validate(keys); draft.Save(ProfilePath); savedProfile = draft; profileLocationLabel.Text = ProfilePath; Status("Profile saved on this PC: " + ProfilePath); }
            catch (Exception error) { Status("Profile could not be saved: " + error.Message); }
        }
        private void ShowMenu(ContextMenuStrip menu, Control anchor)
        {
            menu.Closed += delegate { menu.Dispose(); }; menu.Show(anchor, new Point(0, anchor.Height));
        }
        private void RefreshEditorOptions()
        {
            if (musicOptions == null) return; musicOptions.Visible = Selected.settings.effect == "adaptiveMusic"; temperatureOptions.Visible = Selected.settings.effect == "cpuTemperature";
        }
        private async void Navigate(int index)
        {
            if (busy || body == null) return;
            int oldPage = pageIndex; pageIndex = Math.Max(0, Math.Min(3, index));
            workspace.Visible = pageIndex == 0; gallery.Visible = pageIndex == 1; settingsPage.Visible = pageIndex == 2; mappingPage.Visible = pageIndex == 3;
            pageTitle.Text = new[] { "My Lighting", "Effects", "Keyboard", "Key Mapping" }[pageIndex];
            presetButton.Visible = addEffectButton.Visible = pageIndex == 0;
            for (int i = 0; i < navigation.Length; i++) { navigation[i].Selected = i == pageIndex || i == 2 && pageIndex == 3; navigation[i].Invalidate(); }
            if (pageIndex == 3) mappingKeyboardHost.Controls.Add(keyboard); else keyboardHost.Controls.Add(keyboard);
            keyboard.ShowIndices = pageIndex == 3; UpdateSelection();
            if (pageIndex == 1) RebuildGallery();
            if (oldPage == 3 && pageIndex != 3 && beforeMappingEffect >= 0 && client != null)
            {
                RGB[] frame = beforeMapping; int effect = beforeMappingEffect;
                if (await DeviceAction("Restoring lighting after mapping…", c => { if (frame != null) c.SetFrame(frame); else if (effect == 20) c.SelectOnboardEffect(); else c.SetEffect(effect); return ReadResult(c, false); })) { beforeMapping = null; beforeMappingEffect = -1; illuminated = -1; }
            }
        }
        private void BuildSettings()
        {
            var p = Column(); p.Padding = new Padding(0, 0, 0, 16); settingsPage.Controls.Add(p);
            inputLabel = LabelText("Key response is off.", 600); inputLabel.Height = 28;
            inputButton = ButtonText("Enable key response", delegate { if (input == null) return; if (input.IsRunning) { input.Stop(); pulses.Clear(); inputLabel.Text = input.Status; inputButton.Text = "Enable key response"; UpdateControls(); } else EnableInput(); });
            var access = Section(p, "Keyboard access"); access.Controls.Add(inputLabel); access.Controls.Add(Row(inputButton)); var info = LabelText("Windows key response is used for PC playback and mapping. Effects saved on the keyboard read keys themselves.", 700); info.Height = 42; info.ForeColor = StudioTheme.Secondary; access.Controls.Add(info);
            var device = Section(p, "Connection & layout"); transportBox = Combo(new[] { "Auto", "Bluetooth", "USB", "2.4 GHz" }, 140);
            device.Controls.Add(Row(LabelText("Connection"), transportBox, ButtonText("Check keyboard", async delegate { await DeviceAction("Checking keyboard…", c => ReadResult(c), false); }), ButtonText("Key Mapping…", delegate { Navigate(3); })));
            frameLabel = LabelText("104 of 104 keys mapped", 700); frameLabel.Height = 30; frameLabel.ForeColor = StudioTheme.Secondary; device.Controls.Add(frameLabel);
            brightness = Number(0, 4, profile.settings.brightness);
            device.Controls.Add(Row(LabelText("Brightness"), brightness, ButtonText("Apply", async delegate { int b = (int)brightness.Value; if (await DeviceAction("Applying brightness…", c => { c.SetBrightness(b); return ReadResult(c, false); }, false)) { profile.settings.brightness = b; savedProfile.settings.brightness = b; if (applied != null) applied.settings.brightness = b; SaveProfile(false); } })));
            sleepBox = Combo(sleepChoices.Select(x => x == 0 ? "Never" : x / 60 + " minutes").ToArray(), 130); sleepBox.SelectedIndex = 2;
            if (savedSleep.HasValue) { int index = Array.IndexOf(sleepChoices, savedSleep.Value); if (index >= 0) sleepBox.SelectedIndex = index; }
            device.Controls.Add(Row(LabelText("Wireless sleep"), sleepBox, ButtonText("Apply sleep time", async delegate { int seconds = sleepChoices[sleepBox.SelectedIndex]; if (await DeviceAction("Applying sleep time…", c => { c.SetSleepSeconds(seconds); return new DeviceResult { State = c.Read(), Sleep = c.ReadSleepSeconds() }; }, false)) { savedSleep = seconds; SaveSleep(); } })));
            sleepLabel = LabelText("Connect to check adjustable sleep support.", 700); sleepLabel.ForeColor = StudioTheme.Secondary; sleepLabel.Height = 30; device.Controls.Add(sleepLabel);
            var pc = Section(p, "PC playback"); fpsBox = Combo(new[] { "15", "30", "60", "90", "120" }, 80); fpsBox.SelectedItem = (profile.frameRate ?? 60).ToString();
            pc.Controls.Add(Row(LabelText("Frame rate"), fpsBox, LabelText("FPS"), ButtonText("Open PC playback…", ShowPCPlayback)));
            var rate = LabelText("Native keyboard playback uses the firmware frame rate, up to 50 FPS.", 700); rate.ForeColor = StudioTheme.Secondary; rate.Height = 28; pc.Controls.Add(rate);
            restoreBox = new CheckBox { Text = "Restore saved lighting after reconnect", AutoSize = false, Height = 30, Checked = profile.restoreOnReconnect };
            restoreBox.CheckedChanged += delegate { if (loading) return; profile.restoreOnReconnect = restoreBox.Checked; savedProfile.restoreOnReconnect = restoreBox.Checked; SaveProfile(false); }; pc.Controls.Add(restoreBox);
            var saved = Section(p, "Saved profile"); profileLocationLabel = LabelText(ProfilePath, 700); profileLocationLabel.Height = 42; profileLocationLabel.ForeColor = StudioTheme.Secondary; saved.Controls.Add(profileLocationLabel);
            saved.Controls.Add(Row(ButtonText("Show in Explorer", delegate { System.Diagnostics.Process.Start(dataPath); }), ButtonText("Save on this PC", SaveDraftOnPC), ButtonText("Export…", ExportDraftProfile)));
            var advancedButton = ButtonText("Advanced ▸", delegate { }); p.Controls.Add(advancedButton); var advanced = new Panel { Height = 640, Visible = false, BackColor = StudioTheme.Card }; BuildManual(advanced); p.Controls.Add(advanced);
            advancedButton.Click += delegate { advanced.Visible = !advanced.Visible; advancedButton.Text = advanced.Visible ? "Advanced ▾" : "Advanced ▸"; };
            sensorLabel = LabelText("Audio and CPU sensor status appears while PC effects are running.", 700); sensorLabel.Height = 45; sensorLabel.ForeColor = StudioTheme.Secondary; p.Controls.Add(sensorLabel);
            applyButton = ButtonText("Play & save on PC", async delegate { await StartStudio(); });
        }
        private void BuildPlaybackBar(TableLayoutPanel main)
        {
            var footer = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Padding = new Padding(22, 8, 22, 6), Margin = new Padding(0), BackColor = StudioTheme.Card };
            footer.RowStyles.Add(new RowStyle(SizeType.Absolute, 42)); footer.RowStyles.Add(new RowStyle(SizeType.Absolute, 25)); footer.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); main.Controls.Add(footer, 0, 2);
            var actions = new Panel { Dock = DockStyle.Fill }; playbackLabel = LabelText("Offline", 180); playbackLabel.Dock = DockStyle.Left; playbackLabel.ForeColor = StudioTheme.Secondary;
            var buttons = new FlowLayoutPanel { Dock = DockStyle.Right, WrapContents = false, Width = 536 };
            pcPlaybackButton = ButtonText("PC playback…", ShowPCPlayback); stopButton = ButtonText("Stop", async delegate { if (onboardPlaying) await StopOnboard(); else StopPlayback(); });
            playKeyboardButton = ButtonText("Play on keyboard", async delegate { await RunOnboard(false); }); saveKeyboardButton = ButtonText("Save to keyboard", async delegate { await RunOnboard(true); }, true);
            buttons.Controls.AddRange(new Control[] { pcPlaybackButton, stopButton, playKeyboardButton, saveKeyboardButton }); actions.Controls.Add(playbackLabel); actions.Controls.Add(buttons); footer.Controls.Add(actions, 0, 0);
            actionNotice = LabelText("Connect your keyboard to play or save this layout.", 700); actionNotice.Dock = DockStyle.Fill; actionNotice.ForeColor = StudioTheme.Secondary; footer.Controls.Add(actionNotice, 0, 1);
            statusLabel = LabelText("Ready", 700); statusLabel.Dock = DockStyle.Fill; statusLabel.ForeColor = StudioTheme.Secondary; statusLabel.TextAlign = ContentAlignment.TopLeft; statusLabel.AutoEllipsis = true; footer.Controls.Add(statusLabel, 0, 2);
            UpdateWorkspaceStatus();
        }
        private async System.Threading.Tasks.Task StopOnboard()
        {
            if (await DeviceAction("Stopping the keyboard preview…", c => { c.Clear(); return ReadResult(c, false); })) Status("Keyboard playback stopped. Your permanently saved profile is unchanged.");
        }
        private void UpdateWorkspaceStatus()
        {
            if (playbackLabel == null) return;
            playbackLabel.Text = onboardPlaying ? "Playing on keyboard" : playing ? "Playing from PC" : client != null ? "Ready" : "Offline";
            sidebarInput.Text = input != null && input.IsRunning ? "PC key response enabled" : "PC key response is off";
            sidebarInput.ForeColor = input != null && input.IsRunning ? accent : StudioTheme.Secondary;
            actionNotice.Text = busy ? "Working… Your controls will be available when this finishes." : client == null ? "Connect your keyboard to play or save this layout." : !onboard.Volatile ? "Use wired USB and compatible firmware for on-keyboard playback. PC playback is available over wireless." : !onboard.Persistent ? "Keyboard preview is available. This firmware does not support permanent saving." : "Play previews this layout. Save stores it on the keyboard so it returns after power-off.";
            stopButton.Enabled = !busy && (playing || frameInFlight || onboardPlaying); addEffectButton.Enabled = !busy && profile.layers.Count < 16;
            presetButton.Enabled = profileButton.Enabled = pcPlaybackButton.Enabled = !busy; RefreshLayerCards();
        }
        private Form CreatePCPlaybackDialog()
        {
            var dialog = new Form { Text = "PC Playback", Size = new Size(560, 360), MinimumSize = new Size(520, 340), StartPosition = FormStartPosition.CenterParent, BackColor = surface, ForeColor = ink, Font = Font, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false, ShowInTaskbar = false };
            var p = Column(); p.Padding = new Padding(22); dialog.Controls.Add(p);
            p.Controls.Add(Heading("Run from PC", 16)); var detail = LabelText("Plays your layout while Lighting Studio is running. For effects that run on the keyboard, close this window and use Play or Save to keyboard.", 480); detail.Height = 64; detail.ForeColor = StudioTheme.Secondary; p.Controls.Add(detail);
            var rate = Combo(new[] { "15", "30", "60", "90", "120" }, 90); rate.SelectedItem = fpsBox.Text; rate.SelectedIndexChanged += delegate { fpsBox.SelectedItem = rate.Text; };
            p.Controls.Add(Row(LabelText("Frame rate"), rate, LabelText("FPS")));
            var play = ButtonText("Play & save on PC", async delegate { await StartStudio(); }); play.Enabled = client != null && !busy;
            var pause = ButtonText("Stop PC playback", StopPlayback); pause.Enabled = playing; var close = ButtonText("Close", delegate { dialog.Close(); });
            p.Controls.Add(Row(play, pause, close)); dialog.CancelButton = close; dialog.AcceptButton = play;
            var timer = new System.Windows.Forms.Timer { Interval = 200 }; timer.Tick += delegate { play.Enabled = client != null && !busy; pause.Enabled = playing && !busy; }; timer.Start(); dialog.FormClosed += delegate { timer.Stop(); timer.Dispose(); };
            return dialog;
        }
        private void ShowPCPlayback() { using (var dialog = CreatePCPlaybackDialog()) dialog.ShowDialog(this); }
        internal void LoadPreviewPreset(string name) { if (!preview) return; presetBox.SelectedItem = name; LoadPreset(); }
        internal void RenderPreviewFrame() { RenderPreviews(); }
        internal void SavePreviewImage(string path, int width = 1320, int height = 880)
        {
            if (!preview) throw new InvalidOperationException("Preview-only renderer.");
            // Render the complete app surface; a service desktop may be smaller than the app.
            Control root = Controls[0]; root.Dock = DockStyle.None; root.Size = new Size(width, height); root.PerformLayout();
            Application.DoEvents(); RenderPreviews();
            using (var bitmap = new Bitmap(width, height)) { root.DrawToBitmap(bitmap, new Rectangle(0, 0, width, height)); bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png); }
        }
        private void RenderPreviews()
        {
            if (closing || busy) return;
            double time = Now; var demo = new List<KeyPulse> { new KeyPulse("KeyW", time - time % 3.5) };
            if (pageIndex == 1)
            {
                foreach (var thumbnail in thumbnails) { thumbnail.Colors = LightingEngine.Render(new List<LightingLayer> { thumbnail.Layer }, keys, map, demo, time, null, new HashSet<string> { "KeyW" }, new HashSet<string> { "KeyW" }); thumbnail.Invalidate(); }
            }
            else if (pageIndex == 0 && !playing)
            {
                keyboard.Frame = LightingEngine.Render(profile.layers, keys, map, new List<KeyPulse>(pulses), time, null, new HashSet<string>(heldKeys), new HashSet<string>(toggledKeys)); keyboard.Invalidate();
            }
        }
    }
}
