-- DCS DTC Helper -- virtual keyboard feature module.
--
-- Loaded by Scripts\Hooks\DCSDTCHelperVirtualKeyboard.lua.

local M = {}

local TAG = "DCSDTCHelper"
local INFO = (log and log.INFO) or 0
local WARNING = (log and log.WARNING) or 1
local ERROR = (log and log.ERROR) or 2
local keyboard
local last_focus_scan = 0
local last_shortcut_options_poll = 0
local shortcut_registered = false
local suspended = false
local shortcut_left_ctrl_down = false
local shortcut_right_ctrl_down = false
local shortcut_left_shift_down = false
local shortcut_right_shift_down = false
local shortcut_left_alt_down = false
local shortcut_right_alt_down = false
local shortcut_key_down = false
local invalid_widgets = setmetatable({}, { __mode = "k" })

local DEFAULT_SHORTCUT_KEY = "V"
local shortcut = {
    label = "LCtrl+LShift+V",
    key = DEFAULT_SHORTCUT_KEY,
    left_ctrl = true,
    right_ctrl = false,
    left_shift = true,
    right_shift = false,
    left_alt = false,
    right_alt = false,
    enabled = true,
}

-- GameGUI hooks do not include the stock UI Lua search paths by default.
package.path = package.path
    .. ";.\\Scripts\\UI\\?.lua"
    .. ";.\\MissionEditor\\modules\\?.lua"

local function write(level, message)
    if log and log.write then
        log.write(TAG, level, message)
    else
        print(TAG .. ": " .. message)
    end
end

local function toggle_keyboard()
    if suspended then return end
    if not keyboard or not keyboard.window then
        write(WARNING, "virtual keyboard toggle ignored because the window is not ready")
        return
    end

    local visible = keyboard.window:getVisible()
    keyboard.window:setVisible(not visible)
end

local function get_special_option(options_editor, name, default)
    local ok, value = pcall(options_editor.getOption, "plugins.DCSDTCHelper." .. name)
    if ok and value ~= nil then
        return value
    end
    return default
end

local function read_keyboard_shortcut()
    local ok, options_editor = pcall(require, "optionsEditor")
    if not ok then
        return nil
    end

    local key = get_special_option(options_editor, "shortcutKey", DEFAULT_SHORTCUT_KEY)
    if type(key) ~= "string" then
        key = DEFAULT_SHORTCUT_KEY
    end
    key = string.upper(string.gsub(key, "%s+", ""))
    if not string.match(key, "^[A-Z]$") then
        key = DEFAULT_SHORTCUT_KEY
    end

    local result = {
        key = key,
        left_ctrl = get_special_option(options_editor, "shortcutLeftCtrl", true) == true,
        right_ctrl = get_special_option(options_editor, "shortcutRightCtrl", false) == true,
        left_shift = get_special_option(options_editor, "shortcutLeftShift", true) == true,
        right_shift = get_special_option(options_editor, "shortcutRightShift", false) == true,
        left_alt = get_special_option(options_editor, "shortcutLeftAlt", false) == true,
        right_alt = get_special_option(options_editor, "shortcutRightAlt", false) == true,
    }

    local parts = {}
    if result.left_ctrl then table.insert(parts, "LCtrl") end
    if result.right_ctrl then table.insert(parts, "RCtrl") end
    if result.left_shift then table.insert(parts, "LShift") end
    if result.right_shift then table.insert(parts, "RShift") end
    if result.left_alt then table.insert(parts, "LAlt") end
    if result.right_alt then table.insert(parts, "RAlt") end
    result.enabled = #parts > 0
    if result.enabled then
        table.insert(parts, result.key)
        result.label = table.concat(parts, "+")
    else
        result.label = "disabled (select at least one modifier)"
    end

    return result
end

local function shortcuts_equal(a, b)
    return a.key == b.key
        and a.left_ctrl == b.left_ctrl
        and a.right_ctrl == b.right_ctrl
        and a.left_shift == b.left_shift
        and a.right_shift == b.right_shift
        and a.left_alt == b.left_alt
        and a.right_alt == b.right_alt
end

local function refresh_keyboard_shortcut()
    local configured = read_keyboard_shortcut()
    if configured and not shortcuts_equal(shortcut, configured) then
        shortcut = configured
        shortcut_key_down = false
    end
end

local function is_key_down(key_state)
    -- The native global callback currently supplies "down"/"up". Accept the
    -- boolean form too, so the hook remains compatible with older DCS builds.
    return key_state == "down" or key_state == true or key_state == 1
end

