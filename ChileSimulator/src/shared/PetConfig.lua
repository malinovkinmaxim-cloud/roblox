--[[
	PetConfig - rarities, eggs and pets.

	Pets are a side system: they give a Growth AND Coins multiplier. Equipped pets stack
	ADDITIVELY: total = 1 + sum(petMultiplier - 1). Three x5 pets = x13, not x125, so pets
	help a lot but never replace tapping / rebirths.

	Pet models are built from simple parts on the client (PetBuilder), described by Look.
	Weight = relative chance inside its egg. Luck (gem upgrade) multiplies weights of Rare+.
]]

local PetConfig = {}

PetConfig.Rarities = {
	Common = { Order = 1, Color = Color3.fromRGB(200, 205, 215), Sound = "PetCommon" },
	Rare = { Order = 2, Color = Color3.fromRGB(70, 170, 255), Sound = "PetRare" },
	Epic = { Order = 3, Color = Color3.fromRGB(180, 90, 255), Sound = "PetRare" },
	Legendary = { Order = 4, Color = Color3.fromRGB(255, 190, 40), Sound = "PetLegendary" },
	Mythic = { Order = 5, Color = Color3.fromRGB(255, 70, 110), Sound = "PetLegendary" },
	Secret = { Order = 6, Color = Color3.fromRGB(20, 20, 25), Sound = "PetSecret" },
}
PetConfig.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

PetConfig.BaseEquip = 3
PetConfig.BaseStorage = 30
PetConfig.StoragePerGemLevel = 5
PetConfig.LuckPerGemLevel = 0.1 -- +10% Rare+ weight per level
PetConfig.MaxHatchCount = 3 -- hatch 1 or 3 at once

