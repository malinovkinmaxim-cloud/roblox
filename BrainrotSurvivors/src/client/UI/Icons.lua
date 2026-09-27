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

Icons.Stat = {
	Might = "DMG",
	AttackSpeed = "ATK",
	Cooldown = "CD",
	Area = "AREA",
	Amount = "+1",
	MoveSpeed = "SPD",
	Growth = "XP",
	Crit = "CRIT",
	Magnet = "MAG",
	MaxHP = "HP",
	Regen = "REG",
	Armor = "ARM",
	Luck = "LUCK",
	Greed = "GOLD",
	Reroll = "RR",
	Revive = "REV",
	ExtraWeapon = "+W",
	WeaponSlot = "SLOT",
}

Icons.Rare = {
	Percent67 = "67%",
	SigmaMode = "Σ",
	Overdrive = "OVR",
	GooberArmy = "ARMY",
	MainCharacter = "MC",
	Mewing = "MEW",
	AuraFarming = "AURA",
	Awaken = "AWK",
}

Icons.Filler = { Snack = "+HP", Coins = "$" }

Icons.Buff = { Sigma = "Σ", Storm = "STRM", XP67 = "XP", Damage67 = "DMG" }

Icons.Product = {
	VIP = "VIP",
	DoubleCoins = "2×",
	DoubleXP = "2×XP",
	Cosmetics = "FX",
	ExtraLoadout = "+W",
	Revive = "REV",
	CoinRush = "+50%",
}

Icons.Menu = {
	Achievements = "Star",
	Leaderboard = "Podium",
	Statistics = "Chart",
	Codes = "Ticket",
	Settings = "Gear",
	Credits = "Info",
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
	elseif kind == "Character" then
		local holder = Kit.New("Frame", { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
		if props then
			for k, v in props do
				(holder :: any)[k] = v
			end
		end
		Previews.Character(holder, key)
		return holder
	elseif kind == "Hat" then
		local holder = Kit.New("Frame", { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
		if props then
			for k, v in props do
				(holder :: any)[k] = v
			end
		end
		Previews.Hat(holder, key)
		return holder
	elseif kind == "Rare" then
		return mono(parent, Icons.Rare[key] or "?", Theme.Rarity.Rare, size, props)
	elseif kind == "Filler" then
		return mono(parent, Icons.Filler[key] or "?", C.Success, size, props)
	elseif kind == "Buff" then
		return mono(parent, Icons.Buff[key] or "?", C.Accent, size, props)
	elseif kind == "Product" then
		if key == "CoinsSmall" or key == "CoinsBig" then
			local holder = Kit.New("Frame", { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
			if props then
				for k, v in props do
					(holder :: any)[k] = v
				end
			end
			local n = if key == "CoinsBig" then 3 else 1
			for i = 1, n do
				Widgets.Coin(holder, math.floor(size * 0.62), {
					Position = UDim2.fromScale(0.5 + (i - (n + 1) / 2) * 0.16, 0.5 - (i - 1) * 0.06),
					AnchorPoint = Vector2.new(0.5, 0.5),
				})
			end
			return holder
		end
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
