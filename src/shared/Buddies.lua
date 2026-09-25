-- Playable buddies (classes) and colour skins. Buddies only get passives that help the TEAM,
-- never raw power. Buddies are unlocked with stars only; Robux can buy colour skins and star packs.
local Buddies = {}

Buddies.classOrder = { "bunny", "bear", "frog", "gecko" }

Buddies.classes = {
	bunny = {
		id = "bunny",
		name = "Кролик",
		emoji = "🐰",
		cost = 0,
		description = "Обычный пушистик. Умеет всё, что умеет команда",
	},
	bear = {
		id = "bear",
		name = "Мишка",
		emoji = "🐻",
		cost = 30,
		description = "Тяжёлый: на кнопках, лифтах и весах считается за двоих",
	},
	frog = {
		id = "frog",
		name = "Лягушка",
		emoji = "🐸",
		cost = 50,
		description = "Прыгучая: союзники рядом с ней получают двойной прыжок",
	},
	gecko = {
		id = "gecko",
		name = "Геккон",
		emoji = "🦎",
		cost = 80,
		description = "Липкий: 2 секунды держится на стене и отпрыгивает от неё",
	},
}

Buddies.skinOrder = { "classic", "mint", "caramel", "candy", "night", "gold" }

-- color = nil keeps the player's team colour
Buddies.skins = {
	classic = { id = "classic", name = "Командный", cost = 0 },
	mint = { id = "mint", name = "Мятный", cost = 20, color = Color3.fromRGB(160, 230, 200) },
	caramel = { id = "caramel", name = "Карамель", cost = 20, color = Color3.fromRGB(215, 160, 100) },
	candy = { id = "candy", name = "Конфетка", cost = 40, color = Color3.fromRGB(255, 170, 215) },
	night = { id = "night", name = "Ночной", cost = 40, color = Color3.fromRGB(70, 75, 120) },
	gold = { id = "gold", name = "Золотой", cost = 150, color = Color3.fromRGB(255, 205, 70) },
}

function Buddies.getClass(id)
	return Buddies.classes[id] or Buddies.classes.bunny
end

function Buddies.getSkin(id)
	return Buddies.skins[id] or Buddies.skins.classic
end

function Buddies.catalog(kind)
	if kind == "class" then
		return Buddies.classes, Buddies.classOrder
	elseif kind == "skin" then
		return Buddies.skins, Buddies.skinOrder
	end
	return nil, nil
end

return Buddies
