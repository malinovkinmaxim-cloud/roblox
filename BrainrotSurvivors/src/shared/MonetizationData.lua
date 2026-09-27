--[[
	MonetizationData - Robux items. Nothing here makes a run winnable by paying:
	passes give coins / account XP / cosmetics / convenience, the paid revive is limited
	to once per run (after the free ones), boosts only affect coins.

	HOW TO CONFIGURE: create the Game Passes and Developer Products on the Creator Dashboard
	and paste their ids below. An id of 0 means "not configured": the shop shows the item
	as unavailable in live servers, and in Studio buying it runs a fake purchase so every
	reward can be tested.
]]

export type PassDef = { Key: string, Name: string, Icon: string, Desc: string, Id: number, Price: number }
export type ProductDef = { Key: string, Name: string, Icon: string, Desc: string, Id: number, Price: number, Coins: number?, BoostMinutes: number? }

local MonetizationData = {}

MonetizationData.Passes = {
	{ Key = "VIP", Name = "VIP", Icon = "👑", Desc = "+20% coins, golden name tag, VIP chat tag, gold trail", Id = 0, Price = 299 },
	{ Key = "DoubleCoins", Name = "2x Coins", Icon = "💰", Desc = "Double coins from every run", Id = 0, Price = 399 },
	{ Key = "DoubleXP", Name = "2x Brain XP", Icon = "🧠", Desc = "Double account XP (Brain Level) from every run", Id = 0, Price = 199 },
	{ Key = "Cosmetics", Name = "Cosmetic Pack", Icon = "🎨", Desc = "Rainbow trail + sparkle aura for every character", Id = 0, Price = 149 },
	{ Key = "ExtraLoadout", Name = "Extra Loadout", Icon = "🎒", Desc = "Pick your starting weapon from all unlocked weapons", Id = 0, Price = 249 },
} :: { PassDef }

MonetizationData.Products = {
	{ Key = "Revive", Name = "Revive", Icon = "💖", Desc = "Come back with 60% HP (once per run)", Id = 0, Price = 25 },
	{ Key = "CoinsSmall", Name = "Bag of Coins", Icon = "🪙", Desc = "+1,000 Brain Coins", Id = 0, Price = 49, Coins = 1000 },
	{ Key = "CoinsBig", Name = "Chest of Coins", Icon = "💰", Desc = "+6,000 Brain Coins", Id = 0, Price = 249, Coins = 6000 },
	{ Key = "CoinRush", Name = "Coin Rush", Icon = "⏫", Desc = "+50% coins for 30 minutes", Id = 0, Price = 39, BoostMinutes = 30 },
} :: { ProductDef }

MonetizationData.PassByKey = {} :: { [string]: PassDef }
for _, def in MonetizationData.Passes do
	MonetizationData.PassByKey[def.Key] = def
end
MonetizationData.ProductByKey = {} :: { [string]: ProductDef }
for _, def in MonetizationData.Products do
	MonetizationData.ProductByKey[def.Key] = def
end

MonetizationData.VIPCoinBonus = 0.2
MonetizationData.CoinRushBonus = 0.5

return MonetizationData
