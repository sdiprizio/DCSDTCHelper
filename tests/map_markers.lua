-- Run from the repository root with DCS's bin/luae.exe.
package.path = "SavedGames/Scripts/DCSDTCHelper/?.lua;" .. package.path
local windows = {}
local function widget()
    local w = {}
    for _, name in ipairs({ "setTitleHeight", "setDraggable", "setResizable", "setZOrder",
        "insertWidget", "insertOverlayWidget", "setText" }) do w[name] = function() end end
    function w:setSkin(skin) self.skin = skin end
    function w:setZOrder(z) self.z = z end
    function w:setBounds(x, y, width, height) self.bounds = { x, y, width, height } end
    function w:setVisible(value)
        assert(type(value) == "boolean", "DCS WidgetSetVisible requires a boolean")
        self.visible = value
    end
    function w:setTransparentForUserInput(value) self.transparent = value end
    function w:addMouseDownCallback(callback) self.down = callback end
    function w:addMouseMoveCallback(callback) self.move = callback end
    function w:addMouseUpCallback(callback) self.up = callback end
    function w:captureMouse() self.captured = true end
    function w:releaseMouse() self.captured = false end
    function w:kill() self.killed = true end
    return w
end
package.preload.Window = function() return { new = function()
    local w = widget(); table.insert(windows, w); return w
end } end
package.preload.Button = function() return { new = widget } end
package.preload.Static = function() return { new = widget } end
package.preload.Skin = function()
    local function painted_skin()
        return { skinData = { params = { name = "defaultSkin" }, states = {
            released = { { bkg = {}, picture = {}, text = {} } },
            pressed = { { bkg = {}, picture = {}, text = {} } },
            hover = { { bkg = {}, picture = {}, text = {} } },
            disabled = { { bkg = {}, picture = {}, text = {} } },
        } } }
    end
    return {
        buttonSkin_MENew2 = function()
            if arg[1] then return assert(loadfile(arg[1] .. "/dxgui/skins/skinME/buttonSkin_MENew2.skin.lua"))() end
            return painted_skin()
        end,
        windowSkinTransparent = function()
            if arg[1] then return assert(loadfile(arg[1] .. "/dxgui/skins/skinME/windowSkinTransparent.skin.lua"))() end
            local skin = painted_skin()
            skin.skinData.skins = { view = painted_skin(), header = painted_skin() }
            return skin
        end,
    }
end

local visible, zoom, pan = true, 2, 0
local foreground = 1
local Gui = {
    FindWidgetAtScreenPoint = function() return foreground end,
    WidgetGetVisible = function() return visible end,
    WidgetToScreen = function() return 10, 20 end,
    WidgetGetSize = function() return 1000, 800 end,
}
-- Rotated axes, nonzero widget origin, zoom and pan.
local NativeMap = { GetMapPoint = function(_, x, y) return pan + y * zoom, -x * zoom end }
local map = { getMapPoint = function(_, x, y) return NativeMap.GetMapPoint(1, x - 10, y - 20) end }
local feature = require("CoordinateList").new({
    get_active_map = function() return map end,
    to_lat_lon = function(x, y) return x / 100, y / 100 end,
    terrain_height = function(x) return x end,
    log = function(message, level) if level ~= "info" then error(message) end end,
})
local markers = require("MapMarkers").new(Gui, NativeMap, feature)
map.refreshMarkers = function() markers:refresh(1, map) end
feature.points = { { x = 200, y = -400, lat = 2, lon = -4, elevation = 200, name = "Test" } }
feature:refresh_all_markers()
local entry = markers.maps[1][1]
local function cross_center()
    local h, v, w = entry.horizontal.bounds, entry.vertical.bounds, entry.window.bounds
    assert(h[1] + h[3] / 2 == v[1] + v[3] / 2)
    assert(h[2] + h[4] / 2 == v[2] + v[4] / 2)
    return w[1] + h[1] + h[3] / 2, w[2] + h[2] + h[4] / 2
end
local cx, cy = cross_center()
assert(cx == 210 and cy == 120) -- The cross, not the window edge, is the coordinate anchor.
local function assert_clear_window(skin)
    assert(not (skin.skinData.params or {}).name)
    for _, group in pairs(skin.skinData.states or {}) do
        for _, state in pairs(group) do
            assert(state.bkg.center_center == "0x00000000" and state.picture.color == "0x00000000")
        end
    end
    for _, child in pairs(skin.skinData.skins or {}) do assert_clear_window(child) end
end
assert_clear_window(entry.window.skin)
assert(entry.window.skin.skinData.params.headerHeight == 0)
for _, group in pairs(entry.control.skin.skinData.states) do
    for _, state in pairs(group) do
        assert(state.text and state.bkg.center_center == "0x00000000" and state.picture.color == "0x00000000")
    end
end
assert(entry.window.transparent and entry.window.visible)
assert(entry.window.z > 200)
foreground = 2
markers:update()
assert(entry.window.visible == false and not entry.window.killed,
    "covering a marker with a dialog must hide it without killing it")
