-- DCS DTC Helper -- virtual keyboard hook entrypoint.
local write_dir = lfs and lfs.writedir and lfs.writedir()
if write_dir then package.path = package.path .. ";" .. write_dir .. "Scripts\\DCSDTCHelper\\?.lua" end
require("VirtualKeyboard").start()
