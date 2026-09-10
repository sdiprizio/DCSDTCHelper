-- DCS DTC Helper -- F10 coordinate collection feature.
-- Loaded by Scripts\Hooks\DCSDTCHelper.lua.

local M = {}

local TAG = "DCSDTCHelper"
local INFO = (log and log.INFO) or 0
local WARNING = (log and log.WARNING) or 1
local ERROR = (log and log.ERROR) or 2
local DEFAULT_SHORTCUT_KEY = "C"

local coordinate_list
local map_markers
local discover_maps
local active_map
local map_adapters = setmetatable({}, { __mode = "v" })
local logged_non_map_capture_types = {}
local last_options_poll = 0
local shortcut_registered = false
local suspended = false
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
    if suspended then return end
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
            if not pointer or type(type_name) ~= "string" then return nil end
            if map_adapters[pointer] then return map_adapters[pointer] end
            local normalized_type = string.lower(type_name)
            -- In this isolated hook state the F10 native map is reported as a
            -- generic Widget rather than its map class. Probe that pointer via
            -- gui_map and accept it only when it yields real map coordinates.
            if not is_map_widget(wrapper) and not string.find(normalized_type, "map", 1, true) and normalized_type ~= "widget" then return nil end
            local adapter = {
                getMapPoint = function(_, screen_x, screen_y)
                    local widget_x, widget_y = Gui.ScreenToWidget(pointer, screen_x, screen_y)
                    return NativeMap.GetMapPoint(pointer, widget_x, widget_y)
                end,
                refreshMarkers = function(map) return map_markers:refresh(pointer, map) end,
            }
            local valid, map_x, map_y = pcall(adapter.getMapPoint, adapter, screen_x, screen_y)
            if not valid or type(map_x) ~= "number" or type(map_y) ~= "number" then return nil end
            map_adapters[pointer] = adapter
            write(INFO, "coordinate list: using native " .. type_name .. " F10/DTC map adapter")
            return adapter
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
        })
        coordinate_list:create_ui()
        map_markers = require("MapMarkers").new(Gui, NativeMap, coordinate_list)

        discover_maps = function()
            if #coordinate_list.points == 0 then return end
            local width, height = Gui.GetWindowSize()
            local seen = {}
            -- Native F10/DTC maps are not registered in this hook's Widget table.
            -- Probe visible screen surfaces so opening DTC needs no initial click.
            for _, fx in ipairs({ 0.25, 0.5, 0.75 }) do
                for _, fy in ipairs({ 0.25, 0.5, 0.75 }) do
                    local x, y = width * fx, height * fy
                    local pointer = Gui.FindWidgetAtScreenPoint(x, y)
                    if pointer and not seen[pointer] then
                        seen[pointer] = true
                        local map = map_adapter(pointer, Gui.WidgetGetTypeName(pointer), Widget.widgets[pointer], x, y)
                        if map and not coordinate_list.marker_sets[map] then
                            coordinate_list:refresh_markers(map)
                        end
                    end
                end
            end
        end

        Gui.AddMouseCallback("up", function(x, y, button)
            if suspended then return end
            if map_markers:mouse_up(x, y, button) then return end
            if button ~= 1 then return end
            local pointer = Gui.FindWidgetAtScreenPoint(x, y)
            local wrapper = pointer and Widget.widgets[pointer] or nil
            local type_name = pointer and Gui.WidgetGetTypeName(pointer) or nil
            local map = map_adapter(pointer, type_name, wrapper, x, y)
            if map then
                active_map = map
                if not coordinate_list.marker_sets[map] then coordinate_list:refresh_markers(map) end
                coordinate_list:map_click(map, x, y)
            elseif coordinate_list.capture and type_name and not logged_non_map_capture_types[type_name] then
                logged_non_map_capture_types[type_name] = true
                write(WARNING, "coordinate list: capture release hit " .. tostring(type_name) .. ", not a map widget")
            end
        end)
    end)
    if not ok then write(ERROR, "DTC setup failed: " .. tostring(err)) end
end

local function on_frame()
    if suspended or not coordinate_list then return end
    if map_markers then map_markers:update() end
    local now = DCS.getRealTime()
    if now - last_options_poll >= 0.25 then
        last_options_poll = now
        refresh_shortcut()
        if discover_maps then discover_maps() end
    end
end

local function suspend_feature()
    if suspended then return end
    suspended = true
    active_map = nil
    map_adapters = setmetatable({}, { __mode = "v" })
    logged_non_map_capture_types = {}
    left_ctrl_down, right_ctrl_down = false, false
    left_shift_down, right_shift_down = false, false
    left_alt_down, right_alt_down, shortcut_key_down = false, false, false
    write(INFO, "coordinate list: mission cleanup begin")
    if map_markers then map_markers:clear() end
    if coordinate_list then
        coordinate_list.marker_sets = {}
        coordinate_list:set_mode(nil)
        if coordinate_list.window then coordinate_list.window:setVisible(false) end
    end
    write(INFO, "coordinate list: mission cleanup complete")
end

function M.start()
    DCS.setUserCallbacks({
        onMissionLoadBegin = suspend_feature,
        onSimulationStop = suspend_feature,
        onSimulationStart = function()
            create_feature()
            last_options_poll = 0
            suspended = false
        end,
        onShowMainInterface = create_feature,
        onSimulationFrame = on_frame,
    })
    create_feature()
end

return M
