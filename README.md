# DCS DTC Helper

The project is installed entirely under the active DCS Saved Games profile.
No DCS installation files are changed.

## Current milestone: virtual keyboard foundation

`SavedGames/Scripts/Hooks/DCSDTCHelperGameGUI.lua` opens a basic QWERTY
keyboard as the DCS GUI loads, so it is available in missions and DTC. Clickable
keys update the selected native DCS text field. Click the target field first,
place its caret where text should be inserted, then click the virtual keys.
The keyboard preserves the field's caret position after each edit.

### Manual test

1. Copy the repository's `SavedGames` contents into the active profile, normally
   `%USERPROFILE%\Saved Games\DCS`.
2. Start a mission, then exit DCS.
3. In `%USERPROFILE%\Saved Games\DCS\Logs\dcs.log`, search for
   `DCSDTCHelper`.
4. Confirm the keyboard appears and that clicking keys updates the selected DCS
   field at its existing caret position.
