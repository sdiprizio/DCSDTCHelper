-- DCS DTC Helper -- F10 coordinate and JDAM DTC hook entrypoint.
local write_dir = lfs and lfs.writedir and lfs.writedir()
if write_dir then package.path = package.path .. ";" .. write_dir .. "Scripts\\DCSDTCHelper\\?.lua" end
require("DTC").start()
