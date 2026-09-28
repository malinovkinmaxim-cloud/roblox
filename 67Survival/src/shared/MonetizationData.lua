--[[
	MonetizationData - Robux items. Cosmetics first, convenience second, never power:
	nothing here makes a run easier to win. The paid revive is limited to once per run
	(after the free ones), an extra reroll only shows when you are out of rerolls.

	HOW TO CONFIGURE: create the Game Passes and Developer Products on the Creator Dashboard
	and paste their ids below. An id of 0 means "not configured": the shop shows the item
	as unavailable in live servers, and in Studio buying it runs a fake purchase so every
	reward can be tested.
]]

export type PassDef = { Key: string, Name: string, Desc: string, Id: number, Price: number }
export type ProductDef = { Key: string, Name: string, Desc: string, Id: number, Price: number, Minutes: number? }

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
} :: { ProductDef }

MonetizationData.PassByKey = {} :: { [string]: PassDef }
for _, def in MonetizationData.Passes do
	MonetizationData.PassByKey[def.Key] = def
end
MonetizationData.ProductByKey = {} :: { [string]: ProductDef }
for _, def in MonetizationData.Products do
	MonetizationData.ProductByKey[def.Key] = def
end

return MonetizationData
