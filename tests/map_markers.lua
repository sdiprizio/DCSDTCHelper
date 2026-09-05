-- Run from the repository root with DCS's bin/luae.exe.
package.path = "SavedGames/Scripts/DCSDTCHelper/?.lua;" .. package.path
local windows = {}
local function widget()
    local w = {}
    for _, name in ipairs({ "setTitleHeight", "setDraggable", "setResizable", "setZOrder",
        "insertWidget", "setText", "setSkin" }) do w[name] = function() end end
    function w:setBounds(x, y, width, height) self.bounds = { x, y, width, height } end
    function w:setVisible(value) self.visible = value end
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
package.preload.Skin = function() return { buttonSkin_MENew2 = function()
    return { skinData = { states = { released = { { text = { horzAlign = {} } } } } } }
end } end

local visible, zoom, pan = true, 2, 0
local Gui = {
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
    log = function(message) error(message) end,
})
local markers = require("MapMarkers").new(Gui, NativeMap, feature)
map.refreshMarkers = function() markers:refresh(1, map) end
feature.points = { { x = 200, y = -400, lat = 2, lon = -4, elevation = 200, name = "Test" } }
feature:refresh_all_markers()
local entry = markers.maps[1][1]
assert(entry.window.bounds[1] == 210 and entry.window.bounds[2] == 109)
assert(entry.window.transparent and entry.window.visible)
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
assert(entry.window.bounds[1] == 135 and entry.window.bounds[2] == 69)
visible = false
markers:update()
assert(not entry.window.visible)
feature.points[1].selected = true
feature:delete_selected()
assert(entry.window.killed and #markers.maps[1] == 0)
assert(not feature:map_click(map, 400, 400)) -- Empty Edit space does not relocate points.
for _, path in ipairs({ "DTC.lua", "CoordinateList.lua", "MapMarkers.lua" }) do
    assert(loadfile("SavedGames/Scripts/DCSDTCHelper/" .. path))
end
print("Map marker regression checks passed")
