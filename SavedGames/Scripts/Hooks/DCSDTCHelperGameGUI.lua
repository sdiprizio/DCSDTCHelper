-- DCS DTC Helper -- Saved Games GameGUI hook
--
-- Install under the active DCS Saved Games directory as:
--   Scripts\Hooks\DCSDTCHelperGameGUI.lua
--
-- This milestone displays a self-contained, VR-clickable keyboard. It keeps its
-- own text buffer while character delivery to an arbitrary existing DCS field is
-- investigated separately.

local TAG = "DCSDTCHelper"
local INFO = (log and log.INFO) or 0
local WARNING = (log and log.WARNING) or 1
local ERROR = (log and log.ERROR) or 2
local keyboard
local last_focus_scan = 0

-- GameGUI hooks do not include the DTC UI directory by default. Add only the
-- installed DCS UI search paths needed to inspect the active DTC dialog.
package.path = package.path
    .. ";.\\Scripts\\UI\\?.lua"
    .. ";.\\Scripts\\UI\\DTC_manager\\?.lua"
    .. ";.\\MissionEditor\\modules\\?.lua"

local function describe_widget(widget)
    local name = widget.getName and widget:getName() or "<unnamed>"
    return widget:getTypeName() .. " name=" .. tostring(name) .. " ptr=" .. tostring(widget.widget)
end

local function describe_target(target)
    if not target then
        return "<none>"
    end
    return target.type_name .. " ptr=" .. tostring(target.pointer)
        .. " wrapper=" .. tostring(target.wrapper ~= nil)
        .. " source=" .. tostring(target.source)
        .. " selection=" .. tostring(target.selection and target.selection.index_begin)
        .. ":" .. tostring(target.selection and target.selection.index_end)
end

local function write(level, message)
    if log and log.write then
        log.write(TAG, level, message)
    else
        print(TAG .. ": " .. message)
    end
end

local function probe_module(name)
    local ok, value = pcall(require, name)
    if ok then
        write(INFO, "module available: " .. name .. " (" .. type(value) .. ")")
        return true
    end

    write(WARNING, "module unavailable: " .. name .. " (" .. tostring(value) .. ")")
    return false
end

