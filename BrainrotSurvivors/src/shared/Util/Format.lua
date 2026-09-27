--[[
	Format - short readable numbers and times for a phone screen.
]]

local Format = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa" }

local function trim(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

function Format.Number(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	if n < 0 then
		return "-" .. Format.Number(-n)
	end
	if n < 1000 then
		return tostring(math.floor(n))
	end
	local i = 0
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local digits = if n >= 100 then 0 elseif n >= 10 then 1 else 2
	local factor = 10 ^ digits
	return trim(string.format("%." .. digits .. "f", math.floor(n * factor) / factor)) .. SUFFIXES[i]
end

function Format.Commas(n: number): string
	n = math.floor(if n == n then n else 0)
	local s = tostring(math.abs(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	out = string.gsub(out, "^,", "")
	return (if n < 0 then "-" else "") .. out
end

-- 125 -> "2:05"
function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(if seconds == seconds then seconds else 0))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Format.Percent(x: number): string
	return trim(string.format("%.1f", x * 100)) .. "%"
end

return Format
