--[[
	Progression
	XP -> player level math. Shared so the client can draw the XP bar
	exactly the way the server computes levels.
]]

local Config = require(script.Parent.Config)

local Progression = {}

function Progression.XPForLevel(level: number): number
	-- XP needed to go from `level` to `level + 1`
	return Config.XP_PER_LEVEL + (level - 1) * Config.XP_LEVEL_GROWTH
end

-- Returns level, xp into the current level, xp needed for the next level
function Progression.FromXP(totalXP: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, math.floor(totalXP))
	while true do
		local need = Progression.XPForLevel(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
		if level > 10000 then
			return level, 0, need
		end
	end
end

function Progression.LevelKey(levelId: number): string
	return "L" .. tostring(levelId)
end

return Progression
