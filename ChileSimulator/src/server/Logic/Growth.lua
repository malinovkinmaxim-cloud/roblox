--[[
	Growth (logic) - THE core loop on the server: tap -> height + coins, auto growth,
	upgrades, rebirth. Everything the client sends is validated here.

	Anti-cheat for taps: a token bucket per player (Config.Tap). Each accepted tap costs one
	token; tokens refill at MaxPerSecond up to Burst. A client that sends 1,000,000 taps (or
	a tap count of 1e9) gets at most Burst taps once and MaxPerSecond per second after that.
	The client never sends an amount of height - only "I tapped N times" (N <= MaxBatch).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ZoneConfig = require(Shared.ZoneConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Num = require(Shared.Util.Num)
local ShopConfig = require(Shared.ShopConfig)

local Session = require(script.Parent.Session)
local Mults = require(script.Parent.Mults)
local Rewards = require(script.Parent.Rewards)
local Boosts = require(script.Parent.Boosts)

local Growth = {}

---------------------------------------------------------------------------
-- Tap rate limiting
---------------------------------------------------------------------------
function Growth.Refill(session, clock: number)
	local cfg = Config.Tap
	local dt = math.max(0, clock - session.LastRefill)
	session.LastRefill = clock
	session.Tokens = math.min(cfg.Burst, session.Tokens + dt * cfg.MaxPerSecond)
end

-- Takes up to `wanted` tokens, returns how many were granted
function Growth.TakeTokens(session, wanted: number, clock: number): number
	Growth.Refill(session, clock)
	local granted = math.clamp(math.floor(math.min(wanted, session.Tokens)), 0, wanted)
	session.Tokens -= granted
	return granted
end

-- Validates the raw remote argument. Returns an integer 1..MaxBatch or nil.
function Growth.ValidateTapCount(count: any): number?
	-- anything above MaxBatch is clamped (a laggy client may batch a few more), junk is rejected
	local valid = Num.ValidInt(count, 1, Num.MAX)
	if not valid then
		return nil
	end
	return math.min(valid, Config.Tap.MaxBatch)
end

---------------------------------------------------------------------------
-- Height changes
---------------------------------------------------------------------------
-- Adds height (cm) and handles everything that depends on height going up.
function Growth.AddHeight(session, gain: number, world)
	gain = Num.NonNeg(gain)
	if gain <= 0 then
		return
	end
	local data = session.Data
	local oldBest = data.BestHeight
	data.Height = Num.Add(data.Height, gain)

	if data.Height > oldBest then
		if session.RecordArmed then
			session.RecordArmed = false
			Session.Notify(session, "Big", "🚨 NEW HEIGHT RECORD!", { Sound = "BigGrowth" })
		end
		local oldZone = ZoneConfig.HighestUnlocked(oldBest)
		data.BestHeight = data.Height
		local newZone = ZoneConfig.HighestUnlocked(data.BestHeight)
		if newZone > oldZone then
			for z = oldZone + 1, newZone do
				local zone = ZoneConfig.Zones[z]
				Session.Notify(session, "Big", "🌍 NEW WORLD UNLOCKED: " .. string.upper(zone.Name) .. "!", { Sound = "NewZone" })
				Session.Effect(session, "ZoneUnlocked", { Zone = z })
			end
			Session.MarkDirty(session, "Zones")
		end
	end

	Rewards.AddQuestProgress(session, "Grown", gain, world.Now)
	Rewards.CheckMilestones(session)
	session.AttrDirty = true
	Session.MarkDirty(session, "Stats")
end

-- Applies `taps` real taps (already rate-limited). Returns height gained, coins gained.
function Growth.ApplyTaps(session, taps: number, world): (number, number)
	if taps <= 0 then
		return 0, 0
	end
	local data = session.Data
	-- DOUBLE TAP event: every tap counts as two
	local tapCount = taps * (world.Event and world.Event.TapCount or 1)
	local m = Mults.Get(session, world)
	local gain = Num.Mul(Formulas.TapGain(data.TapLevel, m), tapCount)
	local coins = Num.Mul(Formulas.TapCoins(data.TapLevel, m, data.Height), tapCount)

	data.Taps = Num.Add(data.Taps, tapCount)
	data.Coins = Num.Add(data.Coins, coins)
	if world.Event then
		session.EventTapped = true
	end
	Rewards.AddQuestProgress(session, "Taps", tapCount, world.Now)
	Growth.AddHeight(session, gain, world)
	return gain, coins
end

-- Remote entry point: raw count from the client. Returns accepted taps, gain, coins.
function Growth.Tap(session, rawCount: any, world, clock: number): (number, number, number)
	local count = Growth.ValidateTapCount(rawCount)
	if not count then
		session.Flags.BadTap = (session.Flags.BadTap or 0) + 1
		return 0, 0, 0
	end
	local accepted = Growth.TakeTokens(session, count, clock)
	if accepted < count then
		session.Flags.Throttled = (session.Flags.Throttled or 0) + (count - accepted)
	end
	local gain, coins = Growth.ApplyTaps(session, accepted, world)
	if accepted > 0 then
		Rewards.CheckAchievements(session)
	end
	return accepted, gain, coins
end

---------------------------------------------------------------------------
-- Passive: auto growth + auto tap (called by the server tick, dt seconds)
---------------------------------------------------------------------------
function Growth.HasAutoTap(session): boolean
	local _, _, boostAutoTap = Boosts.Multipliers(session)
	return boostAutoTap or (session.Passes.AutoTap == true and session.Data.Settings.AutoTap)
end

function Growth.Tick(session, dt: number, world, clock: number): (number, number)
	local data = session.Data
	local m = Mults.Get(session, world)
	local gain = Num.Mul(Formulas.AutoGain(data.AutoLevel, m), dt)
	local coins = Num.Mul(Formulas.AutoCoins(data.AutoLevel, m, data.Height), dt)
	data.Coins = Num.Add(data.Coins, coins)
	Growth.AddHeight(session, gain, world)

	-- Auto Tap shares the tap token bucket, so auto + manual can never exceed the tap limit
	local autoTapGain, autoTapCoins = 0, 0
	if Growth.HasAutoTap(session) then
		local wanted = math.floor(Config.Tap.AutoTapRate * dt + 0.5)
		local accepted = Growth.TakeTokens(session, wanted, clock)
		autoTapGain, autoTapCoins = Growth.ApplyTaps(session, accepted, world)
	end
	Rewards.CheckAchievements(session)
	return gain + autoTapGain, coins + autoTapCoins
end

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------
function Growth.BuyUpgrade(session, kind: any): (boolean, string?)
	local data = session.Data
	local cost, field
	if kind == "TapPower" then
		cost, field = Formulas.TapCost(data.TapLevel), "TapLevel"
	elseif kind == "AutoGrow" then
		cost, field = Formulas.AutoCost(data.AutoLevel), "AutoLevel"
	else
		return false, "Unknown upgrade"
	end
	if not cost then
		return false, "MAX LEVEL"
	end
	if data.Coins < cost then
		return false, "Not enough coins"
	end
	data.Coins -= cost
	data[field] += 1
	if data.Tutorial < 2 then
		data.Tutorial = 2
	end
	Session.MarkDirty(session, "Stats", "Rates")
	Session.Effect(session, "Upgrade", { Kind = kind, Level = data[field] })
	return true
end

function Growth.BuyGemUpgrade(session, id: any): (boolean, string?)
	if type(id) ~= "string" or not ShopConfig.GemUpgrades[id] then
		return false, "Unknown upgrade"
	end
	local data = session.Data
	local level = data.Gem[id]
	local cost = ShopConfig.GemUpgradeCost(id, level)
	if not cost then
		return false, "MAX LEVEL"
	end
	if data.Gems < cost then
		return false, "Not enough gems"
	end
	data.Gems -= cost
	data.Gem[id] = level + 1
	session.PetMultCache = nil
	Session.MarkDirty(session, "Stats", "Rates", "Pets")
	Session.Effect(session, "Upgrade", { Kind = id, Level = level + 1 })
	return true
end

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------
function Growth.CanRebirth(session): boolean
	return session.Data.Height >= Formulas.RebirthCost(session.Data.Rebirths)
end

-- free = true for the "+1 Instant Rebirth" developer product (skips the height check)
function Growth.Rebirth(session, world, free: boolean?): (boolean, string?)
	local data = session.Data
	local cost = Formulas.RebirthCost(data.Rebirths)
	if not free and data.Height < cost then
		return false, "Reach " .. Format.Length(cost) .. " to rebirth"
	end
	local oldHeight = data.Height
	local oldMult = Formulas.RebirthMultiplier(data.Rebirths)
	data.Rebirths += 1
	local newMult = Formulas.RebirthMultiplier(data.Rebirths)
	local gems = Formulas.RebirthGems(data.Rebirths)
	data.Gems = Num.Add(data.Gems, gems)
	data.Height = Config.START_HEIGHT
	session.RecordArmed = data.BestHeight > data.Height
	if data.Tutorial < 3 then
		data.Tutorial = 3
	end

	Rewards.AddQuestProgress(session, "Rebirths", 1, world.Now)
	Rewards.CheckAchievements(session)
	session.AttrDirty = true
	Session.MarkDirty(session, "Stats", "Rates")
	Session.Effect(session, "Rebirth", {
		Broadcast = true,
		UserId = session.UserId,
		Rebirths = data.Rebirths,
		OldHeight = oldHeight,
		OldMult = oldMult,
		NewMult = newMult,
		Gems = gems,
	})
	return true
end

return Growth
