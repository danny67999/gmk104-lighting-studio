# Individual-key RGB and layers

[Documentation home](README.md)

These button names describe the Windows controller. See the [Mac effects guide](../README.md#effects-and-layers) for the native Mac workflow.

## Give individual keys different colors

1. Connect the keyboard and set brightness above zero.
2. Press **Stop** if a host animation is running, so it will not overwrite your manual colors.
3. Choose a base color in **Effect layers**. Open **Manual lighting** and click **Set all keys** once. This establishes a complete, known direct-RGB frame; a running built-in firmware effect is not a stable editable frame.
4. Choose a different color. Click a key on the diagram outside key-selection or mapping mode. That key's assigned color changes while the rest of the verified frame is preserved.
5. Repeat for other keys. If the wrong physical key lights, see [mapping troubleshooting](troubleshooting.md#the-wrong-key-changes-color).

Example: set all keys to dim blue, choose orange, then click W, A, S and D individually.

## Color a key group with layers

1. Create or select a **Static color** layer and choose its color.
2. Click **Choose keys**, select the keys on the diagram, then click **Done selecting**.
3. Add other layers for another group or an animated background. Up to 16 layers are supported; the top layer appears above those below.
4. Click **Apply & save layers** to start and save the result. Unapplied layer edits are drafts and are not what reconnect restores.

Layers support color, speed, intensity, opacity and normal/additive blending. **Affect all keys** allows selected trigger keys to start an effect across the keyboard; turn it off to restrict the effect to the selected group. An empty key selection disables the layer's output.

## Why a ripple can look dark

Ripple, rainbow ripple and reactive effects respond to key presses and can be dark while idle. Enable key response and press a selected trigger key, or use **Test pulse**. Use a Static color layer for continuous illumination. The Windows listener accepts the selected GMK104's physical key transitions, not unrelated keyboards.

## Save, export and reconnect

Use **Apply & save layers** for layer changes and **Export saved** to back up the saved profile. **Import profile** accepts supported Mac profile JSON. Imported studio profiles start with Apply & save layers; imported manual/built-in profiles use **Manual lighting → Apply imported / saved profile**.

Enable **Restore saved lighting after reconnect** if you want the saved profile reapplied. **Stop** pauses host effects and leaves the last verified colors. Closing the window keeps the controller in the tray; **Quit** exits it. Host-generated effects require the app to stay running; do not assume a profile is permanently stored in keyboard firmware.

The FPS setting is a cap, not a promised rate. Bluetooth can be slower than USB; the displayed rate reflects achieved performance.
