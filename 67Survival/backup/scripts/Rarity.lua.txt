--[[
	Rarity - the 7 tiers used by heroes, abilities, evolutions and cosmetics.

	  Common  Uncommon  Rare  Epic  Legendary  Mythic  Secret

	Weight: how often an ability of that tier shows up in a level-up offer (relative).
	Legendary is deliberately rare; Mythic cards are evolutions (never random); Secret
	abilities only enter the pool after their secret was discovered.
	Luck multiplies the weight of the higher tiers (LuckScale per tier).
]]

local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Rarity.Index = {} :: { [string]: number }
for i, name in Rarity.Order do
	Rarity.Index[name] = i
end

Rarity.Weight = {
	Common = 1,
	Uncommon = 0.7,
	Rare = 0.4,
	Epic = 0.2,
	Legendary = 0.065,
	Mythic = 0,
	Secret = 0.06,
}

Rarity.LuckScale = {
	Common = 0,
	Uncommon = 0.35,
	Rare = 0.8,
	Epic = 1.2,
	Legendary = 1.6,
	Mythic = 0,
	Secret = 1,
}

-- offer weight of a tier for a player with `luck` (1 = normal)
function Rarity.WeightFor(rarity: string, luck: number): number
	local base = Rarity.Weight[rarity] or 1
	local scale = Rarity.LuckScale[rarity] or 0
	return base * math.max(0.2, 1 + (luck - 1) * scale)
end

-- menu colours (the client theme uses these too)
local rgb = Color3.fromRGB
Rarity.Colors = {
	Common = rgb(150, 158, 190),
	Uncommon = rgb(90, 210, 130),
	Rare = rgb(80, 160, 255),
	Epic = rgb(175, 105, 255),
	Legendary = rgb(255, 190, 60),
	Mythic = rgb(0, 225, 210),
	Secret = rgb(235, 235, 245),
}

return Rarity
