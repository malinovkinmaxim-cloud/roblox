--[[
	IconImages - pictures for passives, permanent upgrades, shop items and cosmetics.

	Paste an image asset id next to a key ("rbxassetid://1234567890") to show a real icon.
	An empty string keeps the drawn placeholder: a rounded tile in the category colour with a
	simple symbol (UI/Icons.lua), so every icon has the same style until real art exists.
	All entries start empty on purpose: no ids are invented here.
]]

local IconImages = {}

-- passives (level-up cards, ABILITIES > PASSIVE, the HUD build list)
IconImages.Stat = {
	Power = "",
	RapidFire = "",
	Expansion = "",
	Swiftness = "",
	Wisdom = "",
	Magnet = "",
	Vitality = "",
	Regeneration = "",
	Greed = "",
	Duration = "",
	CritMaster = "",
	Armor = "",
	Luck = "",
	Vampire = "",
	Berserk = "",
	OrbitalMastery = "",
	BurnMastery = "",
	DoubleShot = "",
	Execution = "",
	XPStorm = "",
	Percent67 = "",
	TouchGrass = "",
	-- permanent upgrades (SHOP > UPGRADES)
	Might = "",
	MaxHP = "",
	MoveSpeed = "",
	Growth = "",
	Regen = "",
	Reroll = "",
	Revive = "",
	ExtraWeapon = "",
	WeaponSlot = "",
}

-- level-up filler cards when everything is maxed
IconImages.Filler = {
	Snack = "",
	Coins = "",
}

-- game passes and developer products (SHOP > BOOSTS / GAMEPASSES)
IconImages.Product = {
	VIPCosmetics = "",
	CosmeticPass = "",
	ExtraLoadout = "",
	ExtraHeroSlot = "",
	AfkCapacity = "",
	Revive = "",
	ExtraReroll = "",
	ExtraChest = "",
	CosmeticBoost = "",
	AfkBoost = "",
	Support1 = "",
	Support2 = "",
	Support3 = "",
}

-- cosmetics without a 3D preview (trails, effects, emotes...), by cosmetic id ("Trail.Fire")
IconImages.Cosmetic = {}

return IconImages
