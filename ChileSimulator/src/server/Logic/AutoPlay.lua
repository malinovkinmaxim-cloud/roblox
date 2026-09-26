--[[
	AutoPlay (logic) - ONE-BUTTON MODE.

	With Settings.OneButton on (the default) the whole game is played with a single button:
	the player only TAPS, and the server does the rest, every second:
	  * buys the best-value upgrade (TAP POWER / AUTO GROW) as soon as it is affordable
	  * spends gems on permanent upgrades
	  * claims the daily reward, playtime gifts and finished quests
	  * activates boosts from the inventory
	  * sets a quarter of the coin income aside for eggs and hatches the best egg it can save
	    up for in ~3 minutes (makes room by deleting the weakest unequipped pet); the best
	    pets are auto-equipped
	Rebirth is NOT automatic: the TAP button itself turns into "REBIRTH!" (client) and the
	next press rebirths - still one button, but the player chooses the big moment.

	Pure logic (no Roblox API), unit-tested in tests/run.luau. Everything goes through the
	same validated functions the manual UI uses, so one-button mode can never do anything a
	player could not do by hand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local ShopConfig = require(Shared.ShopConfig)
local BoostConfig = require(Shared.BoostConfig)
local RewardConfig = require(Shared.RewardConfig)
local PetConfig = require(Shared.PetConfig)

local Session = require(script.Parent.Session)
local Growth = require(script.Parent.Growth)
local Pets = require(script.Parent.Pets)
local Boosts = require(script.Parent.Boosts)
local Rewards = require(script.Parent.Rewards)

local AutoPlay = {}

AutoPlay.ASSUMED_TAPS_PER_SECOND = 5 -- to compare tap vs auto upgrades
AutoPlay.MAX_BUYS_PER_TICK = 6
AutoPlay.HATCH_INTERVAL = 6 -- seconds between auto hatches
-- share of every coin earned that is set aside for eggs; upgrades get the rest, so pets can
-- never starve the upgrades (and the other way round)
AutoPlay.EGG_SHARE = 0.25
AutoPlay.EGG_SAVE_SECONDS = 180 -- only save up for eggs that take at most this long
AutoPlay.GEM_ORDER = { "TapBonus", "CoinBonus", "AutoBonus", "Luck" }

function AutoPlay.Enabled(session): boolean
	return session.Data.Settings.OneButton == true
end

---------------------------------------------------------------------------
-- upgrades
---------------------------------------------------------------------------
-- Coins the autopilot may spend on upgrades (everything except the egg savings)
function AutoPlay.Spendable(session): number
	return math.max(0, session.Data.Coins - (session.EggBudget or 0))
end

-- The upgrade with the most extra growth per coin, or nil if nothing is affordable.
function AutoPlay.BestUpgrade(session): string?
	local data = session.Data
	local tps = AutoPlay.ASSUMED_TAPS_PER_SECOND
	local coins = AutoPlay.Spendable(session)
	local best, bestValue = nil, 0
	local tapCost = Formulas.TapCost(data.TapLevel)
	if tapCost and coins >= tapCost then
		local value = (Formulas.TapPower(data.TapLevel + 1) - Formulas.TapPower(data.TapLevel)) * tps / tapCost
		if value > bestValue then
			best, bestValue = "TapPower", value
		end
	end
	local autoCost = Formulas.AutoCost(data.AutoLevel)
	if autoCost and coins >= autoCost then
		local value = (Formulas.AutoRate(data.AutoLevel + 1) - Formulas.AutoRate(data.AutoLevel)) / autoCost
		if value > bestValue then
			best, bestValue = "AutoGrow", value
		end
	end
	return best
end

function AutoPlay.BuyUpgrades(session): number
	local bought = 0
	for _ = 1, AutoPlay.MAX_BUYS_PER_TICK do
		local kind = AutoPlay.BestUpgrade(session)
		if not kind or not Growth.BuyUpgrade(session, kind) then
			break
		end
		bought += 1
	end
	return bought
end

function AutoPlay.BuyGemUpgrades(session): number
	local data = session.Data
	local bought = 0
	for _ = 1, 3 do
		local choice, choiceCost = nil, math.huge
		local order = table.clone(AutoPlay.GEM_ORDER)
		if Pets.Count(session) >= Pets.Capacity(session) - 2 then
			table.insert(order, "Storage")
		end
		for _, id in order do
			local cost = ShopConfig.GemUpgradeCost(id, data.Gem[id])
			if cost and cost <= data.Gems and cost < choiceCost then
				choice, choiceCost = id, cost
			end
		end
		if not choice or not Growth.BuyGemUpgrade(session, choice) then
			break
		end
		bought += 1
	end
	return bought
end

---------------------------------------------------------------------------
-- rewards + boosts
---------------------------------------------------------------------------
local function announce(session, title: string, labels: { string }?)
	if labels and #labels > 0 then
		Session.Notify(session, "Reward", title .. "  " .. table.concat(labels, "  •  "), { Sound = "Reward" })
	end
end

function AutoPlay.ClaimRewards(session, world, rng, clock: number): number
	local claimed = 0
	if Rewards.DailyStatus(session, world.Now).CanClaim then
		local labels = Rewards.ClaimDaily(session, world, rng)
		if labels then
			claimed += 1
			announce(session, "📅 DAILY REWARD!", labels)
		end
	end
	local elapsed = Rewards.PlaytimeSeconds(session, clock)
	for i, gift in RewardConfig.Playtime do
		if not session.PlaytimeClaimed[i] and elapsed >= gift.Minutes * 60 then
			local labels = Rewards.ClaimPlaytime(session, i, clock, world, rng)
			if labels then
				claimed += 1
				announce(session, "🎁 FREE GIFT!", labels)
			end
		end
	end
	Rewards.EnsureQuestDay(session, world.Now)
	local quests = session.Data.Quests
	for _, quest in RewardConfig.Quests do
		if not quests.Claimed[quest.Id] and (quests.Progress[quest.Stat] or 0) >= quest.Goal then
			local labels = Rewards.ClaimQuest(session, quest.Id, world, rng)
			if labels then
				claimed += 1
				announce(session, "📜 QUEST DONE!", labels)
			end
		end
	end
	return claimed
end

-- Activates boosts from the inventory (one of each kind at a time, the rest waits)
function AutoPlay.UseBoosts(session): number
	local used = 0
	local data = session.Data
	for _, id in BoostConfig.Order do
		if (data.Boosts.Inventory[id] or 0) > 0 and not data.Boosts.Active[id] then
			if Boosts.Activate(session, id) then
				used += 1
			end
		end
	end
	return used
end

---------------------------------------------------------------------------
-- pets
---------------------------------------------------------------------------
-- Deletes the weakest unequipped Common/Rare pet to make room. Returns true if one was deleted.
function AutoPlay.MakeRoom(session): boolean
	local weakestUid, weakest = nil, math.huge
	for uid, pet in session.Data.Pets do
		local def = PetConfig.Pets[pet.Id]
		if not pet.E and def and PetConfig.Rarities[def.Rarity].Order <= PetConfig.Rarities.Rare.Order and def.Mult < weakest then
			weakestUid, weakest = uid, def.Mult
		end
	end
	if weakestUid then
		return (Pets.Delete(session, weakestUid))
	end
	return false
end

-- The best unlocked egg the egg savings can pay for within EGG_SAVE_SECONDS (at least the
-- cheapest one), so the autopilot neither spams cheap eggs forever nor saves for ages.
function AutoPlay.TargetEgg(session)
	local perSecond = (session.IncomeRate or 0) * AutoPlay.EGG_SHARE
	local reach = (session.EggBudget or 0) + perSecond * AutoPlay.EGG_SAVE_SECONDS
	local target = PetConfig.Eggs[1]
	for _, egg in PetConfig.Eggs do
		if Pets.EggUnlocked(session, egg) and egg.Cost <= reach then
			target = egg
		end
	end
	return target
end

-- Returns hatch results (for announcements) or nil
function AutoPlay.Hatch(session, rng, clock: number)
	if clock < (session.NextAutoHatch or 0) then
		return nil
	end
	session.NextAutoHatch = clock + AutoPlay.HATCH_INTERVAL
	local egg = AutoPlay.TargetEgg(session)
	if (session.EggBudget or 0) < egg.Cost or session.Data.Coins < egg.Cost then
		return nil
	end
	if Pets.Count(session) >= Pets.Capacity(session) and not AutoPlay.MakeRoom(session) then
		return nil
	end
	local results = Pets.Hatch(session, egg.Id, 1, rng)
	if results then
		session.EggBudget = math.max(0, (session.EggBudget or 0) - egg.Cost)
		Session.Effect(session, "Hatch", { Egg = egg.Id, Results = results, Fast = true, Auto = true })
		Rewards.CheckAchievements(session)
	end
	return results, egg
end

---------------------------------------------------------------------------
-- one server tick
---------------------------------------------------------------------------
function AutoPlay.Tick(session, world, rng, clock: number)
	if not AutoPlay.Enabled(session) then
		session.CoinsSeen = nil
		return nil
	end
	-- put EGG_SHARE of the coins earned since the last tick into the egg savings
	local data = session.Data
	local earned = if session.CoinsSeen then math.max(0, data.Coins - session.CoinsSeen) else 0
	session.EggBudget = (session.EggBudget or 0) + earned * AutoPlay.EGG_SHARE
	-- smoothed coins per second (this runs once per second)
	session.IncomeRate = (session.IncomeRate or earned) * 0.95 + earned * 0.05
	session.EggBudget = math.min(session.EggBudget or 0, data.Coins)
	AutoPlay.BuyUpgrades(session)
	AutoPlay.BuyGemUpgrades(session)
	AutoPlay.ClaimRewards(session, world, rng, clock)
	AutoPlay.UseBoosts(session)
	local results, egg = AutoPlay.Hatch(session, rng, clock)
	session.CoinsSeen = data.Coins
	return results, egg
end

return AutoPlay