-- Look: Body/Accent colours + shape flags for PetBuilder.
-- Ears: "Pointy" | "Floppy" | "Long" | "Round" | "None";  Extra: "Horn" | "Wings" | "Halo" | "Antenna" | "Ring" | "Beak" | nil
PetConfig.Pets = {
	-- Basic Egg --------------------------------------------------------------
	Doggy = { Name = "Doggy", Rarity = "Common", Mult = 1.1, Look = { Body = Color3.fromRGB(210, 160, 110), Accent = Color3.fromRGB(120, 80, 50), Ears = "Floppy" } },
	Kitty = { Name = "Kitty", Rarity = "Common", Mult = 1.15, Look = { Body = Color3.fromRGB(255, 170, 90), Accent = Color3.fromRGB(255, 240, 220), Ears = "Pointy" } },
	Bunny = { Name = "Bunny", Rarity = "Rare", Mult = 1.5, Look = { Body = Color3.fromRGB(245, 245, 250), Accent = Color3.fromRGB(255, 160, 190), Ears = "Long" } },
	Piggy = { Name = "Piggy", Rarity = "Epic", Mult = 2, Look = { Body = Color3.fromRGB(255, 160, 185), Accent = Color3.fromRGB(230, 110, 150), Ears = "Pointy", Snout = true } },
	GoldenChick = { Name = "Golden Chick", Rarity = "Legendary", Mult = 5, Look = { Body = Color3.fromRGB(255, 215, 60), Accent = Color3.fromRGB(255, 140, 20), Ears = "None", Extra = "Beak", Neon = true } },
	RainbowFox = { Name = "Rainbow Fox", Rarity = "Mythic", Mult = 10, Look = { Body = Color3.fromRGB(255, 90, 160), Accent = Color3.fromRGB(90, 220, 255), Ears = "Pointy", Rainbow = true, Neon = true } },
	TallNoob = { Name = "Tall Noob", Rarity = "Secret", Mult = 25, Look = { Body = Color3.fromRGB(245, 205, 50), Accent = Color3.fromRGB(40, 110, 220), Ears = "None", Tall = true, Sparkle = true } },

	-- Big Egg ----------------------------------------------------------------
	Bear = { Name = "Bear", Rarity = "Common", Mult = 1.5, Look = { Body = Color3.fromRGB(140, 95, 60), Accent = Color3.fromRGB(90, 60, 40), Ears = "Round" } },
	Panda = { Name = "Panda", Rarity = "Common", Mult = 1.6, Look = { Body = Color3.fromRGB(245, 245, 245), Accent = Color3.fromRGB(30, 30, 35), Ears = "Round" } },
	Penguin = { Name = "Penguin", Rarity = "Rare", Mult = 2.5, Look = { Body = Color3.fromRGB(40, 45, 60), Accent = Color3.fromRGB(255, 170, 40), Ears = "None", Extra = "Beak" } },
	Fox = { Name = "Fox", Rarity = "Epic", Mult = 4, Look = { Body = Color3.fromRGB(255, 120, 40), Accent = Color3.fromRGB(255, 245, 235), Ears = "Pointy" } },
	Unicorn = { Name = "Unicorn", Rarity = "Legendary", Mult = 10, Look = { Body = Color3.fromRGB(255, 240, 255), Accent = Color3.fromRGB(255, 120, 220), Ears = "Pointy", Extra = "Horn", Neon = true } },
	CrystalDragon = { Name = "Crystal Dragon", Rarity = "Mythic", Mult = 22, Look = { Body = Color3.fromRGB(120, 230, 255), Accent = Color3.fromRGB(255, 255, 255), Ears = "Pointy", Extra = "Wings", Neon = true, Sparkle = true } },
	StretchyCat = { Name = "Stretchy Cat", Rarity = "Secret", Mult = 60, Look = { Body = Color3.fromRGB(60, 60, 70), Accent = Color3.fromRGB(120, 255, 120), Ears = "Pointy", Tall = true, Sparkle = true } },

	-- Giant Egg --------------------------------------------------------------
	CloudPup = { Name = "Cloud Pup", Rarity = "Common", Mult = 3, Look = { Body = Color3.fromRGB(240, 248, 255), Accent = Color3.fromRGB(170, 210, 255), Ears = "Floppy" } },
	SkyWhale = { Name = "Sky Whale", Rarity = "Common", Mult = 3.3, Look = { Body = Color3.fromRGB(90, 150, 230), Accent = Color3.fromRGB(230, 240, 255), Ears = "None" } },
	StormBird = { Name = "Storm Bird", Rarity = "Rare", Mult = 5, Look = { Body = Color3.fromRGB(80, 90, 130), Accent = Color3.fromRGB(255, 240, 90), Ears = "None", Extra = "Wings" } },
	ThunderWolf = { Name = "Thunder Wolf", Rarity = "Epic", Mult = 9, Look = { Body = Color3.fromRGB(70, 80, 120), Accent = Color3.fromRGB(120, 230, 255), Ears = "Pointy", Neon = true } },
	Angel = { Name = "Angel", Rarity = "Legendary", Mult = 22, Look = { Body = Color3.fromRGB(255, 250, 235), Accent = Color3.fromRGB(255, 220, 90), Ears = "None", Extra = "Halo", Neon = true } },
	Phoenix = { Name = "Phoenix", Rarity = "Mythic", Mult = 50, Look = { Body = Color3.fromRGB(255, 90, 30), Accent = Color3.fromRGB(255, 220, 60), Ears = "None", Extra = "Wings", Neon = true, Sparkle = true } },
	Titan = { Name = "Titan", Rarity = "Secret", Mult = 140, Look = { Body = Color3.fromRGB(30, 30, 35), Accent = Color3.fromRGB(255, 60, 60), Ears = "None", Tall = true, Sparkle = true } },

	-- Galaxy Egg -------------------------------------------------------------
	MoonBunny = { Name = "Moon Bunny", Rarity = "Common", Mult = 8, Look = { Body = Color3.fromRGB(210, 215, 235), Accent = Color3.fromRGB(150, 160, 200), Ears = "Long" } },
	Alien = { Name = "Alien", Rarity = "Common", Mult = 9, Look = { Body = Color3.fromRGB(120, 240, 110), Accent = Color3.fromRGB(20, 30, 20), Ears = "None", Extra = "Antenna" } },
	RocketDog = { Name = "Rocket Dog", Rarity = "Rare", Mult = 14, Look = { Body = Color3.fromRGB(230, 230, 240), Accent = Color3.fromRGB(255, 80, 60), Ears = "Floppy", Extra = "Antenna" } },
	Comet = { Name = "Comet", Rarity = "Epic", Mult = 25, Look = { Body = Color3.fromRGB(120, 200, 255), Accent = Color3.fromRGB(255, 255, 255), Ears = "None", Neon = true, Sparkle = true } },
	StarGuardian = { Name = "Star Guardian", Rarity = "Legendary", Mult = 60, Look = { Body = Color3.fromRGB(255, 225, 80), Accent = Color3.fromRGB(120, 80, 255), Ears = "Pointy", Extra = "Halo", Neon = true, Sparkle = true } },
	BlackHole = { Name = "Black Hole", Rarity = "Mythic", Mult = 150, Look = { Body = Color3.fromRGB(15, 10, 25), Accent = Color3.fromRGB(200, 90, 255), Ears = "None", Extra = "Ring", Neon = true, Sparkle = true } },
	TheTallest = { Name = "The Tallest", Rarity = "Secret", Mult = 500, Look = { Body = Color3.fromRGB(255, 255, 255), Accent = Color3.fromRGB(255, 60, 220), Ears = "Pointy", Tall = true, Rainbow = true, Sparkle = true, Neon = true } },
}

