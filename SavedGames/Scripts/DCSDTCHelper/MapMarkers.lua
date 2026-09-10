-- Screen-space marker windows sit above the native F10 scene. In Edit mode
-- they own mouse capture, so a marker press never starts native map panning.
local M = {}

function M.new(Gui, NativeMap, feature)
    local Window = require("Window")
    local Button = require("Button")
    local Static = require("Static")
    local Skin = require("Skin")
    local self = { maps = {}, drag = nil, logged_errors = {}, spare_entries = {} }

    local function transparent_surface()
        return { bkg = {
            file = "", center_center = "0x00000000", center_top = "0x00000000",
            center_bottom = "0x00000000", left_top = "0x00000000", left_center = "0x00000000",
            left_bottom = "0x00000000", right_top = "0x00000000", right_center = "0x00000000",
            right_bottom = "0x00000000",
        }, picture = { file = "", color = "0x00000000" } }
    end

    -- Remove every painted surface, including the WindowView and header skins.
    -- Input transparency alone does not make a dxgui widget visually transparent.
    local function clear_surfaces(skin)
        local data = skin.skinData
        if data.params then data.params.name = nil end
        for state in pairs(data.states or {}) do data.states[state] = { transparent_surface() } end
        for _, child in pairs(data.skins or {}) do clear_surfaces(child) end
    end

    local function label_skin(color)
        local skin = Skin["buttonSkin_MENew2"]()
        skin.skinData.params.name = nil
        skin.skinData.params.insets = { left = 22, right = 0, top = 0, bottom = 0 }
        for name in pairs(skin.skinData.states) do
            -- A fresh text-only state prevents button backgrounds, focus borders,
            -- and pressed-state offsets from returning on hover/click.
            local state = transparent_surface()
            state.text = {
                color = color, font = "DejaVuLGCSansCondensed-Bold.ttf", fontSize = 12,
                horzAlign = { type = "min" }, vertAlign = { type = "middle" },
                shadowOffset = { horz = 1, vert = 1 },
            }
            skin.skinData.states[name] = { state }
        end
        return skin
    end

    local function stroke_skin(color)
        return { version = 1, skinData = { type = "Static", params = {}, states = {
            released = { { bkg = { center_center = color } } },
            disabled = { { bkg = { center_center = color } } },
        } } }
    end

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

    local function retire(entry)
        -- Keep native windows alive across DCS's modal/menu transition. WindowKill
        -- leaves native input/hover state outside Lua's control. Reuse the hidden
        -- windows instead, retaining only the largest simultaneous marker count.
        entry.window:setTransparentForUserInput(true)
        entry.window:setVisible(false)
        entry.point, entry.map, entry.pointer = nil, nil, nil
        table.insert(self.spare_entries, entry)
    end

    function self:remove(pointer)
        local entries = self.maps[pointer]
        if not entries then return end
        if self.drag and self.drag.pointer == pointer then self:cancel_drag() end
        for _, entry in ipairs(entries) do retire(entry) end
        if entries.map then feature.marker_sets[entries.map] = nil end
        self.maps[pointer] = nil
    end

    function self:clear()
        self:cancel_drag()
        -- Drop native map references before touching our own windows. Never
        -- probe a mission's map while DCS is tearing its scene down.
        local maps = self.maps
        self.maps = {}
        for _, entries in pairs(maps) do
            if entries.map then feature.marker_sets[entries.map] = nil end
            for _, entry in ipairs(entries) do
                local ok, err = pcall(function()
                    retire(entry)
                end)
                if not ok then report("cleanup", err) end
            end
        end
        if #self.spare_entries > 0 then
            feature.api.log("marker cleanup: " .. #self.spare_entries .. " windows hidden for reuse; none killed", "info")
        end
    end

    function self:refresh(pointer, map)
        local entries = self.maps[pointer] or {}
        if entries.failed then return end
        self.maps[pointer] = entries
        entries.map = map
        for i = #entries, #feature.points + 1, -1 do
            retire(entries[i])
            entries[i] = nil
        end
        for index, point in ipairs(feature.points) do
            local entry = entries[index] or table.remove(self.spare_entries)
            if not entry then
                local window = Window.new(0, 0, 170, 22, "")
                window:setVisible(false)
                local skin = Skin["windowSkinTransparent"]()
                clear_surfaces(skin)
                skin.skinData.params.headerHeight = 0
                skin.skinData.params.insets = { left = 0, right = 0, top = 0, bottom = 0 }
                window:setSkin(skin)
                window:setDraggable(false)
                window:setResizable(false)
                window:setZOrder(201) -- DTC's map window is at 200; F10's scene is below it.
                local control = Button.new()
                control:setBounds(0, 0, 170, 22)
                window:insertWidget(control)
                local horizontal, vertical = Static.new(), Static.new()
                -- Both strokes have their geometric centre at local (10, 11).
                -- Overlay widgets draw above the label but never steal its input.
                horizontal:setBounds(3, 10, 14, 2)
                vertical:setBounds(9, 4, 2, 14)
                window:insertOverlayWidget(horizontal)
                window:insertOverlayWidget(vertical)
                entry = { window = window, control = control, horizontal = horizontal, vertical = vertical }
                entries[index] = entry
                control:addMouseDownCallback(function(widget, x, y, button)
                    if not entry.map or not feature.edit or button ~= 1 then return end
                    local mx, my = feature:map_point_from_click(entry.map, x, y)
                    if not mx then return end
                    self:cancel_drag()
                    local target = entry.point
                    self.drag = { control = widget, pointer = entry.pointer, map = entry.map,
                        point = target, x = x, y = y, dx = target.x - mx, dy = target.y - my,
                        original_x = target.x, original_y = target.y }
                    widget:captureMouse()
                end)
                control:addMouseMoveCallback(function(_, x, y) self:mouse_move(x, y) end)
                control:addMouseUpCallback(function(_, x, y, button) self:mouse_up(x, y, button) end)
            end
            entries[index] = entry
            entry.pointer, entry.map = pointer, map
            entry.point = point
            entry.control:setText(point.name ~= "" and point.name or ("Target " .. index))
            local color = point.selected and "0xffff00ff" or "0xff4d1aff"
            entry.control:setSkin(label_skin(color))
            entry.horizontal:setSkin(stroke_skin(color))
            entry.vertical:setSkin(stroke_skin(color))
        end
        self:update()
    end

    function self:update()
        if self.drag and not feature.edit then self:cancel_drag() end
        -- Probe the native surface without our own marker windows intercepting
        -- the hit test. This also prevents F10 markers showing over the DTC map.
        for _, entries in pairs(self.maps) do
            for _, entry in ipairs(entries) do
                if not self.drag or self.drag.control ~= entry.control then entry.window:setVisible(false) end
            end
        end
        for pointer, entries in pairs(self.maps) do
            if not entries.failed then
                local stage = "map visibility"
                local ok, err = pcall(function()
                    local visible = Gui.WidgetGetVisible(pointer, true)
                    if not visible then
                        for _, entry in ipairs(entries) do entry.window:setVisible(false) end
                        if self.drag and self.drag.pointer == pointer then self:cancel_drag() end
                        return
                    end
                    stage = "map transform"
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
                        local show = visible and x >= 10 and y >= 11 and x < width - 10 and y < height - 11
                        if show then
                            stage = "marker hit test"
                            local hit = Gui.FindWidgetAtScreenPoint(sx + x, sy + y)
                            show = hit == pointer or (self.drag ~= nil and self.drag.point == point and self.drag.pointer == pointer)
                        end
                        stage = "marker layout"
                        entry.window:setTransparentForUserInput(not feature.edit)
                        if show then
                            local w = math.min(170, width - x + 10)
                            entry.window:setBounds(sx + x - 10, sy + y - 11, w, 22)
                            entry.control:setBounds(0, 0, w, 22)
                        end
                        stage = "marker visibility"
                        entry.window:setVisible(not not show)
                    end
                    if not visible and self.drag and self.drag.pointer == pointer then self:cancel_drag() end
                end)
                if not ok then
                    -- A projection error does not establish that the native map was
                    -- destroyed. Hide and quarantine its overlays until cleanup;
                    -- do not kill windows under DCS's active input processing.
                    entries.failed = true
                    if self.drag and self.drag.pointer == pointer then self:cancel_drag() end
                    for _, entry in ipairs(entries) do
                        pcall(entry.window.setVisible, entry.window, false)
                    end
                    report("projection (" .. stage .. ")", err)
                end
            end
        end
    end

    return self
end

return M
