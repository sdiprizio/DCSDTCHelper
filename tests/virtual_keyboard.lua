-- Run from the repository root with DCS's bin/luae.exe.
package.path = "SavedGames/Scripts/DCSDTCHelper/?.lua;" .. package.path
local registry, buttons, mouse, messages = {}, {}, {}, {}
local callbacks, hit
local now = 1
log = { write = function(_, _, message) table.insert(messages, message) end }
DCS = {
    setUserCallbacks = function(value) callbacks = value end,
    getRealTime = function() return now end,
}
local function control()
    local w = {}
    for _, name in ipairs({ "setDraggable", "setHasCursor", "setZOrder", "setBounds", "insertWidget" }) do
        w[name] = function() end
    end
    function w:setVisible(value) self.visible = value end
    function w:getVisible() return self.visible end
    function w:addMouseUpCallback(fn) self.up = fn end
    return w
end
package.preload.Window = function() return { new = control } end
package.preload.Button = function() return { new = function(label)
    local w = control()
    buttons[label] = w
    return w
end } end
package.preload.EditBox = function() return {} end
package.preload.Widget = function() return { widgets = registry } end
local selection_writes = 0
local gui = {
    GetWindowSize = function() return 1920, 1080 end,
    AddKeyboardCallback = function() end,
    AddMouseCallback = function(event, fn) mouse[event] = fn end,
    FindWidgetAtScreenPoint = function() return hit end,
    WidgetGetTypeName = function(pointer)
        assert(registry[pointer], "expired native widget")
        return "EditBox"
    end,
    EditBoxGetSelection = function(pointer)
        local w = assert(registry[pointer])
        return 0, w.first, 0, w.last
    end,
    EditBoxSetSelection = function(pointer, _, first, _, last)
        local w = assert(registry[pointer], "selection on destroyed widget")
        w.first, w.last = first, last
        selection_writes = selection_writes + 1
    end,
    WidgetSetFocused = function() error("must not force native focus") end,
}
package.preload.dxgui = function() return gui end
require("VirtualKeyboard").start()
assert(buttons.Q, "keyboard setup failed")
local function field(text)
    local w = { text = text, first = #text, last = #text, focused = true }
    w.widget = {}
    registry[w.widget] = w
    function w:getTypeName() return gui.WidgetGetTypeName(self.widget) end
    function w:getFocused() return self.focused end
    function w:getText() return self.text end
    function w:setText(value) self.text = value end
    function w:setFocused() error("must not force wrapper focus") end
    function w:onChange() self.saved = self.text end
    return w
end
local w = field("Target")
hit = w.widget
mouse.up(0, 0)
w.focused = false -- A virtual key takes focus.
buttons.Q.up()
buttons.W.up()
assert(w.text == "TargetQW" and w.saved == w.text, "repeated typing/change handler")
buttons.DEL.up()
assert(w.text == "TargetQ")
w.first, w.last = 0, #w.text
mouse.up(0, 0)
buttons.A.up()
assert(w.text == "A", "selection replacement")
buttons.CLEAR.up()
assert(w.text == "", "clear")
registry[w.widget] = nil
buttons.Q.up() -- Expired target must be discarded before reading/writing text.
assert(w.text == "")
w = field("New")
hit = w.widget
mouse.up(0, 0)
function w:onChange() registry[self.widget] = nil; self.widget = nil end
local before = selection_writes
buttons.Q.up()
assert(selection_writes == before, "must not access widget destroyed by onChange")
local invalid_reads = 0
registry.bad = { widget = {}, getTypeName = function()
    invalid_reads = invalid_reads + 1
    error("Invalid type conversion! Type expected is Widget")
end }
now = 2
callbacks.onSimulationFrame()
now = 3
callbacks.onSimulationFrame()
assert(invalid_reads == 1, "invalid registry entry must not be polled repeatedly")
w = field("Live")
now = 4
callbacks.onSimulationFrame()
buttons.Q.up()
assert(w.text == "LiveQ", "focus scan must recover after stale entry")
callbacks.onSimulationStop()
registry[w.widget] = nil
local reads = 0
gui.FindWidgetAtScreenPoint = function() reads = reads + 1; error("map teardown") end
mouse.up(0, 0)
now = 5
callbacks.onSimulationFrame()
buttons.Q.up()
assert(reads == 0 and w.text == "LiveQ", "teardown must not access saved widgets")
callbacks.onSimulationStop() -- Cleanup is idempotent.
callbacks.onShowMainInterface()
buttons.Q.up()
assert(w.text == "LiveQ", "main interface must not restore the old target")
callbacks.onMissionLoadBegin()
callbacks.onSimulationStart()
w = field("Next")
now = 6
callbacks.onSimulationFrame()
buttons.Q.up()
assert(w.text == "NextQ", "next mission must accept a fresh target")
print("virtual keyboard regression tests passed")