local function on_simulation_start()
    if keyboard and keyboard.window then
        keyboard.window:setVisible(true)
        write(INFO, "existing virtual keyboard window restored")
        return
    end

    write(INFO, "capability probe started")
    probe_module("dxgui")
    probe_module("DialogLoader")
    probe_module("Button")
    probe_module("EditBox")
    probe_module("Window")
    write(INFO, "capability probe completed")

    local ok, err = pcall(function()
        local Gui = require("dxgui")
        local Window = require("Window")
        local Button = require("Button")
        local EditBox = require("EditBox")
        local Static = require("Static")
        local Widget = require("Widget")

        local screen_width, screen_height = Gui.GetWindowSize()
        -- Keep this panel compact enough to leave the DTC map and its fields
        -- usable. This is approximately half the first prototype's footprint.
        local width, height = 450, 175
        local x = math.max(20, math.floor((screen_width - width) / 2))
        local y = math.max(20, math.floor((screen_height - height) / 2))

        keyboard = {
            buttons = {},
            text = "",
            parent = nil,
            window = Window.new(x, y, width, height, "DCS DTC Helper - Virtual Keyboard"),
        }

        keyboard.window:setDraggable(true)
        keyboard.window:setHasCursor(true)
        -- The Mission Editor map and DTC dialogs are regular dxgui windows that
        -- cover the default Z layer. Match DCS's own overlay convention so this
        -- keyboard remains above them without modifying their source files.
        keyboard.window:setZOrder(10002)

        local function refresh_output()
            -- The original preview field made it look as though input was being
            -- sent to DTC. Keep the keyboard compact and write only to its target.
        end

        local function set_status(text)
            keyboard.status:setText(text)
        end

        local function read_selection(pointer)
            local ok, line_begin, index_begin, line_end, index_end = pcall(Gui.EditBoxGetSelection, pointer)
            if not ok then
                write(WARNING, "selection read failed: " .. tostring(line_begin))
                return { line_begin = 0, index_begin = 0, line_end = 0, index_end = 0 }
            end
            return {
                line_begin = line_begin,
                index_begin = index_begin,
                line_end = line_end,
                index_end = index_end,
            }
        end

        local function capture_target(pointer, wrapper, source)
            local type_name = wrapper and wrapper:getTypeName() or Gui.WidgetGetTypeName(pointer)
            local changed = not keyboard.target or keyboard.target.pointer ~= pointer
            keyboard.target = {
                pointer = pointer,
                wrapper = wrapper,
                type_name = type_name,
                source = source,
                selection = read_selection(pointer),
            }
            if changed then
                set_status("Target field selected")
                write(INFO, "target captured: " .. describe_target(keyboard.target))
            end
        end

        keyboard.capture_target = capture_target

        Gui.AddMouseCallback("down", function(x, y)
            local pointer = Gui.FindWidgetAtScreenPoint(x, y)
            if not pointer then
                write(INFO, "global mouse down: no widget at " .. x .. "," .. y)
                return
            end

            local type_name = Gui.WidgetGetTypeName(pointer)
            local wrapper = Widget.widgets[pointer]
            write(INFO, "global mouse down: type=" .. tostring(type_name)
                .. " ptr=" .. tostring(pointer)
                .. " wrapper=" .. tostring(wrapper ~= nil))

            if type_name == "EditBox" then
                capture_target(pointer, wrapper, "global mouse")
            end
        end)
        -- Mouse-down identifies the widget; mouse-up sees the selection DCS
        -- has assigned after placing its native caret inside that EditBox.
        Gui.AddMouseCallback("up", function(x, y)
            local pointer = Gui.FindWidgetAtScreenPoint(x, y)
            if pointer and Gui.WidgetGetTypeName(pointer) == "EditBox" then
                capture_target(pointer, Widget.widgets[pointer], "global mouse up")
                write(INFO, "global mouse up: caret captured for " .. describe_target(keyboard.target))
            end
        end)
        write(INFO, "global widget diagnostics enabled")

        local function apply_to_target(action, value)
            local target = keyboard.target
            if target and target.type_name == "EditBox" then
                local focused_before = target.wrapper
                    and target.wrapper:getFocused()
                    or Gui.WidgetGetFocused(target.pointer)
                local selection = target.selection or read_selection(target.pointer)
                write(INFO, "key " .. action .. " target=" .. describe_target(target)
                    .. " focusedBefore=" .. tostring(focused_before)
                    .. " selectionBefore=" .. tostring(selection.index_begin)
                    .. ":" .. tostring(selection.index_end))
                local current = target.wrapper
                    and (target.wrapper:getText() or "")
                    or (Gui.WidgetGetText(target.pointer) or "")
                local next_text
                local caret
                local first = math.max(0, math.min(selection.index_begin or 0, #current))
                local last = math.max(first, math.min(selection.index_end or first, #current))

                if selection.line_begin ~= selection.line_end then
                    write(WARNING, "multiline selection is not supported; using its first-line caret")
                    last = first
                end

                if action == "append" then
                    next_text = string.sub(current, 1, first) .. value .. string.sub(current, last + 1)
                    caret = first + #value
                elseif action == "backspace" then
                    if first ~= last then
                        next_text = string.sub(current, 1, first) .. string.sub(current, last + 1)
                        caret = first
                    elseif first > 0 then
                        next_text = string.sub(current, 1, first - 1) .. string.sub(current, first + 1)
                        caret = first - 1
                    else
                        next_text = current
                        caret = 0
                    end
                elseif action == "clear" then
                    next_text = ""
                    caret = 0
                end

                if target.wrapper then
                    target.wrapper:setText(next_text)
                else
                    Gui.WidgetSetText(target.pointer, next_text)
                    write(WARNING, "target has no Lua wrapper; its change handler cannot be invoked")
                end
                -- DCS dialogs generally update their backing data from the
                -- EditBox change handler. setText() alone does not emit it.
                if target.wrapper and target.wrapper.onChange then
                    target.wrapper:onChange()
                end
                -- Clicking a virtual key transfers native dxgui focus to this
                -- window. Restore it to the edited DCS field immediately so the
                -- next key continues writing to the same place.
                if target.wrapper then
                    target.wrapper:setFocused(true)
                else
                    Gui.WidgetSetFocused(target.pointer, true)
                end
                Gui.EditBoxSetSelection(target.pointer, 0, caret, 0, caret)
                target.selection = read_selection(target.pointer)
                local focused_after = target.wrapper
                    and target.wrapper:getFocused()
                    or Gui.WidgetGetFocused(target.pointer)
                write(INFO, "key " .. action .. " completed focusedAfter=" .. tostring(focused_after)
                    .. " selectionAfter=" .. tostring(target.selection.index_begin)
                    .. ":" .. tostring(target.selection.index_end))

                keyboard.text = next_text
                refresh_output()
                set_status("Target field updated")
                return true
            end

            return false
        end

        local function add_alpha_key(label, value, row, column, columns)
            local margin = 12
            local gap = 2
            local row_height = 23
            local usable_width = 274 - (gap * (columns - 1))
            local key_width = math.floor(usable_width / columns)
            local button = Button.new(label)
            button:setBounds(margin + (column - 1) * (key_width + gap), 28 + (row - 1) * (row_height + gap), key_width, row_height)
            -- dxgui transfers focus during mouse-down. Handle the key on mouse-up
            -- so the target EditBox can be focused again afterwards.
            button:addMouseUpCallback(function()
                if not apply_to_target("append", value) then
                    keyboard.text = keyboard.text .. value
                    refresh_output()
                    set_status("Click a DCS text field first")
                end
            end)
            keyboard.window:insertWidget(button)
            table.insert(keyboard.buttons, button)
        end

        local rows = {
            { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
            { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
            { "Z", "X", "C", "V", "B", "N", "M", "-", "." },
        }

        for row_index, row in ipairs(rows) do
            for column, key in ipairs(row) do
                add_alpha_key(key, key, row_index, column, #row)
            end
        end

        local backspace = Button.new("DEL")
        backspace:setBounds(12, 103, 62, 23)
        backspace:addMouseUpCallback(function()
            if not apply_to_target("backspace") then
                keyboard.text = string.sub(keyboard.text, 1, -2)
                refresh_output()
                set_status("Click a DCS text field first")
            end
        end)
        keyboard.window:insertWidget(backspace)
        table.insert(keyboard.buttons, backspace)

        local space = Button.new("SPACE")
        space:setBounds(76, 103, 138, 23)
        space:addMouseUpCallback(function()
            if not apply_to_target("append", " ") then
                keyboard.text = keyboard.text .. " "
                refresh_output()
                set_status("Click a DCS text field first")
            end
        end)
        keyboard.window:insertWidget(space)
        table.insert(keyboard.buttons, space)

        local clear = Button.new("CLEAR")
        clear:setBounds(216, 103, 70, 23)
        clear:addMouseUpCallback(function()
            if not apply_to_target("clear") then
                keyboard.text = ""
                refresh_output()
                set_status("Click a DCS text field first")
            end
        end)
        keyboard.window:insertWidget(clear)
        table.insert(keyboard.buttons, clear)

        local function add_coordinate_key(label, value, row, column)
            local gap = 3
            local key_width = 42
            local key_height = 23
            local button = Button.new(label)
            button:setBounds(303 + (column - 1) * (key_width + gap), 28 + (row - 1) * (key_height + gap), key_width, key_height)
            button:addMouseUpCallback(function()
                if not apply_to_target("append", value) then
                    keyboard.text = keyboard.text .. value
                    refresh_output()
                    set_status("Click a DCS text field first")
                end
            end)
            keyboard.window:insertWidget(button)
            table.insert(keyboard.buttons, button)
        end

        local coordinate_rows = {
            { "7", "8", "9" },
            { "4", "5", "6" },
            { "1", "2", "3" },
            { "-", "0", "." },
        }

        for row_index, row in ipairs(coordinate_rows) do
            for column, key in ipairs(row) do
                add_coordinate_key(key, key, row_index, column)
            end
        end

        local coordinate_backspace = Button.new("DEL")
        coordinate_backspace:setBounds(303, 132, 132, 18)
        coordinate_backspace:addMouseUpCallback(function()
            if not apply_to_target("backspace") then
                keyboard.text = string.sub(keyboard.text, 1, -2)
                refresh_output()
                set_status("Click a DCS text field first")
            end
        end)
        keyboard.window:insertWidget(coordinate_backspace)
        table.insert(keyboard.buttons, coordinate_backspace)

        keyboard.status = Static.new("Click a DCS text field, then use this keyboard.")
        keyboard.status:setBounds(12, 154, width - 24, 12)
        keyboard.window:insertWidget(keyboard.status)

        keyboard.window:setVisible(true)
        write(INFO, "virtual keyboard window shown")
    end)

    if not ok then
        write(ERROR, "virtual keyboard window failed: " .. tostring(err))
    end
end

local function track_focused_edit_box()
    if not keyboard or not keyboard.window then
        return
    end

    local now = DCS.getRealTime()
    if now - last_focus_scan < 0.1 then
        return
    end
    last_focus_scan = now

    local function find_focused_edit_box(container)
        local count = container:getWidgetCount()
        for index = 0, count - 1 do
            local widget = container:getWidget(index)
            if widget then
                if widget:getTypeName() == "EditBox" and widget:getFocused() then
                    return widget
                end

                if widget.getWidgetCount then
                    local result = find_focused_edit_box(widget)
                    if result then
                        return result
                    end
                end
            end
        end
    end

    local ok, err = pcall(function()
        local Widget = require("Widget")

        for _, widget in pairs(Widget.widgets) do
            if widget
                and widget.widget
                and widget:getTypeName() == "EditBox"
                and widget:getFocused() then
                if not keyboard.target or keyboard.target.pointer ~= widget.widget then
                    write(INFO, "generic focused field observed: " .. describe_widget(widget))
                end
                keyboard.capture_target(widget.widget, widget, "generic focus scan")
                return
            end
        end
    end)

    if not ok then
        write(ERROR, "focused-field tracking failed: " .. tostring(err))
    end
end

local function show_keyboard(context)
    local ok, err = pcall(on_simulation_start)
    if not ok then
        write(ERROR, "virtual keyboard setup failed (" .. context .. "): " .. tostring(err))
    end
end

local callbacks = {
    onSimulationStart = function()
        show_keyboard("simulation start")
    end,
    -- This callback is invoked when DCS returns to its main GUI, including the
    -- Mission Editor. It is not listed in the control API, but is documented as
    -- a simulator callback in the installed GameGUI.lua source.
    onShowMainInterface = function()
        show_keyboard("main interface")
    end,
    onSimulationFrame = track_focused_edit_box,
}

DCS.setUserCallbacks(callbacks)
write(INFO, "GameGUI hook loaded")
-- Create the window once the hook is loaded so it is available before the first
-- mission (for example, while working in the Mission Editor). If GUI startup is
-- still in progress, the supported lifecycle callbacks above retry the setup.
show_keyboard("hook load")
