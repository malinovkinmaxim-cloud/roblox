--[[
	Icons - one place that decides how a thing is pictured in the UI (no emoji art):
	  weapons, characters, hats  -> 3D previews (UI/Previews)
	  stats, rare cards, products, menu entries -> monogram badges (Widgets.Mono)
	Icons.Make(parent, kind, key, size, props?) returns the icon instance.
]]

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Previews = require(script.Parent.Previews)
local Kit = require(script.Parent.Kit)

local Icons = {}

local C = Theme.Colors

-- passives and permanent upgrades: short, readable monograms
Icons.Stat = {
	-- passives
	Power = "DMG",
	RapidFire = "ATK",
	Expansion = "AREA",
	Swiftness = "SPD",
	Wisdom = "XP",
	Magnet = "MAG",
	Vitality = "HP",
	Regeneration = "REG",
	Greed = "GOLD",
	Duration = "DUR",
	CritMaster = "CRIT",
	Armor = "ARM",
	Luck = "LUCK",
	Vampire = "VAMP",
	Berserk = "RAGE",
	OrbitalMastery = "ORB",
	BurnMastery = "BURN",
	DoubleShot = "+1",
	Execution = "EXE",
	XPStorm = "XP×2",
	Percent67 = "67%",
	TouchGrass = "???",
	-- permanent upgrades
	Might = "DMG",
	MaxHP = "HP",
	MoveSpeed = "SPD",
	Growth = "XP",
	Regen = "REG",
	Reroll = "RR",
	Revive = "REV",
	ExtraWeapon = "+1",
	WeaponSlot = "SLOT",
}

Icons.Filler = { Snack = "+HP", Coins = "$" }

Icons.Product = {
	VIPCosmetics = "VIP",
	CosmeticPass = "FX",
	ExtraLoadout = "+L",
	ExtraHeroSlot = "+H",
	AfkCapacity = "4H",
	Revive = "REV",
	ExtraReroll = "RR",
	ExtraChest = "BOX",
	CosmeticBoost = "67",
	AfkBoost = "×2",
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
	Credits = "Info",
	Settings = "Gear",
}

local function mono(parent, text: string, color: Color3, size: number, props)
	return Widgets.Mono(parent, text, color, size, props)
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
		return mono(parent, Icons.Filler[key] or "?", C.Success, size, props)
	elseif kind == "Product" then
		return mono(parent, Icons.Product[key] or "?", C.Gold, size, props)
	elseif kind == "Menu" then
		local badge = mono(parent, "", C.Accent, size, props)
		Widgets.Glyph(badge, Icons.Menu[key] or "Star", math.floor(size * 0.6), C.Accent:Lerp(Color3.new(1, 1, 1), 0.3), {
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
		})
		return badge
	end
	return mono(parent, Icons.Stat[key] or string.upper(string.sub(key, 1, 3)), C.TextDim, size, props)
end

return Icons
