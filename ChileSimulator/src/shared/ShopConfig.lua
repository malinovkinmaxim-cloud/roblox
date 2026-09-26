--[[
	ShopConfig - Gem upgrades (permanent) and Robux items.

	HOW TO SET UP ROBUX ITEMS
	  1. Create the game passes / developer products on the Creator Dashboard.
	  2. Paste their ids into `Id` below (0 = not configured: the item shows in Studio only,
	     and buying it in Studio grants it for testing via the fake purchase flow).
	Prices are what you set on the dashboard; `Price` here is only shown in the UI.
]]

local ShopConfig = {}

-- Permanent upgrades bought with Gems. cost(level) = floor(BaseCost * Growth^level)
ShopConfig.GemUpgrades = {
	TapBonus = { Name = "Tap Power", Icon = "👆", Text = "+10% growth per tap", Per = 0.10, BaseCost = 10, Growth = 1.32, MaxLevel = 50, Order = 1 },
	AutoBonus = { Name = "Auto Growth", Icon = "🌱", Text = "+15% auto growth", Per = 0.15, BaseCost = 10, Growth = 1.32, MaxLevel = 50, Order = 2 },
	CoinBonus = { Name = "Coin Multiplier", Icon = "🪙", Text = "+10% coins", Per = 0.10, BaseCost = 12, Growth = 1.32, MaxLevel = 50, Order = 3 },
	Luck = { Name = "Luck", Icon = "🍀", Text = "+10% rare pet chance", Per = 0.10, BaseCost = 20, Growth = 1.4, MaxLevel = 25, Order = 4 },
	Storage = { Name = "Pet Storage", Icon = "🎒", Text = "+5 pet slots", Per = 5, BaseCost = 8, Growth = 1.3, MaxLevel = 30, Order = 5 },
}
ShopConfig.GemUpgradeOrder = { "TapBonus", "AutoBonus", "CoinBonus", "Luck", "Storage" }

-- Game passes. Effects are applied by the server (Formulas.Multipliers / PetService / ...).
ShopConfig.Passes = {
	VIP = {
		Id = 0,
		Price = 199,
		Name = "VIP",
		Icon = "👑",
		Perks = { "VIP tag over your head", "VIP area access", "x1.25 growth & coins forever", "Exclusive Royal aura" },
		Order = 1,
	},
	Growth2x = { Id = 0, Price = 149, Name = "x2 Growth", Icon = "📏", Perks = { "Grow twice as fast. Forever." }, Order = 2 },
	Coins2x = { Id = 0, Price = 99, Name = "x2 Coins", Icon = "🪙", Perks = { "Double coins. Forever." }, Order = 3 },
	AutoTap = { Id = 0, Price = 129, Name = "Auto Tap", Icon = "🤖", Perks = { "Toggle automatic tapping any time" }, Order = 4 },
	ExtraEquip = { Id = 0, Price = 99, Name = "Extra Pet Equip", Icon = "🐾", Perks = { "+2 equipped pets" }, Order = 5 },
	ExtraStorage = { Id = 0, Price = 49, Name = "Extra Pet Storage", Icon = "🎒", Perks = { "+100 pet slots" }, Order = 6 },
	FasterHatch = { Id = 0, Price = 79, Name = "Faster Hatch", Icon = "⚡", Perks = { "Hatch animations 3x faster" }, Order = 7 },
	VIPTrails = { Id = 0, Price = 69, Name = "VIP Trails", Icon = "✨", Perks = { "VIP Gold + VIP Diamond trails" }, Order = 8 },
}
ShopConfig.PassOrder = { "VIP", "Growth2x", "Coins2x", "AutoTap", "ExtraEquip", "ExtraStorage", "FasterHatch", "VIPTrails" }

-- Pass effects
ShopConfig.VIPMultiplier = 1.25
ShopConfig.VIPAreaBonus = 1.2 -- extra growth while standing in the VIP lounge
ShopConfig.ExtraEquipCount = 2
ShopConfig.ExtraStorageCount = 100
ShopConfig.FasterHatchSpeed = 3

-- Developer products (can be bought many times)
ShopConfig.Products = {
	BoostHeight2x = { Id = 0, Price = 19, Name = "2x Height (15 min)", Icon = "📏", Grant = { Kind = "Boost", Id = "Height2x", Count = 1 }, Order = 1 },
	BoostHeight4x = { Id = 0, Price = 39, Name = "4x Height (10 min)", Icon = "🚀", Grant = { Kind = "Boost", Id = "Height4x", Count = 1 }, Order = 2 },
	BoostSuper = { Id = 0, Price = 49, Name = "Super Growth (5 min)", Icon = "💥", Grant = { Kind = "Boost", Id = "SuperGrowth", Count = 1 }, Order = 3 },
	BoostAutoTap = { Id = 0, Price = 25, Name = "Auto Tap (10 min)", Icon = "🤖", Grant = { Kind = "Boost", Id = "AutoTap", Count = 1 }, Order = 4 },
	CoinsSmall = { Id = 0, Price = 25, Name = "Pile of Coins", Icon = "🪙", Grant = { Kind = "Coins", Taps = 2500 }, Order = 5 },
	CoinsBig = { Id = 0, Price = 99, Name = "Chest of Coins", Icon = "💰", Grant = { Kind = "Coins", Taps = 15000 }, Order = 6 },
	GemsSmall = { Id = 0, Price = 25, Name = "100 Gems", Icon = "💎", Grant = { Kind = "Gems", Amount = 100 }, Order = 7 },
	GemsBig = { Id = 0, Price = 99, Name = "550 Gems", Icon = "💎", Grant = { Kind = "Gems", Amount = 550 }, Order = 8 },
	InstantRebirth = { Id = 0, Price = 49, Name = "+1 Instant Rebirth", Icon = "♻️", Grant = { Kind = "Rebirth" }, Order = 9 },
}
ShopConfig.ProductOrder = { "BoostHeight2x", "BoostHeight4x", "BoostSuper", "BoostAutoTap", "CoinsSmall", "CoinsBig", "GemsSmall", "GemsBig", "InstantRebirth" }

function ShopConfig.GemUpgradeCost(id: string, level: number): number?
	local def = ShopConfig.GemUpgrades[id]
	if not def or level >= def.MaxLevel then
		return nil
	end
	return math.floor(def.BaseCost * def.Growth ^ level)
end

return ShopConfig
