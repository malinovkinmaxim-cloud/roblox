--[[
	CosmeticsConfig
	Everything purely visual that can be bought with coins. Nothing here changes gameplay.
	Categories:
	  Skin  - the doppelgänger's look          (recipes: server Doppelganger/Skins.lua)
	  Trail - a trail behind YOUR character     (applied by CharacterService)
	  Emote - what your doppelgänger does when you finish a level (and when you idle in the lobby)
	Titles are earned, not bought: see TitleConfig.
]]

local CosmeticsConfig = {}

CosmeticsConfig.Categories = { "Skin", "Trail", "Emote" }

CosmeticsConfig.Defaults = {
	Skin = "Default",
	Trail = "Trail_None",
	Emote = "Emote_Wave",
}

CosmeticsConfig.Order = {
	-- skins
	"Default",
	"Noob",
	"SadCat",
	"Dog",
	"Robot",
	"Glitch",
	"Shadow",
	"Alien",
	"Golden",
	-- trails
	"Trail_None",
	"Trail_Cyan",
	"Trail_Fire",
	"Trail_Shadow",
	"Trail_Rainbow",
	"Trail_Gold",
	-- emotes
	"Emote_Wave",
	"Emote_Cheer",
	"Emote_Point",
	"Emote_Laugh",
	"Emote_Dance",
}

CosmeticsConfig.Items = {
	---------------------------------------------------------------- skins
	Default = {
		Category = "Skin",
		DisplayName = "Mirror",
		Description = "Exactly you.",
		Price = 0,
		Color = Color3.fromRGB(200, 220, 255),
	},
	Noob = {
		Category = "Skin",
		DisplayName = "Noob",
		Description = "Classic yellow, blue and green.",
		Price = 100,
		Color = Color3.fromRGB(245, 205, 48),
	},
	SadCat = {
		Category = "Skin",
		DisplayName = "Sad Cat",
		Description = "Grey fur. Pointy ears. Very sad.",
		Price = 300,
		Color = Color3.fromRGB(160, 165, 175),
	},
	Dog = {
		Category = "Skin",
		DisplayName = "Dog",
		Description = "Floppy ears, good boy energy.",
		Price = 300,
		Color = Color3.fromRGB(170, 115, 70),
	},
	Robot = {
		Category = "Skin",
		DisplayName = "Robot",
		Description = "Brushed metal and a tiny antenna.",
		Price = 500,
		Color = Color3.fromRGB(150, 160, 175),
	},
	Glitch = {
		Category = "Skin",
		DisplayName = "Glitch",
		Description = "Something is wrong with your reflection.",
		Price = 750,
		Color = Color3.fromRGB(255, 60, 200),
	},
	Shadow = {
		Category = "Skin",
		DisplayName = "Shadow",
		Description = "Pure darkness.",
		Price = 750,
		Color = Color3.fromRGB(35, 35, 45),
	},
	Alien = {
		Category = "Skin",
		DisplayName = "Alien",
		Description = "Green skin, glowing eyes.",
		Price = 1000,
		Color = Color3.fromRGB(110, 230, 90),
	},
	Golden = {
		Category = "Skin",
		DisplayName = "Golden",
		Description = "For true doppel masters.",
		Price = 1500,
		Color = Color3.fromRGB(255, 200, 60),
	},

	---------------------------------------------------------------- trails
	Trail_None = {
		Category = "Trail",
		DisplayName = "No Trail",
		Description = "Clean and simple.",
		Price = 0,
		Color = Color3.fromRGB(90, 95, 110),
	},
	Trail_Cyan = {
		Category = "Trail",
		DisplayName = "Doppel Cyan",
		Description = "The colour of your double.",
		Price = 200,
		Color = Color3.fromRGB(60, 225, 255),
		Colors = { Color3.fromRGB(60, 225, 255), Color3.fromRGB(120, 170, 255) },
	},
	Trail_Fire = {
		Category = "Trail",
		DisplayName = "Fire",
		Description = "Leave the rival in the smoke.",
		Price = 350,
		Color = Color3.fromRGB(255, 120, 40),
		Colors = { Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 60, 30) },
	},
	Trail_Shadow = {
		Category = "Trail",
		DisplayName = "Shadow Smoke",
		Description = "A shadow of your shadow.",
		Price = 400,
		Color = Color3.fromRGB(110, 70, 170),
		Colors = { Color3.fromRGB(150, 100, 230), Color3.fromRGB(25, 20, 35) },
	},
	Trail_Rainbow = {
		Category = "Trail",
		DisplayName = "Rainbow",
		Description = "Every colour at once.",
		Price = 600,
		Color = Color3.fromRGB(255, 90, 180),
		Colors = {
			Color3.fromRGB(255, 70, 70),
			Color3.fromRGB(255, 210, 60),
			Color3.fromRGB(80, 230, 120),
			Color3.fromRGB(60, 180, 255),
			Color3.fromRGB(190, 90, 255),
		},
	},
	Trail_Gold = {
		Category = "Trail",
		DisplayName = "Gold Dust",
		Description = "Shiny. Very shiny.",
		Price = 800,
		Color = Color3.fromRGB(255, 200, 60),
		Colors = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(230, 160, 20) },
	},

	---------------------------------------------------------------- emotes (doppelgänger)
	Emote_Wave = {
		Category = "Emote",
		DisplayName = "Wave",
		Description = "Your double waves goodbye.",
		Price = 0,
		Color = Color3.fromRGB(120, 215, 255),
		Animation = "Wave",
	},
	Emote_Cheer = {
		Category = "Emote",
		DisplayName = "Cheer",
		Description = "Arms up! We did it!",
		Price = 150,
		Color = Color3.fromRGB(80, 230, 140),
		Animation = "Cheer",
	},
	Emote_Point = {
		Category = "Emote",
		DisplayName = "Point",
		Description = "It points at you. Suspicious.",
		Price = 150,
		Color = Color3.fromRGB(255, 210, 70),
		Animation = "Point",
	},
	Emote_Laugh = {
		Category = "Emote",
		DisplayName = "Laugh",
		Description = "Ha. Ha. Ha.",
		Price = 250,
		Color = Color3.fromRGB(255, 80, 200),
		Animation = "Laugh",
	},
	Emote_Dance = {
		Category = "Emote",
		DisplayName = "Dance",
		Description = "Victory dance, perfectly in sync.",
		Price = 400,
		Color = Color3.fromRGB(170, 120, 255),
		Animation = "Dance",
	},
}

function CosmeticsConfig.Get(id: string)
	return CosmeticsConfig.Items[id]
end

-- Profile field that stores the equipped item of a category
CosmeticsConfig.EquipField = {
	Skin = "EquippedCosmetic",
	Trail = "EquippedTrail",
	Emote = "EquippedEmote",
}

return CosmeticsConfig
