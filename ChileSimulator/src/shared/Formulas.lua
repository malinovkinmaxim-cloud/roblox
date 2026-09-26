--[[
	Formulas - every gameplay number is computed here (pure functions, no Roblox API).

	The SERVER uses these for the real values. The CLIENT uses them only to display prices and
	predict "+X" popups; it never decides anything.
	All results are sanitized (no NaN / inf).
]]

local Config = require(script.Parent.Config)
local ZoneConfig = require(script.Parent.ZoneConfig)
local ShopConfig = require(script.Parent.ShopConfig)
local Num = require(script.Parent.Util.Num)

local Formulas = {}

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------
local STEPS_125 = { 1, 2.5, 5 }

-- Tap power by level: x1, x2, x5, x10, x25, x50, x100, x250, x500, x1K, ...
function Formulas.TapPower(level: number): number
	level = math.max(1, math.floor(Num.Sanitize(level, 1)))
	if level == 1 then
		return 1
	elseif level == 2 then
		return 2
	elseif level == 3 then
		return 5
	end
	local k = (level - 4) // 3 + 1
	local r = (level - 4) % 3
	return Num.Sanitize(STEPS_125[r + 1] * 10 ^ k)
end

-- Price of step n of a "flattening geometric" curve: base * r(0) * r(1) * ... * r(n-1)
-- with r(i) = max(RatioMin, RatioStart - RatioDecay * i). Steep early, steady later.
local costCache: { [any]: { [number]: number } } = {}

local function flatteningCost(def, n: number): number
	local cache = costCache[def]
	if not cache then
		cache = {}
		costCache[def] = cache
	end
	local cached = cache[n]
	if cached then
		return cached
	end
	local cost = def.BaseCost
	for i = 0, n - 1 do
		cost = Num.Sanitize(cost * math.max(def.RatioMin, def.RatioStart - def.RatioDecay * i))
		if cost >= Num.MAX then
			break
		end
	end
	cost = Num.Sanitize(math.floor(cost))
	if n <= 100000 then
		cache[n] = cost
	end
	return cost
end

-- Coins needed to go from `level` to level+1 (nil = maxed)
function Formulas.TapCost(level: number): number?
	local def = Config.Upgrades.TapPower
	if level >= def.MaxLevel then
		return nil
	end
	return flatteningCost(def, math.max(0, level - 1))
end

-- Auto growth in cm/second (before multipliers): 0, 1, 2, 5, 10, 25, 50, 100, 250 ...
-- Same shape as tap power so neither upgrade can snowball past the other.
function Formulas.AutoRate(level: number): number
	level = math.max(0, math.floor(Num.Sanitize(level, 0)))
	if level == 0 then
		return 0
	end
	return Formulas.TapPower(level)
end

function Formulas.AutoCost(level: number): number?
	local def = Config.Upgrades.AutoGrow
	if level >= def.MaxLevel then
		return nil
	end
	return flatteningCost(def, math.max(0, level))
end

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------
-- Height (cm) needed for the next rebirth when you already have `rebirths`.
-- Each rebirth costs RatioStart - RatioDecay * i times more than the previous one (never
-- below RatioMin): steep at first so zones don't fly by, steady rhythm in the long run.
function Formulas.RebirthCost(rebirths: number): number
	return flatteningCost(Config.Rebirth, math.max(0, math.floor(Num.Sanitize(rebirths, 0))))
end

-- only needed when Config is changed at runtime (balance tests)
function Formulas.ClearCache()
	table.clear(costCache)
end

-- Growth multiplier from rebirths: R0 x1, R1 x2, R2 x3, R3 x5, R10 x21, R100 x1101
function Formulas.RebirthMultiplier(rebirths: number): number
	rebirths = math.max(0, math.floor(Num.Sanitize(rebirths, 0)))
	return Num.Sanitize(math.max(1, math.floor(1 + rebirths + Config.Rebirth.Quadratic * rebirths * rebirths + 0.5)))
end

-- Gems for reaching rebirth number `newRebirths`
function Formulas.RebirthGems(newRebirths: number): number
	local def = Config.Rebirth
	return math.min(def.GemsMax, def.GemsBase + def.GemsPerRebirth * math.max(1, newRebirths))
end

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------
-- Equipped pets stack additively: 1 + sum(m - 1)
function Formulas.PetMultiplier(mults: { number }): number
	local total = 1
	for _, m in mults do
		total += math.max(0, Num.Sanitize(m, 1) - 1)
	end
	return Num.Sanitize(total, 1)
end

---------------------------------------------------------------------------
-- Multipliers
---------------------------------------------------------------------------
export type MultState = {
	Rebirths: number,
	ZoneIndex: number,
	PetMult: number,
	BoostHeight: number,
	BoostCoins: number,
	EventHeight: number,
	EventCoins: number,
	Passes: { [string]: boolean },
	Gem: { [string]: number },
	VIPArea: boolean?, -- standing in the VIP lounge
}

export type Multipliers = {
	TapHeight: number, -- multiplier on tap growth
	AutoHeight: number, -- multiplier on auto growth
	TapCoinGrowth: number, -- the part of TapHeight that also counts for coins (see TapCoins)
	AutoCoinGrowth: number,
	Coins: number, -- multiplier on coins
	Rebirth: number,
	Zone: number,
	Pet: number,
}

local function gemBonus(state: MultState, id: string): number
	local def = ShopConfig.GemUpgrades[id]
	local level = (state.Gem and state.Gem[id]) or 0
	return 1 + def.Per * level
end

