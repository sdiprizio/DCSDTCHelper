-- DCS DTC Helper -- session-only F10 coordinate collection.
--
-- This file deliberately has no dependency on the virtual keyboard. The DTC
-- feature module supplies the small DCS-specific adapter passed to new().

local M = {}

local function safe_call(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil, a
end

local COORDINATE_MODES = {
    { name = "Decimal Degrees", key = "dd" },
    { name = "Degrees / Minutes", key = "ddm" },
    { name = "Degrees / Minutes / Seconds", key = "dms" },
    { name = "MGRS", key = "mgrs" },
}

local function format_degrees(value, positive, negative)
    return string.format("%.6f°%s", math.abs(value), value < 0 and negative or positive)
end

local function format_degrees_minutes(value, positive, negative)
    local absolute = math.abs(value)
    local degrees = math.floor(absolute)
    local minutes = (absolute - degrees) * 60
    return string.format("%d° %06.3f'%s", degrees, minutes, value < 0 and negative or positive)
end

local function format_degrees_minutes_seconds(value, positive, negative)
    local absolute = math.abs(value)
    local degrees = math.floor(absolute)
    local total_seconds = (absolute - degrees) * 3600
    local minutes = math.floor(total_seconds / 60)
    local seconds = total_seconds - minutes * 60
    return string.format("%d° %02d' %05.2f\"%s", degrees, minutes, seconds, value < 0 and negative or positive)
end

-- WGS-84 latitude/longitude to the standard 1 m MGRS grid used by DCS maps.
local function format_mgrs(latitude, longitude)
    if latitude < -80 or latitude > 84 then return "MGRS unavailable at this latitude" end
    local zone = math.floor((longitude + 180) / 6) + 1
    if latitude >= 56 and latitude < 64 and longitude >= 3 and longitude < 12 then zone = 32 end
    if latitude >= 72 and latitude < 84 then
        if longitude >= 0 and longitude < 9 then zone = 31
        elseif longitude < 21 then zone = 33
        elseif longitude < 33 then zone = 35
        elseif longitude < 42 then zone = 37 end
    end
    local central_meridian = (zone - 1) * 6 - 180 + 3
    local radians = math.pi / 180
    local lat = latitude * radians
    local lon_delta = (longitude - central_meridian) * radians
    local a, eccentricity_squared, scale = 6378137.0, 0.00669438, 0.9996
    local eccentricity_prime_squared = eccentricity_squared / (1 - eccentricity_squared)
    local sin_lat, cos_lat = math.sin(lat), math.cos(lat)
    local tan_lat = math.tan(lat)
    local n = a / math.sqrt(1 - eccentricity_squared * sin_lat * sin_lat)
    local t = tan_lat * tan_lat
    local c = eccentricity_prime_squared * cos_lat * cos_lat
    local aa = cos_lat * lon_delta
    local m = a * ((1 - eccentricity_squared / 4 - 3 * eccentricity_squared ^ 2 / 64 - 5 * eccentricity_squared ^ 3 / 256) * lat
        - (3 * eccentricity_squared / 8 + 3 * eccentricity_squared ^ 2 / 32 + 45 * eccentricity_squared ^ 3 / 1024) * math.sin(2 * lat)
        + (15 * eccentricity_squared ^ 2 / 256 + 45 * eccentricity_squared ^ 3 / 1024) * math.sin(4 * lat)
        - (35 * eccentricity_squared ^ 3 / 3072) * math.sin(6 * lat))
    local easting = scale * n * (aa + (1 - t + c) * aa ^ 3 / 6 + (5 - 18 * t + t ^ 2 + 72 * c - 58 * eccentricity_prime_squared) * aa ^ 5 / 120) + 500000
    local northing = scale * (m + n * tan_lat * (aa ^ 2 / 2 + (5 - t + 9 * c + 4 * c ^ 2) * aa ^ 4 / 24 + (61 - 58 * t + t ^ 2 + 600 * c - 330 * eccentricity_prime_squared) * aa ^ 6 / 720))
    if latitude < 0 then northing = northing + 10000000 end
    local bands = "CDEFGHJKLMNPQRSTUVWX"
    local band = string.sub(bands, math.floor((latitude + 80) / 8) + 1, math.floor((latitude + 80) / 8) + 1)
    local column_sets = { "ABCDEFGH", "JKLMNPQR", "STUVWXYZ" }
    local row_sets = { "ABCDEFGHJKLMNPQRSTUV", "FGHJKLMNPQRSTUVABCDE" }
    local column = string.sub(column_sets[(zone - 1) % 3 + 1], math.floor(easting / 100000), math.floor(easting / 100000))
    local row_index = math.floor(northing / 100000) % 20 + 1
    local row = string.sub(row_sets[(zone - 1) % 2 + 1], row_index, row_index)
    return string.format("%d%s %s%s %05d %05d", zone, band, column, row, math.floor(easting % 100000), math.floor(northing % 100000))
end

function M.new(api)
    local self = {
        api = api,
        points = {},
        capture = false,
        edit = false,
        marker_sets = setmetatable({}, { __mode = "k" }),
        status = "Open F10, then enable Add.",
        coordinate_mode = 1,
        updating_select_all = false,
        window = nil,
    }

    function self:set_status(message)
        self.status = message
        if self.status_label then self.status_label:setText(message) end
    end

    function self:selected_points()
        local selected = {}
        for _, point in ipairs(self.points) do
            if point.selected then table.insert(selected, point) end
        end
        return selected
    end

    function self:refresh_markers(map)
        if not map or not map.refreshMarkers then return end
        local ok, err = pcall(map.refreshMarkers, map)
        if ok then
            self.marker_sets[map] = true
        else
            self:set_status("Map marker update failed; see dcs.log.")
            api.log("map marker update failed: " .. tostring(err), "warning")
        end
    end

    function self:refresh_all_markers()
        for map in pairs(self.marker_sets) do self:refresh_markers(map) end
        local active = api.get_active_map()
        if active and not self.marker_sets[active] then self:refresh_markers(active) end
    end

    function self:refresh_action_state()
        if not self.window then return end
        if self.add_skin_active then
            self.capture_button:setSkin(self.capture and self.add_skin_active or self.add_skin_inactive)
            self.edit_button:setSkin(self.edit and self.add_skin_active or self.add_skin_inactive)
        end
        local selected_count = #self:selected_points()
        self.delete_button:setEnabled(selected_count > 0)
        if self.select_all_button then
            self.updating_select_all = true
            self.select_all_button:setState(#self.points > 0 and selected_count == #self.points)
            self.updating_select_all = false
        end
    end

    function self:format_coordinates(point)
        local mode = COORDINATE_MODES[self.coordinate_mode]
        if mode.key == "dd" then
            return format_degrees(point.lat, "N", "S") .. ", " .. format_degrees(point.lon, "E", "W")
        elseif mode.key == "ddm" then
            return format_degrees_minutes(point.lat, "N", "S") .. ", " .. format_degrees_minutes(point.lon, "E", "W")
        elseif mode.key == "dms" then
            return format_degrees_minutes_seconds(point.lat, "N", "S") .. ", " .. format_degrees_minutes_seconds(point.lon, "E", "W")
        end
        return format_mgrs(point.lat, point.lon)
    end

    function self:cycle_coordinate_mode()
        self.coordinate_mode = self.coordinate_mode % #COORDINATE_MODES + 1
        local mode = COORDINATE_MODES[self.coordinate_mode]
        self.coordinate_mode_button:setText("Coordinates: " .. mode.name)
        self:set_status("Coordinate display: " .. mode.name .. ".")
        self:refresh_table()
    end

    function self:set_all_selected(selected)
        for _, point in ipairs(self.points) do point.selected = selected end
        self:refresh_table()
        self:refresh_all_markers()
    end

    function self:refresh_table()
        if not self.grid then return end
        local Static = require("Static")
        local CheckBox = require("CheckBox")
        local EditBox = require("EditBox")
        local Skin = require("Skin")
        local Align = require("Align")

        local function static_cell(text, centered)
            local cell = Static.new(centered and tostring(text) or " " .. tostring(text))
            local skin = Skin["staticSkin_ME"]()
            if centered then
                for _, state in pairs(skin.skinData.states.disabled) do
                    if state.text then state.text.horzAlign.type = Align.center end
                end
                for _, state in pairs(skin.skinData.states.released) do
                    if state.text then state.text.horzAlign.type = Align.center end
                end
            end
            cell:setSkin(skin)
            return cell
        end

        local function checkbox_cell(selected)
            local cell = CheckBox.new()
            local skin = Skin["checkBoxSkin_MENew"]()
            for _, state_name in ipairs({ "pressed", "disabled", "hover", "released" }) do
                for _, state in pairs(skin.skinData.states[state_name]) do
                    if state.check then state.check.horzAlign.type = Align.center end
                end
            end
            cell:setSkin(skin)
            cell:setState(selected)
            return cell
        end

        self.grid:removeAllRows()
        for index, point in ipairs(self.points) do
            self.grid:insertRow(20)
            local row = index - 1

            local selected = checkbox_cell(point.selected == true)
            selected:addChangeCallback(function(control)
                point.selected = control:getState()
                self:refresh_action_state()
                self:refresh_all_markers()
            end)
            self.grid:setCell(0, row, selected)
            self.grid:setCell(1, row, static_cell(index, true))

            local label = EditBox.new(point.name)
            label:setSkin(Skin["editBoxSkin_ME"]())
            -- EditBox's native change callback dispatches onChange; the virtual
            -- keyboard also calls it after programmatically setting the text.
            label.onChange = function(control)
                point.name = control:getText() or ""
                self:refresh_all_markers()
            end
            self.grid:setCell(2, row, label)
            self.grid:setCell(3, row, static_cell(self:format_coordinates(point)))
            self.grid:setCell(4, row, static_cell(string.format("%d ft", math.floor(point.elevation * 3.28084 + 0.5)), true))
        end
        self:refresh_action_state()
    end

    function self:add_point(x, y)
        local lat, lon = api.to_lat_lon(x, y)
        if not lat or not lon then
            self:set_status("Could not convert this map point to latitude/longitude.")
            return false
        end
        local elevation = api.terrain_height(x, y) or 0
        local index = #self.points + 1
        table.insert(self.points, {
            name = "Target " .. index, x = x, y = y, lat = lat, lon = lon,
            elevation = math.floor(elevation + 0.5),
        })
        self.points[index].selected = true
        self:set_status("Captured Target " .. index .. ".")
        self:refresh_table()
        self:refresh_all_markers()
        api.log(string.format("captured Target %d: %.6f, %.6f, %dm", index, lat, lon, elevation))
        return true
    end

    function self:delete_selected()
        local removed = 0
        for index = #self.points, 1, -1 do
            if self.points[index].selected then
                table.remove(self.points, index)
                removed = removed + 1
            end
        end
        if removed == 0 then return end
        self:set_status(string.format("Deleted %d target%s.", removed, removed == 1 and "" or "s"))
        self:refresh_table()
        self:refresh_all_markers()
    end

    function self:map_point_from_click(map, screen_x, screen_y)
        if not map or not map.getMapPoint then return nil, nil end
        local x, y = safe_call(map.getMapPoint, map, screen_x, screen_y)
        if type(x) ~= "number" or type(y) ~= "number" then
            self:set_status("F10 map coordinate API was unavailable for this click.")
            return nil, nil
        end
        return x, y
    end

    function self:toggle_map_selection(index)
        local point = self.points[index]
        if not point then return false end
        point.selected = not point.selected
        self:set_status((point.selected and "Selected " or "Deselected ") .. (point.name ~= "" and point.name or ("Target " .. index)) .. ".")
        self:refresh_table()
        self:refresh_all_markers()
        return true
    end

    function self:move_point(index, x, y)
        local point = self.points[index]
        local lat, lon = api.to_lat_lon(x, y)
        if not point or not lat or not lon then
            self:set_status("Could not convert the new map point to latitude/longitude.")
            return false
        end
        point.x, point.y = x, y
        point.lat, point.lon = lat, lon
        point.elevation = math.floor((api.terrain_height(x, y) or 0) + 0.5)
        self:set_status("Moved " .. (point.name ~= "" and point.name or ("Target " .. index)) .. ".")
        self:refresh_table()
        self:refresh_all_markers()
        return true
    end

    function self:set_mode(mode)
        if mode == "add" and self.capture then mode = nil
        elseif mode == "edit" and self.edit then mode = nil end
        self.capture = mode == "add"
        self.edit = mode == "edit"
        if self.capture then
            self:set_status("Add enabled: release on the F10 map to add a target.")
        elseif self.edit then
            self:set_status("Edit enabled: drag a marker or label to move it; click to select.")
        else
            self:set_status("Add and Edit disabled.")
        end
        self:refresh_action_state()
    end

    function self:map_click(map, screen_x, screen_y)
        -- FindWidgetAtScreenPoint already established that this release was on
        -- the map. getPointInMap() expects widget-local coordinates in some
        -- DCS versions, so calling it with global mouse coordinates would make
        -- otherwise valid F10 clicks fail.
        local x, y = self:map_point_from_click(map, screen_x, screen_y)
        if not x then return false end
        if self.capture then
            self:add_point(x, y)
            return true
        end
        return false
    end

    function self:create_ui()
        if self.window then return end
        local DialogLoader = require("DialogLoader")
        if not lfs or not lfs.writedir then
            error("Saved Games directory is unavailable for the DTC dialog")
        end
        local dialog_path = lfs.writedir() .. "Scripts\\DCSDTCHelper\\DCSDTCHelper.dlg"
        self.window = DialogLoader.spawnDialogFromFile(dialog_path, {})
        self.window:setZOrder(10001)
        local controls = self.window.pMain
        self.capture_button = controls.btnCapture
        self.edit_button = controls.btnEdit
        self.delete_button = controls.btnDeleteSelected
        self.coordinate_mode_button = controls.btnCoordinateMode
        self.select_all_button = controls.cbSelectAll
        self.status_label = controls.sStatus
        self.grid = controls.gCapturedTargets
        local Skin = require("Skin")
        local function add_skin(active)
            local skin = Skin["buttonSkin_MENew2"]()
            if active then
                for _, state_group in pairs(skin.skinData.states) do
                    for _, state in pairs(state_group) do
                        if state.picture then state.picture.color = "0x6b3e1fff" end
                        if state.text then state.text.color = "0xffa500ff" end
                    end
                end
            end
            return skin
        end
        self.add_skin_inactive = add_skin(false)
        self.add_skin_active = add_skin(true)

        self.capture_button:addMouseUpCallback(function()
            self:set_mode("add")
        end)
        self.edit_button:addMouseUpCallback(function() self:set_mode("edit") end)
        self.delete_button:addMouseUpCallback(function() self:delete_selected() end)
        self.coordinate_mode_button:addMouseUpCallback(function() self:cycle_coordinate_mode() end)
        self.select_all_button:addChangeCallback(function(control)
            if not self.updating_select_all then self:set_all_selected(control:getState()) end
        end)
        self.window:setVisible(false)
        self:refresh_table()
        self:set_status(self.status)
    end

    function self:toggle()
        self:create_ui()
        self.window:setVisible(not self.window:getVisible())
        if self.window:getVisible() then self:refresh_all_markers() end
    end

    return self
end

return M
