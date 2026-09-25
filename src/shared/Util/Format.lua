--[[
	Formatting helpers shared by server and client.
]]

local Format = {}

-- 84.37 -> "01:24.37" ; precise=false -> "01:24"
function Format.Time(seconds: number?, precise: boolean?): string
	if seconds == nil or seconds ~= seconds or seconds == math.huge then
		return "--:--"
	end
	seconds = math.max(0, seconds)
	local minutes = math.floor(seconds / 60)
	local rest = seconds - minutes * 60
	if precise then
		local whole = math.floor(rest)
		local hundredths = math.floor((rest - whole) * 100)
		return string.format("%02d:%02d.%02d", minutes, whole, hundredths)
	end
	return string.format("%02d:%02d", minutes, math.floor(rest))
end

function Format.LevelNumber(id: number): string
	return string.format("%02d", id)
end

function Format.Commas(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s
	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end
	return formatted
end

return Format
