-- neofetch.lua — простой neofetch для OpenOS
local component = require("component")
local computer = require("computer")
local unicode = require("unicode")
local filesystem = require("filesystem")

local gpu = component.gpu
local oldFg = gpu.getForeground()

local function formatBytes(bytes)
  local units = {"B", "KB", "MB", "GB"}
  local unit = 1

  while bytes >= 1024 and unit < #units do
    bytes = bytes / 1024
    unit = unit + 1
  end

  return string.format("%.1f %s", bytes, units[unit])
end

local function formatTime(seconds)
  seconds = math.floor(seconds)

  local days = math.floor(seconds / 86400)
  local hours = math.floor(seconds % 86400 / 3600)
  local minutes = math.floor(seconds % 3600 / 60)

  local result = {}

  if days > 0 then
    table.insert(result, days .. "d")
  end

  if hours > 0 then
    table.insert(result, hours .. "h")
  end

  table.insert(result, minutes .. "m")
  return table.concat(result, " ")
end

local function getCpuName()
  local info = computer.getDeviceInfo()

  for _, device in pairs(info) do
    if device.class == "processor" then
      return device.description or device.product or "Unknown CPU"
    end
  end

  return "OpenComputers CPU"
end

local function getDiskUsage()
  local proxy = filesystem.get("/")

  if not proxy then
    return "Unknown"
  end

  local total = proxy.spaceTotal()
  local used = total - proxy.spaceFree()

  return formatBytes(used) .. " / " .. formatBytes(total)
end

local width, height = gpu.getResolution()
local totalMemory = computer.totalMemory()
local usedMemory = totalMemory - computer.freeMemory()

local user = os.getenv("USER") or "player"
local hostname = os.getenv("HOSTNAME") or "opencomputer"

local art = {
  "       _______       ",
  "    .-`       `-.    ",
  "  .'   OPEN      `.  ",
  " /    COMPUTERS     \\ ",
  "|       ┌────┐       |",
  "|       │ ▣▣ │       |",
  "|       │ ▣▣ │       |",
  " \\      └────┘      / ",
  "  `.             .'  ",
  "    `-._______.-`    "
}

local info = {
  user .. "@" .. hostname,
  string.rep("-", unicode.len(user .. "@" .. hostname)),
  "OS: OpenOS",
  "Kernel: " .. (_VERSION or "Lua"),
  "CPU: " .. getCpuName(),
  "Memory: " .. formatBytes(usedMemory) .. " / " .. formatBytes(totalMemory),
  "Disk: " .. getDiskUsage(),
  "Uptime: " .. formatTime(computer.uptime()),
  "Resolution: " .. width .. "x" .. height,
  "Energy: " .. math.floor(computer.energy()) ..
    " / " .. math.floor(computer.maxEnergy())
}

local cyan = 0x00BFFF
local white = 0xFFFFFF
local gap = 3
local artWidth = 0

for _, line in ipairs(art) do
  artWidth = math.max(artWidth, unicode.len(line))
end

local lines = math.max(#art, #info)

for i = 1, lines do
  if art[i] then
    gpu.setForeground(cyan)
    io.write(art[i])
  else
    io.write(string.rep(" ", artWidth))
  end

  io.write(string.rep(" ", gap))

  if info[i] then
    gpu.setForeground(i <= 2 and cyan or white)
    io.write(info[i])
  end

  io.write("\n")
end

gpu.setForeground(oldFg)