local function global_keyboard_callback(key_name, key_state)
    local down = is_key_down(key_state)

    if key_name == "left ctrl" then
        shortcut_left_ctrl_down = down
    elseif key_name == "right ctrl" then
        shortcut_right_ctrl_down = down
    elseif key_name == "left shift" then
        shortcut_left_shift_down = down
    elseif key_name == "right shift" then
        shortcut_right_shift_down = down
    elseif key_name == "left alt" then
        shortcut_left_alt_down = down
    elseif key_name == "right alt" then
        shortcut_right_alt_down = down
    elseif key_name == string.lower(shortcut.key) then
        local modifiers_match = shortcut_left_ctrl_down == shortcut.left_ctrl
            and shortcut_right_ctrl_down == shortcut.right_ctrl
            and shortcut_left_shift_down == shortcut.left_shift
            and shortcut_right_shift_down == shortcut.right_shift
            and shortcut_left_alt_down == shortcut.left_alt
            and shortcut_right_alt_down == shortcut.right_alt
        if down and shortcut.enabled and modifiers_match and not shortcut_key_down then
            shortcut_key_down = true
            toggle_keyboard()
        elseif not down then
            shortcut_key_down = false
        end
    end
end

local function install_keyboard_shortcut(Gui)
    if shortcut_registered then
        return
    end

    Gui.AddKeyboardCallback(global_keyboard_callback)
    shortcut_registered = true
end

