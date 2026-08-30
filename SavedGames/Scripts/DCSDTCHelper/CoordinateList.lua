-- DCS DTC Helper -- session-only F10 coordinate collection.
--
-- This file deliberately has no dependency on the virtual keyboard. The DTC
-- feature module supplies the small DCS-specific adapter passed to new().

local M = {}

local ICON_CLASS = "P0091000041"
local TEXT_CLASS = "NavigationPointDescription"

local function safe_call(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil, a
end

function M.new(api)
    local self = {
        api = api,
        points = {},
        capture = false,
        marker_sets = setmetatable({}, { __mode = "k" }),
        next_marker_id = 9200000,
        status = "Open F10, then enable Capture.",
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

    function self:remove_markers(map)
        local objects = self.marker_sets[map]
        if objects and map and map.removeUserObjects then
            safe_call(map.removeUserObjects, map, objects)
        end
        self.marker_sets[map] = nil
    end

    function self:refresh_markers(map)
        if not map or not map.addUserObjects then return end
        self:remove_markers(map)
        if #self.points == 0 then return end

        local objects = {}
        for index, point in ipairs(self.points) do
            self.next_marker_id = self.next_marker_id + 1
            local color = point.selected and { 1, 1, 0 } or { 1, 0.3, 0.1 }
            table.insert(objects, {
                classKey = ICON_CLASS, id = self.next_marker_id, x = point.x, y = point.y,
                angle = 0, color = color, zOrder = 100,
            })
            self.next_marker_id = self.next_marker_id + 1
            table.insert(objects, {
                classKey = TEXT_CLASS, id = self.next_marker_id, x = point.x, y = point.y,
                title = tostring(index), color = color, offsetX = 8, offsetY = -8, zOrder = 101,
            })
        end
        local ok, err = pcall(map.addUserObjects, map, objects)
        if ok then
            self.marker_sets[map] = objects
        else
            self:set_status("Map marker update failed; see dcs.log.")
            api.log("map marker update failed: " .. tostring(err), "warning")
        end
    end

    function self:refresh_all_markers()
        for map in pairs(self.marker_sets) do self:refresh_markers(map) end
        local active = api.get_active_map()
        if active then self:refresh_markers(active) end
    end

    function self:refresh_action_state()
        if not self.window then return end
        self.capture_button:setText(self.capture and "Capture: ON" or "Capture: OFF")
        local selected_count = #self:selected_points()
        self.delete_button:setEnabled(selected_count > 0)
        self.transfer_button:setEnabled(selected_count == 1)
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
            label:addChangeCallback(function(control)
                point.name = control:getText() or ""
            end)
            self.grid:setCell(2, row, label)
            self.grid:setCell(3, row, static_cell(string.format("%.6f, %.6f", point.lat, point.lon)))
            self.grid:setCell(4, row, static_cell(string.format("%dm", point.elevation), true))
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

    function self:clear_all()
        self.points = {}
        self:set_status("All temporary targets cleared.")
        self:refresh_table()
        self:refresh_all_markers()
    end

    function self:capture_map_click(map, screen_x, screen_y)
        if not self.capture then return false end
        if not map or not map.getMapPoint then return false end
        -- FindWidgetAtScreenPoint already established that this release was on
        -- the map. getPointInMap() expects widget-local coordinates in some
        -- DCS versions, so calling it with global mouse coordinates would make
        -- otherwise valid F10 clicks fail.
        local x, y = safe_call(map.getMapPoint, map, screen_x, screen_y)
        if type(x) ~= "number" or type(y) ~= "number" then
            self:set_status("F10 map coordinate API was unavailable for this click.")
            return false
        end
        self:add_point(x, y)
        return true
    end

    function self:transfer_selected()
        local selected = self:selected_points()
        if #selected ~= 1 then
            self:set_status("Select exactly one target before sending it to JDAM.")
            return
        end
        local point = selected[1]
        local ok, message = api.transfer_to_jdam(point)
        self:set_status(message)
        if ok then api.log("sent " .. point.name .. " to F-14B(U) JDAM DTC") end
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
        self.delete_button = controls.btnDeleteSelected
        self.transfer_button = controls.btnSendToJDAM
        self.status_label = controls.sStatus
        self.grid = controls.gCapturedTargets

        self.capture_button:addMouseUpCallback(function()
            self.capture = not self.capture
            self:set_status(self.capture and "Capture enabled: release on the F10 map to add a target." or "Capture disabled.")
            self:refresh_action_state()
        end)
        self.delete_button:addMouseUpCallback(function() self:delete_selected() end)
        controls.btnClearAll:addMouseUpCallback(function() self:clear_all() end)
        self.transfer_button:addMouseUpCallback(function() self:transfer_selected() end)
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
