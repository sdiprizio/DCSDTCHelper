# DCS DTC Helper

This project aims to :

- Create a virtual keyboard for VR usage
- Create a link between DCS F10 map (in multiplayer server) and DTC map.

## Hook layout

Install both Saved Games hooks:

- `Scripts/Hooks/DCSDTCHelperVirtualKeyboard.lua` provides the VR virtual keyboard.
- `Scripts/Hooks/DCSDTCHelper.lua` provides F10 coordinate collection.

The hook files are deliberately small. Their feature implementations live in
`Scripts/DCSDTCHelper/`; the two hooks share only the plugin's single Special
Options page.

## Virtual keyboard shortcut

Press `Ctrl+Shift+V` to show or hide the virtual keyboard. This default shortcut
can be changed in Special options

## F10 coordinate list

Press `Ctrl+Shift+C` to show the **Coordinate List** (the shortcut is
separately configurable in Special options). Enable **Add** and release the
mouse over the F10 map to collect targets. Enable **Edit** to click a target's
map marker or label to select or deselect it, or drag it to move the target.
Markers appear above native map symbols, including units. Dragging empty map
space still pans the map.
Targets are kept only
for the current DCS session and include latitude, longitude, and sampled ground
elevation. The scrollable table lets you select one or more rows, edit labels,
and review each point's index, coordinates, and altitude. Use the coordinate
mode button to cycle through decimal degrees, degrees/minutes,
degrees/minutes/seconds, and MGRS. The header checkbox selects or deselects
every target. Selected targets are highlighted on the map; delete supports
multiple selected rows.

The project also installs a Saved Games service module. In **Options → Special
→ DCS DTC Helper**, select the exact left/right modifier keys and enter the
single trigger letter. Changes apply without restarting DCS. An empty or
invalid letter falls back to `V`; selecting no modifier disables the shortcut.

It is largely made with AI coding, we are in 2026, it is a small project for DCS World, not a nuclear plant code... I don't have time to do it by hand.