local function on_simulation_start()
    if keyboard and keyboard.window then
        return
    end

    local ok, err = pcall(function()
        local Gui = require("dxgui")
        local Window = require("Window")
        local Button = require("Button")
        local EditBox = require("EditBox")
        local Widget = require("Widget")

        refresh_keyboard_shortcut()
        install_keyboard_shortcut(Gui)

        local screen_width, screen_height = Gui.GetWindowSize()
        -- Keep this panel compact enough to leave the active DCS UI usable.
        -- This is approximately half the first prototype's footprint.
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
        -- Native DCS dialogs cover the default Z layer. Match DCS's overlay
        -- convention so this keyboard remains above them without source edits.
        keyboard.window:setZOrder(10002)

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
            keyboard.target = {
                pointer = pointer,
                wrapper = wrapper,
                type_name = type_name,
                source = source,
                selection = read_selection(pointer),
            }
        end

        keyboard.capture_target = capture_target

        local function target_is_live(target)
            if target.wrapper and (target.wrapper.widget ~= target.pointer
                or Widget.widgets[target.pointer] ~= target.wrapper) then
                return false
            end
            local ok, type_name = pcall(Gui.WidgetGetTypeName, target.pointer)
            return ok and type_name == "EditBox"
        end

        Gui.AddMouseCallback("down", function(x, y)
            if suspended then return end
            local pointer = Gui.FindWidgetAtScreenPoint(x, y)
            if pointer and Gui.WidgetGetTypeName(pointer) == "EditBox" then
                capture_target(pointer, Widget.widgets[pointer], "global mouse")
            end
        end)
        -- Mouse-down identifies the widget; mouse-up sees the selection DCS
        -- has assigned after placing its native caret inside that EditBox.
        Gui.AddMouseCallback("up", function(x, y)
            if suspended then return end
            local pointer = Gui.FindWidgetAtScreenPoint(x, y)
            if pointer and Gui.WidgetGetTypeName(pointer) == "EditBox" then
                capture_target(pointer, Widget.widgets[pointer], "global mouse up")
            end
        end)

        local function apply_to_target(action, value)
            if suspended then return false end
            local target = keyboard.target
            if target and target.type_name == "EditBox" then
                if not target_is_live(target) then
                    keyboard.target = nil
                    write(WARNING, "virtual keyboard discarded an expired target (" .. target.source .. ")")
                    return false
                end
                local selection = target.selection or read_selection(target.pointer)
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
                -- Change handlers may rebuild the dialog and destroy this field.
                if not target_is_live(target) then
                    keyboard.target = nil
                    write(WARNING, "virtual keyboard target expired in its change handler")
                    return true
                end
                -- Keep the saved target/caret without forcing native focus during
                -- mouse-up: cross-window refocus crashed dxgui's modal focus flow.
                Gui.EditBoxSetSelection(target.pointer, 0, caret, 0, caret)
                target.selection = read_selection(target.pointer)

                keyboard.text = next_text
                return true
            end

            return false
        end

        local letter_block_x = 12
        local letter_block_width = 274
        local keyboard_top = 12
        local key_gap = 2
        local key_height = 23
        local letter_key_width = math.floor((letter_block_width - (key_gap * 9)) / 10)

        local function add_alpha_key(label, value, row, column, columns)
            local gap = 2
            local usable_width = letter_block_width - (gap * (columns - 1))
            local key_width = math.floor(usable_width / columns)
            local button = Button.new(label)
            button:setBounds(letter_block_x + (column - 1) * (key_width + gap), keyboard_top + (row - 1) * (key_height + gap), key_width, key_height)
            -- dxgui transfers focus during mouse-down. Handle the key on mouse-up
            -- so the target EditBox can be focused again afterwards.
            button:addMouseUpCallback(function()
                if not apply_to_target("append", value) then
                    keyboard.text = keyboard.text .. value
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
        backspace:setBounds(letter_block_x, 90, 62, key_height)
        backspace:addMouseUpCallback(function()
            if not apply_to_target("backspace") then
                keyboard.text = string.sub(keyboard.text, 1, -2)
            end
        end)
        keyboard.window:insertWidget(backspace)
        table.insert(keyboard.buttons, backspace)

        local space = Button.new("SPACE")
        space:setBounds(letter_block_x + 64, 90, 134, key_height)
        space:addMouseUpCallback(function()
            if not apply_to_target("append", " ") then
                keyboard.text = keyboard.text .. " "
            end
        end)
        keyboard.window:insertWidget(space)
        table.insert(keyboard.buttons, space)

        local clear = Button.new("CLEAR")
        clear:setBounds(letter_block_x + 200, 90, letter_block_width - 200, key_height)
        clear:addMouseUpCallback(function()
            if not apply_to_target("clear") then
                keyboard.text = ""
            end
        end)
        keyboard.window:insertWidget(clear)
        table.insert(keyboard.buttons, clear)

        local function add_coordinate_key(label, value, row, column)
            local gap = 3
            local key_width = letter_key_width
            local button = Button.new(label)
            button:setBounds(303 + (column - 1) * (key_width + gap), keyboard_top + (row - 1) * (key_height + gap), key_width, key_height)
            button:addMouseUpCallback(function()
                if not apply_to_target("append", value) then
                    keyboard.text = keyboard.text .. value
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

        local cardinal_x = 303 + 3 * (letter_key_width + 3)
        local cardinal_width = 42
        local cardinal_points = { "N", "S", "E", "W" }
        for row_index, point in ipairs(cardinal_points) do
            local button = Button.new(point)
            button:setBounds(cardinal_x, keyboard_top + (row_index - 1) * (key_height + 3), cardinal_width, key_height)
            button:addMouseUpCallback(function()
                if not apply_to_target("append", point) then
                    keyboard.text = keyboard.text .. point
                end
            end)
            keyboard.window:insertWidget(button)
            table.insert(keyboard.buttons, button)
        end

        local coordinate_backspace = Button.new("DEL")
        coordinate_backspace:setBounds(cardinal_x, keyboard_top + 4 * (key_height + 3), cardinal_width, key_height)
        coordinate_backspace:addMouseUpCallback(function()
            if not apply_to_target("backspace") then
                keyboard.text = string.sub(keyboard.text, 1, -2)
            end
        end)
        keyboard.window:insertWidget(coordinate_backspace)
        table.insert(keyboard.buttons, coordinate_backspace)

        keyboard.window:setVisible(false)
    end)

    if not ok then
        write(ERROR, "virtual keyboard window failed: " .. tostring(err))
    end
end

local function track_focused_edit_box()
    if suspended or not keyboard or not keyboard.window then
        return
    end

    local now = DCS.getRealTime()
    if now - last_focus_scan < 0.1 then
        return
    end
    last_focus_scan = now

    if now - last_shortcut_options_poll >= 0.25 then
        last_shortcut_options_poll = now
        refresh_keyboard_shortcut()
    end

    local ok, err = pcall(function()
        local Widget = require("Widget")

        for _, widget in pairs(Widget.widgets) do
            if widget
                and widget.widget
                and not invalid_widgets[widget] then
                -- Native container teardown can leave stale Lua registry entries.
                -- One invalid entry must not prevent finding the selected field.
                local valid, focused = pcall(function()
                    return widget:getTypeName() == "EditBox" and widget:getFocused()
                end)
                if not valid then
                    invalid_widgets[widget] = true
                    write(WARNING, "virtual keyboard skipped invalid focus-scan widget: " .. tostring(focused))
                elseif focused then
                    keyboard.capture_target(widget.widget, widget, "generic focus scan")
                    return
                end
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

function M.start()
    local function suspend_keyboard()
        if suspended then return end
        suspended = true
        shortcut_left_ctrl_down, shortcut_right_ctrl_down = false, false
        shortcut_left_shift_down, shortcut_right_shift_down = false, false
        shortcut_left_alt_down, shortcut_right_alt_down = false, false
        shortcut_key_down = false
        if keyboard then
            keyboard.target = nil
            keyboard.text = ""
            if keyboard.window then keyboard.window:setVisible(false) end
        end
        write(INFO, "virtual keyboard: mission references cleared; window hidden")
    end
    DCS.setUserCallbacks({
        onMissionLoadBegin = suspend_keyboard,
        onSimulationStop = suspend_keyboard,
        onSimulationStart = function()
            show_keyboard("simulation start")
            last_focus_scan, last_shortcut_options_poll = 0, 0
            suspended = false
        end,
        -- This callback is invoked when DCS returns to its main GUI, including
        -- the Mission Editor. If GUI startup is still in progress, retry then.
        onShowMainInterface = function()
            show_keyboard("main interface")
            suspended = false
        end,
        onSimulationFrame = track_focused_edit_box,
    })
    -- Make the keyboard available before the first mission as well.
    show_keyboard("hook load")
end

return M