PetConfig.Eggs = {
	{
		Id = "Basic",
		Name = "Basic Egg",
		Cost = 100,
		Zone = 1,
		Color = Color3.fromRGB(245, 240, 225),
		Spots = Color3.fromRGB(120, 200, 255),
		Pets = {
			{ Id = "Doggy", Weight = 42 },
			{ Id = "Kitty", Weight = 34 },
			{ Id = "Bunny", Weight = 16.5 },
			{ Id = "Piggy", Weight = 6 },
			{ Id = "GoldenChick", Weight = 1.4 },
			{ Id = "RainbowFox", Weight = 0.098 },
			{ Id = "TallNoob", Weight = 0.002 },
		},
	},
	{
		Id = "Big",
		Name = "Big Egg",
		Cost = 1e4,
		Zone = 2,
		Color = Color3.fromRGB(150, 220, 120),
		Spots = Color3.fromRGB(255, 240, 120),
		Pets = {
			{ Id = "Bear", Weight = 42 },
			{ Id = "Panda", Weight = 34 },
			{ Id = "Penguin", Weight = 16.5 },
			{ Id = "Fox", Weight = 6 },
			{ Id = "Unicorn", Weight = 1.4 },
			{ Id = "CrystalDragon", Weight = 0.098 },
			{ Id = "StretchyCat", Weight = 0.002 },
		},
	},
	{
		Id = "Giant",
		Name = "Giant Egg",
		Cost = 1e6,
		Zone = 4,
		Color = Color3.fromRGB(190, 225, 255),
		Spots = Color3.fromRGB(255, 255, 255),
		Pets = {
			{ Id = "CloudPup", Weight = 42 },
			{ Id = "SkyWhale", Weight = 34 },
			{ Id = "StormBird", Weight = 16.5 },
			{ Id = "ThunderWolf", Weight = 6 },
			{ Id = "Angel", Weight = 1.4 },
			{ Id = "Phoenix", Weight = 0.098 },
			{ Id = "Titan", Weight = 0.002 },
		},
	},
	{
		Id = "Galaxy",
		Name = "Galaxy Egg",
		Cost = 1e9,
		Zone = 7,
		Color = Color3.fromRGB(90, 40, 160),
		Spots = Color3.fromRGB(255, 120, 240),
		Pets = {
			{ Id = "MoonBunny", Weight = 42 },
			{ Id = "Alien", Weight = 34 },
			{ Id = "RocketDog", Weight = 16.5 },
			{ Id = "Comet", Weight = 6 },
			{ Id = "StarGuardian", Weight = 1.4 },
			{ Id = "BlackHole", Weight = 0.098 },
			{ Id = "TheTallest", Weight = 0.002 },
		},
	},
}

function PetConfig.GetEgg(eggId: string)
	for _, egg in PetConfig.Eggs do
		if egg.Id == eggId then
			return egg
		end
	end
	return nil
end

-- Chance table for display, luck applied: { {Id, Chance(0..1)} }
function PetConfig.Chances(egg, luckMult: number?)
	local luck = luckMult or 1
	local total = 0
	local weights = {}
	for i, entry in egg.Pets do
		local pet = PetConfig.Pets[entry.Id]
		local w = entry.Weight
		if pet and pet.Rarity ~= "Common" then
			w *= luck
		end
		weights[i] = w
		total += w
	end
	local out = {}
	for i, entry in egg.Pets do
		table.insert(out, { Id = entry.Id, Chance = weights[i] / total })
	end
	return out
end

-- Weighted roll. `r` is a number in [0, 1).
function PetConfig.Roll(egg, r: number, luckMult: number?): string
	local chances = PetConfig.Chances(egg, luckMult)
	local acc = 0
	for _, c in chances do
		acc += c.Chance
		if r < acc then
			return c.Id
		end
	end
	return chances[1].Id
end

return PetConfig
