-- DCS DTC Helper -- F10 coordinate collection and JDAM transfer feature.
-- Loaded by Scripts\Hooks\DCSDTCHelper.lua.

local M = {}

local TAG = "DCSDTCHelper"
local INFO = (log and log.INFO) or 0
local WARNING = (log and log.WARNING) or 1
local ERROR = (log and log.ERROR) or 2
local DEFAULT_SHORTCUT_KEY = "C"

local coordinate_list
local active_map
local map_adapters = setmetatable({}, { __mode = "v" })
local logged_non_map_capture_types = {}
local last_options_poll = 0
local shortcut_registered = false
local left_ctrl_down = false
local right_ctrl_down = false
local left_shift_down = false
local right_shift_down = false
local left_alt_down = false
local right_alt_down = false
local shortcut_key_down = false
local shortcut = {
    key = DEFAULT_SHORTCUT_KEY,
    left_ctrl = true, right_ctrl = false,
    left_shift = true, right_shift = false,
    left_alt = false, right_alt = false,
    enabled = true,
}

package.path = package.path
    .. ";.\\Scripts\\UI\\?.lua"
    .. ";.\\Scripts\\UI\\DTC_manager\\?.lua"
    .. ";.\\MissionEditor\\modules\\?.lua"

local function write(level, message)
    if log and log.write then log.write(TAG, level, message) else print(TAG .. ": " .. message) end
end

local function get_special_option(options_editor, name, default)
    local ok, value = pcall(options_editor.getOption, "plugins.DCSDTCHelper." .. name)
    if ok and value ~= nil then return value end
    return default
end

local function read_shortcut()
    local ok, options_editor = pcall(require, "optionsEditor")
    if not ok then return nil end
    local key = get_special_option(options_editor, "coordinateListShortcutKey", DEFAULT_SHORTCUT_KEY)
    if type(key) ~= "string" then key = DEFAULT_SHORTCUT_KEY end
    key = string.upper(string.gsub(key, "%s+", ""))
    if not string.match(key, "^[A-Z]$") then key = DEFAULT_SHORTCUT_KEY end
    local result = {
        key = key,
        left_ctrl = get_special_option(options_editor, "coordinateListShortcutLeftCtrl", true) == true,
        right_ctrl = get_special_option(options_editor, "coordinateListShortcutRightCtrl", false) == true,
        left_shift = get_special_option(options_editor, "coordinateListShortcutLeftShift", true) == true,
        right_shift = get_special_option(options_editor, "coordinateListShortcutRightShift", false) == true,
        left_alt = get_special_option(options_editor, "coordinateListShortcutLeftAlt", false) == true,
        right_alt = get_special_option(options_editor, "coordinateListShortcutRightAlt", false) == true,
    }
    result.enabled = result.left_ctrl or result.right_ctrl or result.left_shift or result.right_shift or result.left_alt or result.right_alt
    return result
end

local function shortcuts_equal(a, b)
    return a.key == b.key and a.left_ctrl == b.left_ctrl and a.right_ctrl == b.right_ctrl
        and a.left_shift == b.left_shift and a.right_shift == b.right_shift
        and a.left_alt == b.left_alt and a.right_alt == b.right_alt
end

local function refresh_shortcut()
    local configured = read_shortcut()
    if configured and not shortcuts_equal(shortcut, configured) then
        shortcut = configured
        shortcut_key_down = false
    end
end

local function is_key_down(state)
    return state == "down" or state == true or state == 1
end

local function modifiers_match()
    return left_ctrl_down == shortcut.left_ctrl and right_ctrl_down == shortcut.right_ctrl
        and left_shift_down == shortcut.left_shift and right_shift_down == shortcut.right_shift
        and left_alt_down == shortcut.left_alt and right_alt_down == shortcut.right_alt
end

local function shortcut_callback(key_name, key_state)
    local down = is_key_down(key_state)
    if key_name == "left ctrl" then left_ctrl_down = down
    elseif key_name == "right ctrl" then right_ctrl_down = down
    elseif key_name == "left shift" then left_shift_down = down
    elseif key_name == "right shift" then right_shift_down = down
    elseif key_name == "left alt" then left_alt_down = down
    elseif key_name == "right alt" then right_alt_down = down
    elseif key_name == string.lower(shortcut.key) then
        if down and shortcut.enabled and modifiers_match() and not shortcut_key_down then
            shortcut_key_down = true
            if coordinate_list then coordinate_list:toggle() end
        elseif not down then
            shortcut_key_down = false
        end
    end
end

local function is_map_widget(wrapper)
    return wrapper and type(wrapper.getMapPoint) == "function"
        and type(wrapper.addUserObjects) == "function"
        and type(wrapper.removeUserObjects) == "function"
end

local function widget_name(widget)
    if not widget then return "" end
    if type(widget.name) == "string" then return string.lower(widget.name) end
    local ok, value = pcall(widget.getName, widget)
    return ok and type(value) == "string" and string.lower(value) or ""
end

