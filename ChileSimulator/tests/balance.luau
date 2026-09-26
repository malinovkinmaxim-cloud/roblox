--[[
	Balance simulation (run from ChileSimulator/):  lune run tests/balance.luau [tapsPerSecond] [minutes]

	A simulated player taps constantly, greedily buys the upgrade with the best value, stands
	in the best unlocked zone, spends gems on Tap Power and rebirths as soon as possible.
	No pets / boosts / events / gamepasses: this is the baseline free-to-play pace.
	Prints a timeline so the first minutes can be tuned (see README "Balance").
]]

local process = require("@lune/process")
local H = require("./harness")

local Formulas = H.Require("ReplicatedStorage.Shared.Formulas")
local Format = H.Require("ReplicatedStorage.Shared.Util.Format")
local Config = H.Require("ReplicatedStorage.Shared.Config")
local ZoneConfig = H.Require("ReplicatedStorage.Shared.ZoneConfig")
local ShopConfig = H.Require("ReplicatedStorage.Shared.ShopConfig")

local TPS = tonumber(process.args[1]) or 6
local MINUTES = tonumber(process.args[2]) or 240
local QUIET = process.args[3] == "quiet" or _G.BALANCE_QUIET == true

local Sim = {}

function Sim.Run(tps: number, minutes: number, log: boolean)
	local s = {
		Height = Config.START_HEIGHT,
		Best = Config.START_HEIGHT,
		Coins = 0,
		Gems = 0,
		Rebirths = 0,
		TapLevel = 1,
		AutoLevel = 0,
		Gem = { TapBonus = 0, AutoBonus = 0, CoinBonus = 0 },
	}
	local events = {}
	local function note(t, text)
		table.insert(events, { T = t, Text = text })
		if log then
			print(string.format("  %6s  %s", Format.Time(t), text))
		end
	end

	local zoneSeen = 1
	local checkpoints = { 0.5, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480 }
	local nextCheck = 1
	local firstRebirth, firstUpgrade
	local reach = {}
	local rebirthAt = {}
	local thresholds = { 10, 100, 1e3, 1e4, 1e6, 1e9, 1e12, 1e15 }

	for t = 1, minutes * 60 do
		local zone = ZoneConfig.HighestUnlocked(s.Best)
		if zone > zoneSeen then
			zoneSeen = zone
			note(t, "zone unlocked: " .. ZoneConfig.Zones[zone].Name)
		end
		local mults = Formulas.Multipliers({
			Rebirths = s.Rebirths,
			ZoneIndex = zone,
			PetMult = 1,
			BoostHeight = 1,
			BoostCoins = 1,
			EventHeight = 1,
			EventCoins = 1,
			Passes = {},
			Gem = s.Gem,
		})
		local gain = Formulas.TapGain(s.TapLevel, mults) * tps + Formulas.AutoGain(s.AutoLevel, mults)
		local coins = Formulas.TapCoins(s.TapLevel, mults, s.Height) * tps + Formulas.AutoCoins(s.AutoLevel, mults, s.Height)
		s.Height += gain
		s.Coins += coins
		s.Best = math.max(s.Best, s.Height)
		for _, m in thresholds do
			if not reach[m] and s.Best >= m * 100 then
				reach[m] = t
			end
		end

		-- buy upgrades greedily (best growth per coin)
		local bought = true
		while bought do
			bought = false
			local tapCost = Formulas.TapCost(s.TapLevel)
			local autoCost = Formulas.AutoCost(s.AutoLevel)
			local tapValue = tapCost and (Formulas.TapPower(s.TapLevel + 1) - Formulas.TapPower(s.TapLevel)) * tps / tapCost or 0
			local autoValue = autoCost and (Formulas.AutoRate(s.AutoLevel + 1) - Formulas.AutoRate(s.AutoLevel)) / autoCost or 0
			if tapValue >= autoValue and tapCost and s.Coins >= tapCost then
				s.Coins -= tapCost
				s.TapLevel += 1
				bought = true
				if not firstUpgrade then
					firstUpgrade = t
				end
				note(t, string.format("TAP POWER -> %s (cost %s)", Format.Mult(Formulas.TapPower(s.TapLevel)), Format.Number(tapCost)))
			elseif autoCost and s.Coins >= autoCost and autoValue > 0 then
				s.Coins -= autoCost
				s.AutoLevel += 1
				bought = true
				note(t, string.format("AUTO GROW -> %s/s (cost %s)", Format.Gain(Formulas.AutoRate(s.AutoLevel)), Format.Number(autoCost)))
			end
		end

		-- gems -> tap bonus
		local gemCost = ShopConfig.GemUpgradeCost("TapBonus", s.Gem.TapBonus)
		while gemCost and s.Gems >= gemCost do
			s.Gems -= gemCost
			s.Gem.TapBonus += 1
			gemCost = ShopConfig.GemUpgradeCost("TapBonus", s.Gem.TapBonus)
		end

		-- rebirth asap
		local cost = Formulas.RebirthCost(s.Rebirths)
		if s.Height >= cost then
			s.Rebirths += 1
			s.Gems += Formulas.RebirthGems(s.Rebirths)
			s.Height = Config.START_HEIGHT
			if not firstRebirth then
				firstRebirth = t
			end
			note(t, string.format("REBIRTH %d  (x%s growth, next at %s)", s.Rebirths, Format.Number(Formulas.RebirthMultiplier(s.Rebirths)), Format.Length(Formulas.RebirthCost(s.Rebirths))))
		end

		if t % 600 == 0 then
			rebirthAt[t // 60] = s.Rebirths
		end
		while checkpoints[nextCheck] and t >= checkpoints[nextCheck] * 60 do
			if log then
				print(string.format(
					"  ==== %5s min: height %s | best %s | coins %s | tap %s | auto %s/s | R%d",
					tostring(checkpoints[nextCheck]),
					Format.Length(s.Height),
					Format.Length(s.Best),
					Format.Number(s.Coins),
					Format.Mult(Formulas.TapPower(s.TapLevel)),
					Format.Gain(Formulas.AutoRate(s.AutoLevel)),
					s.Rebirths
				))
			end
			nextCheck += 1
		end
	end
	return {
		State = s,
		FirstRebirth = firstRebirth,
		FirstUpgrade = firstUpgrade,
		Reach = reach,
		RebirthAt = rebirthAt,
		Thresholds = thresholds,
		Events = events,
	}
end

if not QUIET then
	print(string.format("Balance sim: %d taps/s for %d minutes", TPS, MINUTES))
	local result = Sim.Run(TPS, MINUTES, true)
	print(string.format("\nfirst upgrade at %ss, first rebirth at %s", tostring(result.FirstUpgrade), Format.Time(result.FirstRebirth or -1)))
end

return Sim
