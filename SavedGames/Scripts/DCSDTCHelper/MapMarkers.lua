-- Screen-space marker windows sit above the native F10 scene. In Edit mode
-- they own mouse capture, so a marker press never starts native map panning.
local M = {}

function M.new(Gui, NativeMap, feature)
    local Window = require("Window")
    local Button = require("Button")
    local Skin = require("Skin")
    local self = { maps = {}, drag = nil, logged_errors = {} }

    local function report(stage, err)
        if not self.logged_errors[stage] then
            self.logged_errors[stage] = true
            feature.api.log("marker " .. stage .. " failed: " .. tostring(err), "warning")
        end
    end

    function self:cancel_drag()
        local drag = self.drag
        self.drag = nil
        if drag then
            drag.point.x, drag.point.y = drag.original_x, drag.original_y
            pcall(drag.control.releaseMouse, drag.control)
        end
    end

    function self:mouse_move(x, y)
        local drag = self.drag
        if not drag then return false end
        if not feature.edit then self:cancel_drag(); return true end
        if (x - drag.x) ^ 2 + (y - drag.y) ^ 2 >= 9 then drag.moved = true end
        if drag.moved then
            local mx, my = feature:map_point_from_click(drag.map, x, y)
            if mx then
                -- Preserve the grab offset, including grabs on the label.
                drag.point.x, drag.point.y = mx + drag.dx, my + drag.dy
            end
        end
        return true
    end

    function self:mouse_up(x, y, button)
        local drag = self.drag
        if not drag or button ~= 1 then return false end
        self:mouse_move(x, y)
        if self.drag ~= drag then return true end
        local px, py = drag.point.x, drag.point.y
        self:cancel_drag()
        for index, point in ipairs(feature.points) do
            if point == drag.point then
                if drag.moved then
                    point.selected = true
                    feature:move_point(index, px, py)
                else
                    feature:toggle_map_selection(index)
                end
                break
            end
        end
        return true
    end

    function self:remove(pointer)
        local entries = self.maps[pointer]
        if not entries then return end
        if self.drag and self.drag.pointer == pointer then self:cancel_drag() end
        for _, entry in ipairs(entries) do entry.window:kill() end
        self.maps[pointer] = nil
    end

    function self:refresh(pointer, map)
        local entries = self.maps[pointer] or {}
        self.maps[pointer] = entries
        for i = #entries, #feature.points + 1, -1 do
            entries[i].window:kill()
            entries[i] = nil
        end
        for index, point in ipairs(feature.points) do
            local entry = entries[index]
            if not entry then
                local window = Window.new(0, 0, 160, 22, "")
                window:setVisible(false)
                window:setTitleHeight(0)
                window:setDraggable(false)
                window:setResizable(false)
                window:setZOrder(90) -- Above F10's scene; below its toolbar/dialogs.
                local control = Button.new()
                control:setBounds(0, 0, 160, 22)
                window:insertWidget(control)
                entry = { window = window, control = control }
                entries[index] = entry
                control:addMouseDownCallback(function(widget, x, y, button)
                    if not feature.edit or button ~= 1 then return end
                    local mx, my = feature:map_point_from_click(map, x, y)
                    if not mx then return end
                    self:cancel_drag()
                    local target = entry.point
                    self.drag = { control = widget, pointer = pointer, map = map,
                        point = target, x = x, y = y, dx = target.x - mx, dy = target.y - my,
                        original_x = target.x, original_y = target.y }
                    widget:captureMouse()
                end)
                control:addMouseMoveCallback(function(_, x, y) self:mouse_move(x, y) end)
                control:addMouseUpCallback(function(_, x, y, button) self:mouse_up(x, y, button) end)
            end
            entry.point = point
            entry.control:setText("+  " .. (point.name ~= "" and point.name or ("Target " .. index)))
            local skin = Skin["buttonSkin_MENew2"]()
            for _, group in pairs(skin.skinData.states) do
                for _, state in pairs(group) do
                    if state.text then
                        state.text.color = point.selected and "0xffff00ff" or "0xff4d1aff"
                        state.text.horzAlign.type = "min"
                    end
                end
            end
            entry.control:setSkin(skin)
        end
        self:update()
    end

    function self:update()
        if self.drag and not feature.edit then self:cancel_drag() end
        for pointer, entries in pairs(self.maps) do
            local ok, err = pcall(function()
                local visible = Gui.WidgetGetVisible(pointer, true)
                if not visible then
                    for _, entry in ipairs(entries) do entry.window:setVisible(false) end
                    if self.drag and self.drag.pointer == pointer then self:cancel_drag() end
                    return
                end
                local sx, sy = Gui.WidgetToScreen(pointer, 0, 0)
                local width, height = Gui.WidgetGetSize(pointer)
                -- Invert the native 2D map transform using three local samples.
                -- This follows zoom, pan, and rotation without a guessed scale.
                local ox, oy = NativeMap.GetMapPoint(pointer, 0, 0)
                local ax, ay = NativeMap.GetMapPoint(pointer, 100, 0)
                local bx, by = NativeMap.GetMapPoint(pointer, 0, 100)
                ax, ay, bx, by = ax - ox, ay - oy, bx - ox, by - oy
                local det = ax * by - ay * bx
                for _, entry in ipairs(entries) do
                    local point = entry.point
                    local dx, dy = point.x - ox, point.y - oy
                    local x = det ~= 0 and 100 * (dx * by - dy * bx) / det or -1
                    local y = det ~= 0 and 100 * (ax * dy - ay * dx) / det or -1
                    local show = visible and x >= 0 and y >= 11 and x < width and y < height - 11
                    entry.window:setTransparentForUserInput(not feature.edit)
                    if show then
                        local w = math.min(160, width - x)
                        entry.window:setBounds(sx + x, sy + y - 11, w, 22)
                        entry.control:setBounds(0, 0, w, 22)
                    end
                    entry.window:setVisible(show)
                end
                if not visible and self.drag and self.drag.pointer == pointer then self:cancel_drag() end
            end)
            if not ok then
                report("projection", err)
                for _, entry in ipairs(entries) do entry.window:setVisible(false) end
                if self.drag and self.drag.pointer == pointer then self:cancel_drag() end
            end
        end
    end

    return self
end

return M
