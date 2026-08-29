# DESCRIPTION

DCS DTC Helper is a Lua script extension for DCS World.
It has two scopes :

- Create a VR keyboard that should be available in the whole game to replace any keyboard entry. It's main scope is to allow to enter text anywhere it is needed for example in mission editor to name waypoints, write altitudes, etc.
- Create a binding layer between F10 view/flightplan and DTC view which are currently completely separated. Goal is to add the possibility to enter coordinate for targets visible in F10 view and not visible in DTC view.

# LANGUAGE

LUA is the scripting language of DCS
Eventually tools in powershell for dev.

# REFERENCES

- DCS GameGUI hook API (authoritative local copy): `E:\DCS World\API\Sim_ControlAPI.md`. It documents the Saved Games hook location (`$WRITE_DIR/Scripts/Hooks/*.lua`), its isolated GUI Lua state, and `DCS.setUserCallbacks`.
- DCS GUI implementation references (authoritative local code): `E:\DCS World\MissionEditor\GameGUI.lua`, `E:\DCS World\Scripts\Hooks\common.lua`, and `E:\DCS World\dxgui\bind\Widget.lua`. Use these to follow DCS's widget and callback conventions.
- Native widget selection reference (authoritative local code): `E:\DCS World\MissionEditor\modules\me_contextMenu.lua` uses `dxgui.FindWidgetAtScreenPoint(x, y)` from a window mouse callback. Use this to associate a user click with the underlying DCS GUI widget.
- [DCS Scratchpad](https://github.com/rkusa/dcs-scratchpad) reference: its keypad binds buttons with `addMouseUpCallback`, explicitly noting that mouse-up is necessary before refocusing its text area. Use this event order for virtual-key clicks in dxgui.

# TROUBLESHOOTING

When the user reports any runtime problem, inspect `%USERPROFILE%\Saved Games\DCS\Logs\dcs.log` for `DCSDTCHelper` entries before proposing another change. Add bounded, relevant diagnostic logs when the current entries do not identify the failing API, widget, callback, or lifecycle stage.
- Community quick reference: [Hoggit DCS server gameGUI](https://wiki.hoggit.us/view/DCS_server_gameGUI). Treat it as supplementary; verify API details against the local DCS API matching the installed build.
- Mission Editor extension reference: [DCS-SMS Mission Editor mod](https://github.com/nielsvaes/dcs-sms/blob/main/tools/me-mod/README.md). Its installation documents the practical integration point: add a `require(...)` block to `MissionEditor.lua` and load a module from `MissionEditor/modules/`. This is the reference for editor-only UI; it is not a Saved Games hook.