function Formulas.Multipliers(state: MultState): Multipliers
	local passes = state.Passes or {}
	local rebirth = Formulas.RebirthMultiplier(state.Rebirths or 0)
	local zoneDef = ZoneConfig.Zones[state.ZoneIndex or 1] or ZoneConfig.Zones[1]
	local zone = zoneDef.Multiplier
	local pet = Num.Sanitize(state.PetMult or 1, 1)
	local vip = if passes.VIP then ShopConfig.VIPMultiplier else 1

	-- "extra" growth: pets, boosts, events, passes. It multiplies growth fully but counts for
	-- coins only as extra ^ Coins.ExtraShare - otherwise every extra would also buy upgrades
	-- faster and snowball (a x15 pet team would end up as x10,000,000 an hour later).
	local extra = Num.Product({
		pet,
		state.BoostHeight or 1,
		state.EventHeight or 1,
		if passes.Growth2x then 2 else 1,
		vip,
		if state.VIPArea then ShopConfig.VIPAreaBonus else 1,
	})
	local tapCore = Num.Product({ zone, rebirth, gemBonus(state, "TapBonus") })
	local autoCore = Num.Product({ zone, rebirth, gemBonus(state, "AutoBonus") })
	local extraForCoins = Num.Sanitize(extra ^ Config.Coins.ExtraShare, 1)

	-- coin-only multipliers; growth multipliers reach coins through the tap gain (see TapCoins)
	local coins = Num.Product({
		state.BoostCoins or 1,
		state.EventCoins or 1,
		if passes.Coins2x then 2 else 1,
		vip,
		gemBonus(state, "CoinBonus"),
	})

	return {
		TapHeight = Num.Mul(tapCore, extra),
		AutoHeight = Num.Mul(autoCore, extra),
		TapCoinGrowth = Num.Mul(tapCore, extraForCoins),
		AutoCoinGrowth = Num.Mul(autoCore, extraForCoins),
		Coins = coins,
		Rebirth = rebirth,
		Zone = zone,
		Pet = pet,
	}
end

-- Taller = richer
function Formulas.HeightCoinBonus(heightCm: number): number
	local meters = Num.NonNeg(heightCm) / 100
	return 1 + Config.Coins.HeightBonusPerDecade * math.log10(1 + meters)
end

-- Growth (cm) of ONE tap
function Formulas.TapGain(tapLevel: number, mults: Multipliers): number
	return Num.Mul(Formulas.TapPower(tapLevel), mults.TapHeight)
end

-- Coins of ONE tap: grow more -> earn more, but sub-linearly (gain ^ Exponent), so upgrades
-- and rebirths can't snowball the economy. Coin-only multipliers apply on top.
function Formulas.CoinsFromGain(gain: number, mults: Multipliers, heightCm: number): number
	local cfg = Config.Coins
	return Num.Product({
		cfg.PerTapBase,
		Num.NonNeg(gain) ^ cfg.GainExponent,
		mults.Coins,
		Formulas.HeightCoinBonus(heightCm),
	})
end

function Formulas.TapCoins(tapLevel: number, mults: Multipliers, heightCm: number): number
	return Formulas.CoinsFromGain(Num.Mul(Formulas.TapPower(tapLevel), mults.TapCoinGrowth), mults, heightCm)
end

-- Auto growth (cm) per second
function Formulas.AutoGain(autoLevel: number, mults: Multipliers): number
	return Num.Mul(Formulas.AutoRate(autoLevel), mults.AutoHeight)
end

-- Auto coins per second (a fraction of what the same growth would pay when tapped)
function Formulas.AutoCoins(autoLevel: number, mults: Multipliers, heightCm: number): number
	local gain = Num.Mul(Formulas.AutoRate(autoLevel), mults.AutoCoinGrowth)
	if gain <= 0 then
		return 0
	end
	return Num.Mul(Formulas.CoinsFromGain(gain, mults, heightCm), Config.Coins.AutoCoinFactor)
end

-- Coins worth `taps` of the player's own taps (used to scale coin rewards to progress).
-- Uses the tap coins WITHOUT temporary boosts/events so rewards can't be farmed with boosts.
function Formulas.CoinsForTaps(taps: number, tapLevel: number, baseMults: Multipliers, heightCm: number): number
	return Num.Mul(taps, math.max(1, Formulas.TapCoins(tapLevel, baseMults, heightCm)))
end

---------------------------------------------------------------------------
-- Titles, milestones
---------------------------------------------------------------------------
function Formulas.Title(heightCm: number)
	local meters = Num.NonNeg(heightCm) / 100
	local result = Config.Titles[1]
	for _, t in Config.Titles do
		if meters >= t.Min then
			result = t
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Leaderboard encoding (OrderedDataStore only stores integers)
---------------------------------------------------------------------------
local ODS_SCALE = 1e9

function Formulas.EncodeHeight(cm: number): number
	cm = Num.NonNeg(cm)
	if cm < 1 then
		return 0
	end
	return math.floor(math.log10(cm) * ODS_SCALE)
end

function Formulas.DecodeHeight(value: number): number
	value = Num.NonNeg(value)
	return Num.Sanitize(10 ^ (value / ODS_SCALE))
end

-- Global height histogram bucket: four buckets per decade of centimetres (0..1200)
Formulas.BUCKETS_PER_DECADE = 4

function Formulas.HeightBucket(cm: number): number
	cm = Num.NonNeg(cm)
	if cm < 1 then
		return 0
	end
	return math.clamp(math.floor(math.log10(cm) * Formulas.BUCKETS_PER_DECADE + 1e-9), 0, 1200)
end

return Formulas
