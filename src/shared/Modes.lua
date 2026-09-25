local Modes = {}

Modes.order = { "easy", "medium", "hard", "hardcore", "endless" }

Modes.list = {
	easy = {
		id = "easy",
		name = "Easy",
		description = "8 simple levels to learn the basics",
		pack = "easy",
		color = Color3.fromRGB(80, 195, 110),
	},
	medium = {
		id = "medium",
		name = "Medium",
		description = "16 levels: sand, cannons, moving platforms",
		pack = "medium",
		requires = "easy",
		color = Color3.fromRGB(95, 155, 240),
	},
	hard = {
		id = "hard",
		name = "Hard",
		description = "20 of the toughest levels",
		pack = "hard",
		requires = "medium",
		color = Color3.fromRGB(255, 150, 50),
	},
	hardcore = {
		id = "hardcore",
		name = "Hardcore",
		description = "The 20 hard levels with one life for the team",
		pack = "hard",
		oneLife = true,
		requires = "hard",
		color = Color3.fromRGB(235, 70, 80),
	},
	endless = {
		id = "endless",
		name = "Endless",
		description = "Random levels that keep getting harder. Always open",
		endless = true,
		color = Color3.fromRGB(160, 110, 240),
	},
}

function Modes.get(id)
	if type(id) == "string" then
		return Modes.list[id]
	end
	return nil
end

-- Progress is tracked per party size: `completed` holds keys like "duo:easy".
function Modes.completedKey(partyId, modeId)
	return `{partyId}:{modeId}`
end

function Modes.isUnlocked(id, completed, partyId)
	local mode = Modes.get(id)
	return mode ~= nil and (mode.requires == nil or completed[Modes.completedKey(partyId, mode.requires)] == true)
end

return Modes
