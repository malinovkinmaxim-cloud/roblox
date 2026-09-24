local Modes = {}

Modes.order = { "easy", "medium", "hard", "hardcore", "endless" }

Modes.list = {
	easy = {
		id = "easy",
		name = "Лёгкий",
		description = "10 уровней, чтобы разобраться",
		pack = "easy",
		color = Color3.fromRGB(80, 195, 110),
	},
	medium = {
		id = "medium",
		name = "Средний",
		description = "10 уровней: песок, пушки, качели",
		pack = "medium",
		color = Color3.fromRGB(95, 155, 240),
	},
	hard = {
		id = "hard",
		name = "Сложный",
		description = "10 уровней на время и скорость",
		pack = "hard",
		color = Color3.fromRGB(255, 150, 50),
	},
	hardcore = {
		id = "hardcore",
		name = "Хардкор",
		description = "Сложные уровни, одна жизнь на всех",
		pack = "hard",
		oneLife = true,
		color = Color3.fromRGB(235, 70, 80),
	},
	endless = {
		id = "endless",
		name = "Бесконечный",
		description = "Случайные уровни, всё сложнее",
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

return Modes
