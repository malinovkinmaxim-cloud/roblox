-- Playable buddies (classes) and colour skins. Buddies only get passives that help the TEAM,
-- never raw power. Buddies are bought with Paws only; Robux can buy colour skins and Paw packs.
local Buddies = {}

Buddies.classOrder = { "bunny", "bear", "frog", "gecko" }

Buddies.classes = {
	bunny = {
		id = "bunny",
		name = "Bunny",
		emoji = "🐰",
		cost = 0,
		description = "A classic fluffball. No tricks, just teamwork",
	},
	bear = {
		id = "bear",
		name = "Bear",
		emoji = "🐻",
		cost = 300,
		description = "Heavy: counts as two on plates, lifts and seesaws",
	},
	frog = {
		id = "frog",
		name = "Frog",
		emoji = "🐸",
		cost = 500,
		description = "Bouncy: teammates near her get a double jump",
	},
	gecko = {
		id = "gecko",
		name = "Gecko",
		emoji = "🦎",
		cost = 800,
		description = "Sticky: clings to walls for 2 seconds and wall-jumps",
	},
}

Buddies.skinOrder = { "classic", "mint", "caramel", "candy", "night", "gold" }

-- color = nil keeps the player's team colour
Buddies.skins = {
	classic = { id = "classic", name = "Team", cost = 0 },
	mint = { id = "mint", name = "Mint", cost = 200, color = Color3.fromRGB(160, 230, 200) },
	caramel = { id = "caramel", name = "Caramel", cost = 200, color = Color3.fromRGB(215, 160, 100) },
	candy = { id = "candy", name = "Candy", cost = 400, color = Color3.fromRGB(255, 170, 215) },
	night = { id = "night", name = "Night", cost = 400, color = Color3.fromRGB(70, 75, 120) },
	gold = { id = "gold", name = "Gold", cost = 1500, color = Color3.fromRGB(255, 205, 70) },
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
