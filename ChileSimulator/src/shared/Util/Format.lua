--[[
	Format - compact, readable numbers for a phone screen.

	Format.Number(1234)        -> "1.23K"
	Format.Number(5.2e15)      -> "5.2Qa"
	Format.Length(1)           -> "0.01 m"     (height is stored in centimetres)
	Format.Gain(1250)          -> "+12.5 m"
	Format.Time(125)           -> "2:05"
	Format.Mult(2.5)           -> "x2.5"

	Never returns "nan" / "inf": everything goes through Num.Sanitize.
]]

local Num = require(script.Parent.Num)

local Format = {}

-- 10^3 ... 10^99. Past the table we switch to scientific notation.
local SUFFIXES = {
	"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", -- 1e3 .. 1e30
	"Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", -- 1e33 .. 1e60
	"Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg", "Novg", -- 1e63 .. 1e90
	"Tg", "Utg", "Dtg", -- 1e93 .. 1e99
}
Format.SUFFIXES = SUFFIXES

-- "12.50" -> "12.5", "3.00" -> "3"
local function trim(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

-- 3 significant digits: 1.23 / 12.3 / 123
local function sig3(x: number): string
	if x >= 100 then
		return string.format("%d", math.floor(x + 1e-9))
	elseif x >= 10 then
		return trim(string.format("%.1f", math.floor(x * 10 + 1e-9) / 10))
	end
	return trim(string.format("%.2f", math.floor(x * 100 + 1e-9) / 100))
end

function Format.Commas(n: number): string
	n = math.floor(Num.Sanitize(n))
	local negative = n < 0
	local s = string.format("%.0f", math.abs(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	out = string.gsub(out, "^,", "")
	return (negative and "-" or "") .. out
end

-- Compact number. Values below 1000 keep up to `decimals` decimals (default 0 for >=10, 2 below).
function Format.Number(n: number, decimals: number?): string
	n = Num.Sanitize(n)
	if n < 0 then
		return "-" .. Format.Number(-n, decimals)
	end
	if n < 1000 then
		if decimals then
			return trim(string.format("%." .. decimals .. "f", n))
		end
		if n >= 10 or n == math.floor(n) then
			return string.format("%d", math.floor(n + 1e-9))
		end
		return trim(string.format("%.2f", n))
	end
	local exponent = math.floor(math.log10(n) + 1e-12)
	local group = math.floor(exponent / 3)
	local scaled = n / 10 ^ (group * 3)
	-- guard against log10 rounding at exact powers of ten
	if scaled < 1 then
		group -= 1
		scaled *= 1000
	elseif scaled >= 1000 then
		group += 1
		scaled /= 1000
	end
	if group > #SUFFIXES then
		-- scientific: 1.23e105
		local mantissa = n / 10 ^ exponent
		if mantissa < 1 then
			mantissa *= 10
			exponent -= 1
		elseif mantissa >= 10 then
			mantissa /= 10
			exponent += 1
		end
		return string.format("%se%d", trim(string.format("%.2f", math.floor(mantissa * 100) / 100)), exponent)
	end
	return sig3(scaled) .. SUFFIXES[group]
end

-- Height is stored in centimetres; display in metres.
function Format.Meters(cm: number): string
	local m = Num.NonNeg(cm) / 100
	if m < 10 then
		return string.format("%.2f", math.floor(m * 100 + 1e-9) / 100)
	elseif m < 1000 then
		return trim(string.format("%.1f", math.floor(m * 10 + 1e-9) / 10))
	end
	return Format.Number(m)
end

function Format.Length(cm: number): string
	return Format.Meters(cm) .. " m"
end

-- Gains read nicer in cm while they are small: "+1 cm", "+35 cm", "+2.5 m", "+1.2K m"
function Format.Gain(cm: number): string
	cm = Num.NonNeg(cm)
	if cm < 100 then
		if cm >= 10 then
			return "+" .. string.format("%d", math.floor(cm + 1e-9)) .. " cm"
		end
		return "+" .. trim(string.format("%.1f", math.floor(cm * 10 + 1e-9) / 10)) .. " cm"
	end
	return "+" .. Format.Length(cm)
end

function Format.Mult(x: number): string
	x = Num.NonNeg(x, 1)
	if x < 10 then
		return "x" .. trim(string.format("%.2f", math.floor(x * 100 + 0.5) / 100))
	end
	return "x" .. Format.Number(x)
end

function Format.Percent(fraction: number): string
	fraction = Num.Clamp(fraction, 0, 1)
	return string.format("%d%%", math.floor(fraction * 100))
end

function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(Num.NonNeg(seconds)))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- "5 min", "1 h", "30 s"
function Format.Duration(seconds: number): string
	seconds = math.floor(Num.NonNeg(seconds))
	if seconds >= 3600 and seconds % 3600 == 0 then
		return (seconds // 3600) .. " h"
	elseif seconds >= 60 and seconds % 60 == 0 then
		return (seconds // 60) .. " min"
	elseif seconds >= 60 then
		return Format.Time(seconds)
	end
	return seconds .. " s"
end

return Format
