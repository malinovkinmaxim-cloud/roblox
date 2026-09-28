--[[
	Icons - one place that decides how a thing is pictured in the UI (no emoji art):
	  weapons, characters, hats  -> 3D previews (UI/Previews)
	  passives, upgrades, products, cosmetics -> an image from UI/IconImages when one is set,
	      else a drawn placeholder: a rounded tile in the category colour with a symbol
	  menu entries -> drawn glyphs (Widgets.Glyph)
	Icons.Make(parent, kind, key, size, props?) returns the icon instance.
	Icons.Tile(parent, symbol, color, size, props?, image?) draws one tile (used by the shop for
	cosmetics too).
]]

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Previews = require(script.Parent.Previews)
local Kit = require(script.Parent.Kit)
local IconImages = require(script.Parent.IconImages)

local Icons = {}

local C = Theme.Colors
local rgb = Color3.fromRGB

-- symbol + colour of each category (one style for every placeholder)
Icons.Categories = {
	Attack = rgb(255, 118, 112),
	Speed = rgb(96, 212, 255),
	Area = rgb(186, 132, 255),
	Health = rgb(104, 222, 140),
	Defense = rgb(122, 162, 255),
	Growth = rgb(255, 208, 86),
	Coin = rgb(255, 184, 72),
	Special = rgb(255, 122, 200),
}

-- passives and permanent upgrades -> category
Icons.Stat = {
	Power = "Attack",
	RapidFire = "Speed",
	Expansion = "Area",
	Swiftness = "Speed",
	Wisdom = "Growth",
	Magnet = "Area",
	Vitality = "Health",
	Regeneration = "Health",
	Greed = "Coin",
	Duration = "Area",
	CritMaster = "Attack",
	Armor = "Defense",
	Luck = "Coin",
	Vampire = "Health",
	Berserk = "Attack",
	OrbitalMastery = "Area",
	BurnMastery = "Area",
	DoubleShot = "Attack",
	Execution = "Attack",
	XPStorm = "Growth",
	Percent67 = "Special",
	TouchGrass = "Special",
	Might = "Attack",
	MaxHP = "Health",
	MoveSpeed = "Speed",
	Growth = "Growth",
	Regen = "Health",
	Reroll = "Special",
	Revive = "Defense",
	ExtraWeapon = "Special",
	WeaponSlot = "Special",
}

Icons.Filler = { Snack = "Health", Coins = "Coin" }

Icons.Product = {
	VIPCosmetics = "Special",
	CosmeticPass = "Special",
	ExtraLoadout = "Special",
	ExtraHeroSlot = "Growth",
	AfkCapacity = "Growth",
	Revive = "Defense",
	ExtraReroll = "Special",
	ExtraChest = "Coin",
	CosmeticBoost = "Special",
	AfkBoost = "Growth",
	Support1 = "Health",
	Support2 = "Health",
	Support3 = "Health",
}

