--[[
	CosmeticsConfig
	Doppelgänger skins. Purely visual - no skin changes gameplay.
	Visual recipes are applied on the server by Doppelganger/Skins.lua.
]]

local CosmeticsConfig = {}

CosmeticsConfig.Order = { "Default", "Noob", "SadCat", "Dog", "Robot", "Glitch", "Shadow", "Alien", "Golden" }

CosmeticsConfig.Items = {
	Default = {
		DisplayName = "Mirror",
		Description = "Exactly you.",
		Price = 0,
		Color = Color3.fromRGB(200, 220, 255),
	},
	Noob = {
		DisplayName = "Noob",
		Description = "Classic yellow, blue and green.",
		Price = 100,
		Color = Color3.fromRGB(245, 205, 48),
	},
	SadCat = {
		DisplayName = "Sad Cat",
		Description = "Grey fur. Pointy ears. Very sad.",
		Price = 300,
		Color = Color3.fromRGB(160, 165, 175),
	},
	Dog = {
		DisplayName = "Dog",
		Description = "Floppy ears, good boy energy.",
		Price = 300,
		Color = Color3.fromRGB(170, 115, 70),
	},
	Robot = {
		DisplayName = "Robot",
		Description = "Brushed metal and a tiny antenna.",
		Price = 500,
		Color = Color3.fromRGB(150, 160, 175),
	},
	Glitch = {
		DisplayName = "Glitch",
		Description = "Something is wrong with your reflection.",
		Price = 750,
		Color = Color3.fromRGB(255, 60, 200),
	},
	Shadow = {
		DisplayName = "Shadow",
		Description = "Pure darkness.",
		Price = 750,
		Color = Color3.fromRGB(35, 35, 45),
	},
	Alien = {
		DisplayName = "Alien",
		Description = "Green skin, glowing eyes.",
		Price = 1000,
		Color = Color3.fromRGB(110, 230, 90),
	},
	Golden = {
		DisplayName = "Golden",
		Description = "For true doppel masters.",
		Price = 1500,
		Color = Color3.fromRGB(255, 200, 60),
	},
}

function CosmeticsConfig.Get(id: string)
	return CosmeticsConfig.Items[id]
end

return CosmeticsConfig
