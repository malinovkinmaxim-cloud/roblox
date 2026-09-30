--[[
	LootData - where ITEMS come from and how rare they are, and the CHIPS economy.

	Every source rolls items (shared/ItemData.lua) on its own rarity table: an elite drops an
	item now and then (mostly common), boss 1 always drops one (mostly rare), and every later
	boss drops rarer ones. Luck pushes the weights up the ladder (Rarity.LuckScale).
	  Owned   chance that the roll upgrades an item you already carry instead of a new one
	          ("find it again": level II, III)
	Unlocked premium items and boss relics join the pool; a boss relic only drops from its own
	boss (always, once it is unlocked). THE FINAL ONE drops its 67 FRAGMENT in the arena when
	it changes phase (if unlocked).

	Items are rare on purpose: a full run finds about 8 (4 bosses, 1-2 elites, 1-2 vaults).
	Level ups are the frequent choices; items are the special ones.

	CHIPS: the currency of item unlocks (not Robux, not coins). Earned in runs only:
	about 100 for a good full run (HUNT), scaled by the difficulty's Reward.
]]

local LootData = {}

LootData.Sources = {
	Elite = { Chance = 0.15, Count = 1, Owned = 0.3, Weights = { Common = 70, Rare = 27, Epic = 3, Legendary = 0 } },
	Vault = { Chance = 1, Count = 1, Owned = 0.4, Weights = { Common = 45, Rare = 40, Epic = 13, Legendary = 2 } },
	Boss1 = { Chance = 1, Count = 1, Owned = 0.35, Weights = { Common = 15, Rare = 55, Epic = 25, Legendary = 5 } },
	Boss2 = { Chance = 1, Count = 1, Owned = 0.35, Weights = { Common = 0, Rare = 35, Epic = 50, Legendary = 15 } },
	Boss3 = { Chance = 1, Count = 1, Owned = 0.4, Weights = { Common = 0, Rare = 15, Epic = 50, Legendary = 35 } },
	Boss4 = { Chance = 1, Count = 2, Owned = 0.4, Weights = { Common = 0, Rare = 5, Epic = 45, Legendary = 50 } },
	Secret = { Chance = 1, Count = 1, Owned = 0, Weights = { Common = 0, Rare = 0, Epic = 60, Legendary = 40 } }, -- the crack in the Rift
}

LootData.MaxedCoins = 25 -- a maxed item picked up again
LootData.MaxOnGround = 12 -- items lying on the map at once (the oldest one goes)
LootData.PickupRadius = 4 -- walk this close to take an item (items are not magnetized: go get them)

-- CHIPS earned in one run (before the difficulty's Reward multiplier)
LootData.Chips = {
	PerMinute = 2, -- 15 minutes: 30
	Bosses = { 8, 12, 16, 20 }, -- boss 1..4 defeated: 56
	Main = 30, -- THE FINAL ONE
	Elite = 1, -- per elite, up to EliteMax
	EliteMax = 10,
	MinTime = 60, -- runs shorter than this pay nothing
}

-- the unlock prices by class (shared/ItemData.lua Price is the source of truth; this is the
-- design range, checked by the tests)
LootData.PriceRange = {
	Rare = { 300, 500 },
	Epic = { 700, 1000 },
	Legendary = { 1500, 2500 },
	BossRelic = { 2000, 3500 },
	ExtremelyRare = { 4000, 99999 },
}

function LootData.Source(name: string)
	local s = LootData.Sources[name]
	assert(s, "unknown loot source " .. tostring(name))
	return s
end

-- chips for a finished run (summary numbers from Run:Summary)
function LootData.ChipsFor(time: number, bossSlots: { number }, main: boolean, elites: number, reward: number): number
	local c = LootData.Chips
	if time < c.MinTime then
		return 0
	end
	local chips = math.floor(time / 60) * c.PerMinute
	for _, slot in bossSlots do
		chips += c.Bosses[slot] or 0
	end
	if main then
		chips += c.Main
	end
	chips += math.min(elites, c.EliteMax) * c.Elite
	return math.max(0, math.floor(chips * (reward or 1) + 0.5))
end

return LootData