-- cosmetic category -> symbol (the tile takes the cosmetic's own colour)
Icons.CosmeticSymbol = {
	AbilitySkin = "Attack",
	KillEffect = "Special",
	SpawnEffect = "Area",
	Trail = "Speed",
	Emote = "Special",
	NameEffect = "Growth",
	LobbyDecor = "Defense",
	Victory = "Growth",
	UITheme = "Area",
	Aura = "Area",
}

Icons.Menu = {
	Achievements = "Star",
	Collection = "Book",
	Challenges = "Flag",
	AfkCamp = "Fire",
	Party = "People",
	Leaderboard = "Podium",
	Statistics = "Chart",
	Codes = "Ticket",
	Credits = "Star",
	HowToPlay = "Info",
	Settings = "Gear",
}

local function piece(parent: Instance, w: number, h: number, x: number, y: number, color: Color3, round: number?): Frame
	local f = Kit.New("Frame", {
		Size = UDim2.fromScale(w, h),
		Position = UDim2.fromScale(x, y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Kit.Corner(f, round or 3)
	return f
end

-- the symbol of a category, drawn from a few rounded frames (no text, no image assets)
local function symbol(tile: Frame, kind: string, size: number, color: Color3)
	local ink = color:Lerp(Color3.new(1, 1, 1), 0.55)
	local r = math.max(2, math.floor(size * 0.05))
	if kind == "Attack" then -- a sword
		piece(tile, 0.13, 0.46, 0.5, 0.38, ink, r)
		piece(tile, 0.46, 0.1, 0.5, 0.63, ink, r)
		piece(tile, 0.1, 0.16, 0.5, 0.74, ink, r)
		piece(tile, 0.16, 0.16, 0.5, 0.84, ink, size)
	elseif kind == "Speed" then -- speed lines
		for i, w in { 0.56, 0.42, 0.28 } do
			piece(tile, w, 0.1, 0.22 + w / 2, 0.3 + (i - 1) * 0.2, ink, r)
		end
	elseif kind == "Area" then -- a ring around a dot
		local ring = piece(tile, 0.62, 0.62, 0.5, 0.5, ink, size)
		ring.BackgroundTransparency = 1
		Kit.Stroke(ring, math.max(2, size * 0.07), ink, 0)
		piece(tile, 0.2, 0.2, 0.5, 0.5, ink, size)
	elseif kind == "Health" then -- a cross
		piece(tile, 0.18, 0.56, 0.5, 0.5, ink, r)
		piece(tile, 0.56, 0.18, 0.5, 0.5, ink, r)
	elseif kind == "Defense" then -- a shield
		piece(tile, 0.5, 0.58, 0.5, 0.5, ink, math.floor(size * 0.16))
		piece(tile, 0.08, 0.4, 0.5, 0.5, color:Lerp(Color3.new(0, 0, 0), 0.25), r)
	elseif kind == "Growth" then -- rising bars
		for i, h in { 0.26, 0.42, 0.58 } do
			local bar = piece(tile, 0.14, h, 0.3 + (i - 1) * 0.2, 0.78 - h / 2, ink, r)
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
		end
	elseif kind == "Coin" then -- a coin
		piece(tile, 0.56, 0.56, 0.5, 0.5, ink, size)
		piece(tile, 0.3, 0.3, 0.5, 0.5, color, size)
	else -- Special: a four-point sparkle
		piece(tile, 0.14, 0.62, 0.5, 0.5, ink, size)
		piece(tile, 0.62, 0.14, 0.5, 0.5, ink, size)
		piece(tile, 0.26, 0.26, 0.5, 0.5, ink, math.floor(size * 0.06))
	end
end

-- one icon tile: category colour, soft border, an image (when set) or the category symbol
function Icons.Tile(parent: Instance, kind: string, color: Color3, size: number, props: { [string]: any }?, image: string?): Frame
	local tile = Kit.New("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(tile :: any)[k] = v
		end
	end
	Kit.Corner(tile, math.floor(size * 0.28))
	Kit.Stroke(tile, 1.5, color, 0.2)
	Kit.New("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.45) }),
		Rotation = 90,
		Parent = tile,
	})
	if image and image ~= "" then
		Kit.New("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Image = image,
			Size = UDim2.fromScale(0.78, 0.78),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ScaleType = Enum.ScaleType.Fit,
			Parent = tile,
		})
	else
		symbol(tile, kind, size, color)
	end
	return tile
end

local function categoryTile(parent: Instance, map, images, key: string, size: number, props)
	local kind = map[key] or "Special"
	return Icons.Tile(parent, kind, Icons.Categories[kind] or C.Accent, size, props, images and images[key])
end

function Icons.Make(parent: Instance, kind: string, key: string, size: number, props: { [string]: any }?): GuiObject
	if kind == "Weapon" then
		local holder = Kit.New("Frame", { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
		if props then
			for k, v in props do
				(holder :: any)[k] = v
			end
		end
		Previews.Weapon(holder, key)
		return holder
	elseif kind == "Hero" or kind == "Hat" or kind == "Enemy" then
		local holder = Kit.New("Frame", { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
		if props then
			for k, v in props do
				(holder :: any)[k] = v
			end
		end
		if kind == "Hero" then
			Previews.Hero(holder, key)
		elseif kind == "Hat" then
			Previews.Hat(holder, key)
		else
			Previews.Enemy(holder, key)
		end
		return holder
	elseif kind == "Filler" then
		return categoryTile(parent, Icons.Filler, IconImages.Filler, key, size, props)
	elseif kind == "Product" then
		return categoryTile(parent, Icons.Product, IconImages.Product, key, size, props)
	elseif kind == "Menu" then
		local badge = Widgets.Mono(parent, "", C.Accent, size, props)
		Widgets.Glyph(badge, Icons.Menu[key] or "Star", math.floor(size * 0.6), C.Accent:Lerp(Color3.new(1, 1, 1), 0.3), {
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
		})
		return badge
	end
	return categoryTile(parent, Icons.Stat, IconImages.Stat, key, size, props)
end

-- a cosmetic without a 3D preview: its colour, the symbol of its category
function Icons.Cosmetic(parent: Instance, def, size: number, props: { [string]: any }?): Frame
	local color = def.Color or Theme.Rarity[def.Rarity] or C.Accent
	return Icons.Tile(parent, Icons.CosmeticSymbol[def.Category] or "Special", color, size, props, IconImages.Cosmetic[def.Id])
end

return Icons