local function create_feature()
    if coordinate_list then return end
    local ok, err = pcall(function()
        local Gui = require("dxgui")
        local Widget = require("Widget")
        local Terrain = require("terrain")
        local NativeMap = require("gui_map")
        local CoordinateList = require("CoordinateList")

        refresh_shortcut()
        if not shortcut_registered then
            Gui.AddKeyboardCallback(shortcut_callback)
            shortcut_registered = true
        end

        local function map_adapter(pointer, type_name, wrapper, screen_x, screen_y)
            if is_map_widget(wrapper) then return wrapper end
            if not pointer or type(type_name) ~= "string" then return nil end
            if map_adapters[pointer] then return map_adapters[pointer] end
            local normalized_type = string.lower(type_name)
            -- In this isolated hook state the F10 native map is reported as a
            -- generic Widget rather than its map class. Probe that pointer via
            -- gui_map and accept it only when it yields real map coordinates.
            if not string.find(normalized_type, "map", 1, true) and normalized_type ~= "widget" then return nil end
            local adapter = {
                getMapPoint = function(_, screen_x, screen_y)
                    local widget_x, widget_y = Gui.ScreenToWidget(pointer, screen_x, screen_y)
                    return NativeMap.GetMapPoint(pointer, widget_x, widget_y)
                end,
                addUserObjects = function(_, objects) return NativeMap.AddUserObjects(objects, pointer) end,
                removeUserObjects = function(_, objects) return NativeMap.RemoveUserObjects(objects, pointer) end,
            }
            local valid, map_x, map_y = pcall(adapter.getMapPoint, adapter, screen_x, screen_y)
            if not valid or type(map_x) ~= "number" or type(map_y) ~= "number" then return nil end
            map_adapters[pointer] = adapter
            write(INFO, "coordinate list: using native " .. type_name .. " F10 map adapter")
            return adapter
        end

        local function transfer_to_jdam(point)
            local lat, lon, elevation
            local jdam_controls = false
            for _, widget in pairs(Widget.widgets) do
                if widget and widget.widget and widget:getTypeName() == "EditBox" then
                    local name = widget_name(widget)
                    if string.find(name, "jdam", 1, true) then
                        jdam_controls = true
                        if string.find(name, "lat", 1, true) then lat = widget end
                        if string.find(name, "lon", 1, true) or string.find(name, "long", 1, true) then lon = widget end
                        if string.find(name, "alt", 1, true) or string.find(name, "elev", 1, true) then elevation = widget end
                    end
                end
            end
            if not jdam_controls then return false, "Open the F-14B(U) JDAM DTC target editor first." end
            if not lat or not lon or not elevation then
                write(WARNING, "F-14B(U) JDAM DTC controls found but named coordinate fields are unavailable")
                return false, "JDAM target fields are not exposed by this DCS build."
            end
            for _, update in ipairs({
                { widget = lat, value = string.format("%.6f", point.lat) },
                { widget = lon, value = string.format("%.6f", point.lon) },
                { widget = elevation, value = tostring(point.elevation) },
            }) do
                local updated, update_err = pcall(function()
                    update.widget:setText(update.value)
                    if update.widget.onChange then update.widget:onChange() end
                end)
                if not updated then
                    write(ERROR, "F-14B(U) JDAM DTC field update failed: " .. tostring(update_err))
                    return false, "JDAM field update failed; see dcs.log."
                end
            end
            return true, "Sent selected target to the active JDAM DTC slot."
        end

        coordinate_list = CoordinateList.new({
            log = function(message, level) write(level == "warning" and WARNING or INFO, "coordinate list: " .. message) end,
            get_active_map = function() return active_map end,
            to_lat_lon = function(x, y)
                local converted, lat, lon = pcall(Terrain.convertMetersToLatLon, x, y)
                if converted then return lat, lon end
                write(WARNING, "coordinate conversion failed: " .. tostring(lat))
                return nil, nil
            end,
            terrain_height = function(x, y)
                local sampled, height = pcall(Terrain.GetHeight, x, y)
                return sampled and height or nil
            end,
            transfer_to_jdam = transfer_to_jdam,
        })
        coordinate_list:create_ui()

        Gui.AddMouseCallback("up", function(x, y)
            local pointer = Gui.FindWidgetAtScreenPoint(x, y)
            local wrapper = pointer and Widget.widgets[pointer] or nil
            local type_name = pointer and Gui.WidgetGetTypeName(pointer) or nil
            local map = map_adapter(pointer, type_name, wrapper, x, y)
            if map then
                active_map = map
                coordinate_list:capture_map_click(map, x, y)
            elseif coordinate_list.capture and type_name and not logged_non_map_capture_types[type_name] then
                logged_non_map_capture_types[type_name] = true
                write(WARNING, "coordinate list: capture release hit " .. tostring(type_name) .. ", not a map widget")
            end
        end)
    end)
    if not ok then write(ERROR, "DTC setup failed: " .. tostring(err)) end
end

local function on_frame()
    if not coordinate_list then return end
    local now = DCS.getRealTime()
    if now - last_options_poll >= 0.25 then
        last_options_poll = now
        refresh_shortcut()
    end
end

function M.start()
    DCS.setUserCallbacks({
        onSimulationStart = create_feature,
        onShowMainInterface = create_feature,
        onSimulationFrame = on_frame,
    })
    create_feature()
end

return M
