--[[
	MonetizationData - Robux items. Cosmetics first, convenience second. The one exception
	is the PREMIUM abilities (shared/AbilityConfig.lua): Mythic abilities that are never more
	than +30% over the best free ability of their kind (tests/run.luau [premium] measures it),
	so a boss can't be trivialized. The paid revive is limited to once per run (after the free
	ones), an extra reroll only shows when you are out of rerolls.

	HOW TO SELL FOR ROBUX IN THE PUBLISHED GAME (the code already handles buying, owning,
	receipts and refunds; only the ids are missing):
	  1. Publish the place (File > Publish to Roblox), open it on create.roblox.com
	     (Creations > your experience).
	  2. Monetization > Passes: create one pass per entry of Passes below (name, picture,
	     price), put it on sale, copy its id (the number in its URL) into `Id`.
	  3. Monetization > Developer Products: create one product per entry of Products below,
	     copy each id into `Id`.
	  4. Game Settings > Security: nothing to switch on for purchases (no API access needed).
	The price shown in the game is read from Roblox (MarketplaceService:GetProductInfo), so
	it always matches what you set on the dashboard; `Price` below is only the fallback.
	An id of 0 means "not configured": live servers show the item as SOON (it can't be
	bought), and in Studio buying it runs a fake purchase so every reward can be tested.
	The server prints the items still missing an id when it starts.
]]

export type PassDef = { Key: string, Name: string, Desc: string, Id: number, Price: number, Ability: string?, Cosmetics: { string }? }
export type ProductDef = { Key: string, Name: string, Desc: string, Id: number, Price: number, Minutes: number?, Donation: boolean?, Ability: string?, Cosmetics: { string }? }

local WeaponData = require(script.Parent.WeaponData)
local AbilityConfig = require(script.Parent.AbilityConfig)

local MonetizationData = {}

MonetizationData.Passes = {
	{ Key = "VIPCosmetics", Name = "VIP Cosmetics", Desc = "Neon skin, gold ability skin, coin kill effect, rainbow trail, gold name, gold pedestal, gold aura", Id = 0, Price = 249 },
	{ Key = "CosmeticPass", Name = "Cosmetic Collection", Desc = "Glitched skin, rainbow abilities, meteor spawn, rainbow name, 67 Gold UI theme", Id = 0, Price = 299 },
	{ Key = "ExtraLoadout", Name = "Extra Loadout Slots", Desc = "Save 2 more loadouts (hero + starting ability) and switch in one tap", Id = 0, Price = 149 },
	{ Key = "ExtraHeroSlot", Name = "Extra AFK Hero Slot", Desc = "+1 hero slot in the AFK Camp", Id = 0, Price = 149 },
	{ Key = "AfkCapacity", Name = "AFK Capacity", Desc = "The AFK Camp stores rewards for 4 hours instead of 2", Id = 0, Price = 99 },
} :: { PassDef }

MonetizationData.Products = {
	{ Key = "Revive", Name = "Revive", Desc = "Come back with 60% HP (once per run)", Id = 0, Price = 25 },
	{ Key = "ExtraReroll", Name = "Extra Reroll", Desc = "+1 reroll for this run", Id = 0, Price = 10 },
	{ Key = "ExtraChest", Name = "Extra Chest", Desc = "Open one more reward chest after this run", Id = 0, Price = 29 },
	{ Key = "CosmeticBoost", Name = "67 Aura", Desc = "Wear the 67 Aura for 30 minutes", Id = 0, Price = 19, Minutes = 30 },
	{ Key = "AfkBoost", Name = "AFK Boost", Desc = "x2 AFK Camp rewards for 4 hours", Id = 0, Price = 39, Minutes = 240 },
	-- SUPPORT (donations): no reward in the game, a thank you and a supporter mark in your
	-- profile. Can be bought again and again.
	{ Key = "Support1", Name = "Say Thanks", Desc = "Support 67 Survival. No bonus in the game, just a big thank you!", Id = 0, Price = 25, Donation = true },
	{ Key = "Support2", Name = "Big Thanks", Desc = "Help the game grow: new heroes, bosses and 67 events.", Id = 0, Price = 100, Donation = true },
	{ Key = "Support3", Name = "Legendary Supporter", Desc = "The biggest thank you. You keep 67 Survival going!", Id = 0, Price = 500, Donation = true },
} :: { ProductDef }

-- PREMIUM abilities, ability skins and the trail pack: their ids live in shared/AbilityConfig.lua
-- (ProductId, Type "Gamepass" / "Product"); the entries below are made from it. Price 0: the
-- price always comes from the dashboard (no fallback number is invented here).
--   Ability   owning it puts the premium ability into your runs (shared/WeaponData.lua)
--   Cosmetics owning it gives these cosmetics (shared/CosmeticData.lua Robux)
local function sale(key: string, name: string, desc: string, config, extra: { [string]: any })
	local entry = { Key = key, Name = name, Desc = desc, Id = config.ProductId, Price = 0 }
	for k, v in extra do
		entry[k] = v
	end
	table.insert(if config.Type == "Product" then MonetizationData.Products else MonetizationData.Passes, entry)
end
for _, def in WeaponData.Premium do
	local config = AbilityConfig.Premium[def.Key]
	if config then
		sale("Ability." .. def.Key, def.Name, def.Desc, config, { Ability = def.Key })
	end
end
for _, style in AbilityConfig.SkinOrder do
	local config = AbilityConfig.Skins[style]
	sale("Skin." .. style, style .. " Ability Skin", "Every ability effect in " .. style .. ". Looks only.", config, { Cosmetics = { "WeaponSkin." .. style } })
end
do
	local pack = AbilityConfig.TrailPack
	local trails = {}
	for _, style in pack.Trails do
		table.insert(trails, "Trail." .. style)
	end
	sale("TrailPack", "Trail Pack", "Comet, Sakura and Pixel trails behind you while you run. Looks only.", pack, { Cosmetics = trails })
end

MonetizationData.PassByKey = {} :: { [string]: PassDef }
for _, def in MonetizationData.Passes do
	MonetizationData.PassByKey[def.Key] = def
end
MonetizationData.ProductByKey = {} :: { [string]: ProductDef }
for _, def in MonetizationData.Products do
	MonetizationData.ProductByKey[def.Key] = def
end

-- the pass / product that sells a premium ability ("Ability.SolarBeam67"), or nil
function MonetizationData.ForAbility(key: string): any
	return MonetizationData.PassByKey["Ability." .. key] or MonetizationData.ProductByKey["Ability." .. key]
end

-- can this item be bought here? A configured id, or a Studio test (fake purchase)
function MonetizationData.Available(def: { Id: number }, isStudio: boolean): boolean
	return def.Id ~= 0 or isStudio
end

-- the items still missing an id ("Pass VIPCosmetics", "Product Revive"...)
function MonetizationData.Unconfigured(): { string }
	local out = {}
	for _, def in MonetizationData.Passes do
		if def.Id == 0 then
			table.insert(out, "Pass " .. def.Key)
		end
	end
	for _, def in MonetizationData.Products do
		if def.Id == 0 then
			table.insert(out, "Product " .. def.Key)
		end
	end
	return out
end

return MonetizationData
