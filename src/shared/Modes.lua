local Modes = {}

Modes.order = { "easy", "medium", "hard", "hardcore", "endless" }

Modes.list = {
	easy = {
		id = "easy",
		name = "Лёгкий",
		description = "15 простых уровней с основами",
		pack = "easy",
		color = Color3.fromRGB(80, 195, 110),
	},
	medium = {
		id = "medium",
		name = "Средний",
		description = "25 уровней: песок, пушки, качели",
		pack = "medium",
		requires = "easy",
		color = Color3.fromRGB(95, 155, 240),
	},
	hard = {
		id = "hard",
		name = "Сложный",
		description = "35 самых трудных уровней",
		pack = "hard",
		requires = "medium",
		color = Color3.fromRGB(255, 150, 50),
	},
	hardcore = {
		id = "hardcore",
		name = "Хардкор",
		description = "35 сложных уровней, одна жизнь на всех",
		pack = "hard",
		oneLife = true,
		requires = "hard",
		color = Color3.fromRGB(235, 70, 80),
	},
	endless = {
		id = "endless",
		name = "Бесконечный",
		description = "Случайные уровни, всё сложнее. Всегда открыт",
		endless = true,
		color = Color3.fromRGB(160, 110, 240),
	},
}

-- Each mode except Easy and Endless opens once the previous one is completed.
-- `completed` is a set of mode ids the player has finished.
function Modes.isUnlocked(id, completed)
	local mode = Modes.get(id)
	return mode ~= nil and (mode.requires == nil or completed[mode.requires] == true)
end

function Modes.get(id)
	if type(id) == "string" then
		return Modes.list[id]
	end
	return nil
end

return Modes