foreground = nil
markers:update()
assert(entry.window.visible == false and not entry.window.killed)
foreground = 1
markers:update()
assert(entry.window.visible == true, "uncovered marker must return")
foreground = 2
markers:refresh(2, {})
markers:update()
assert(not entry.window.visible and markers.maps[2][1].window.visible)
markers:remove(2)
foreground = 1
markers:update()
feature:set_mode("edit")
markers:update()
assert(not entry.window.transparent)
entry.control:down(240, 120, 1) -- Grab label 30 pixels to the right.
assert(entry.control.captured)
entry.control:move(290, 160)
markers:update()
assert(feature.points[1].x == 280 and feature.points[1].y == -500)
assert(markers:mouse_up(290, 160, 1))
assert(not entry.control.captured)
assert(feature.points[1].lat == 2.8 and feature.points[1].elevation == 280)
assert(feature.points[1].selected)
entry.control:down(260, 160, 1)
markers:mouse_up(260, 160, 1)
assert(not feature.points[1].selected) -- Click toggles; drag does not toggle off.
entry.control:down(260, 160, 3)
assert(not markers.drag) -- Right button cannot move a marker.
entry.control:down(260, 160, 1)
markers:mouse_move(300, 200)
feature:set_mode("edit")
markers:update()
assert(not markers.drag and feature.points[1].x == 280)
zoom, pan = 4, 40
markers:update()
cx, cy = cross_center()
assert(cx == 135 and cy == 80)
visible = false
markers:update()
assert(not entry.window.visible)
feature.points[1].selected = true
feature:delete_selected()
assert(not entry.window.killed and not entry.window.visible and #markers.maps[1] == 0)
assert(not feature:map_click(map, 400, 400)) -- Empty Edit space does not relocate points.
local allocated = #windows
local fresh_map = { getMapPoint = function() return 123, 456 end }
feature.points = { { name = "Fresh", x = 200, y = -400 } }
markers:refresh(99, fresh_map)
local reused = markers.maps[99][1]
assert(#windows == allocated, "deleted marker windows should be reused")
feature.edit = true
reused.control:down(100, 100, 1)
assert(markers.drag.map == fresh_map and markers.drag.pointer == 99,
    "reused mouse callback must target the new map")
markers:clear()
assert(not markers.drag and not reused.control.captured)
assert(not reused.point and not reused.map and not reused.pointer)
reused.control:down(100, 100, 1)
assert(not markers.drag, "retired callbacks must ignore input")
for _, path in ipairs({ "DTC.lua", "CoordinateList.lua", "MapMarkers.lua" }) do
    assert(loadfile("SavedGames/Scripts/DCSDTCHelper/" .. path))
end
print("Map marker regression checks passed")

-- Integration: opening another visible map is discovered on a frame without
-- calling any mouse callback. Both map adapters receive the existing points.
local callbacks
local list_module = require("CoordinateList")
local original_new = list_module.new
local integrated_feature
list_module.new = function(api)
    integrated_feature = original_new(api)
    integrated_feature.create_ui = function() end
    return integrated_feature
end
Gui.GetWindowSize = function() return 1000, 800 end
Gui.FindWidgetAtScreenPoint = function(x) return x < 500 and 1 or 2 end
Gui.WidgetGetTypeName = function() return "Widget" end
Gui.ScreenToWidget = function(_, x, y) return x - 10, y - 20 end
Gui.AddMouseCallback = function() end
Gui.AddKeyboardCallback = function() end
package.preload.dxgui = function() return Gui end
package.preload.Widget = function() return { widgets = {} } end
package.preload.gui_map = function() return NativeMap end
package.preload.terrain = function() return {
    convertMetersToLatLon = function(x, y) return x / 100, y / 100 end,
    GetHeight = function() return 0 end,
} end
DCS = { setUserCallbacks = function(c) callbacks = c end, getRealTime = function() return 1 end }
visible = true
require("DTC").start()
integrated_feature.points = { { name = "Existing", x = 280, y = -500 } }
callbacks.onSimulationFrame()
local count = 0
for _ in pairs(integrated_feature.marker_sets) do count = count + 1 end
assert(count == 2, "F10 and DTC must attach without a click")
print("Automatic F10/DTC map discovery checks passed")
local old_maps = {}
for map in pairs(integrated_feature.marker_sets) do old_maps[map] = true end
local old_windows = #windows
callbacks.onSimulationStop()
assert(next(integrated_feature.marker_sets) == nil)
assert(not integrated_feature.capture and not integrated_feature.edit)
for i = old_windows - 1, old_windows do
    assert(not windows[i].killed and not windows[i].visible, "mission overlays must be hidden and kept alive")
end
local find = Gui.FindWidgetAtScreenPoint
Gui.FindWidgetAtScreenPoint = function() error("must not discover maps during teardown") end
callbacks.onSimulationFrame()
callbacks.onShowMainInterface()
callbacks.onSimulationFrame()
callbacks.onSimulationStop()
assert(next(integrated_feature.marker_sets) == nil)
Gui.FindWidgetAtScreenPoint = find
callbacks.onMissionLoadBegin()
callbacks.onSimulationStart()
callbacks.onSimulationFrame()
count = 0
for map in pairs(integrated_feature.marker_sets) do
    assert(not old_maps[map], "must not reuse adapters for old native pointers")
    count = count + 1
end
assert(count == 2)
assert(#windows == old_windows, "mission restart must reuse windows without growing the pool")
print("Mission exit and restart regression checks passed")
-- A failed map probe must hide, not destroy, overlays in the frame callback.
local probes = 0
Gui.WidgetGetVisible = function()
    probes = probes + 1
    error("expired map")
end
local window_count = #windows
callbacks.onSimulationFrame()
local first_probes = probes
callbacks.onSimulationFrame()
assert(first_probes == 2 and probes == first_probes, "failed maps must not be probed repeatedly")
for i = window_count - 1, window_count do
    assert(windows[i].visible == false and not windows[i].killed)
end
callbacks.onSimulationStop()
for i = window_count - 1, window_count do assert(not windows[i].killed and not windows[i].visible) end
print("Projection failure quarantine checks passed")
