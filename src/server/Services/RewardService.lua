--[[
	RewardService
	Computes and grants level rewards. Server-only: time, deaths and results all come from
	the server's own run state, never from the client.

	Coins + XP for finishing, bonuses for: no deaths, under par time (Time Bonus),
	perfect (both), beating the Rival. Replays of completed levels pay Config.REPLAY_MULTIPLIER.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)

local RewardService = {}

function RewardService:Init(services)
	self.Services = services
end

local function countKeys(t): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Pure calculation (unit-testable): returns lines, coins, xp, flags
function RewardService.Calculate(input)
	--[[ input = { FirstClear, Deaths, Time, ParTime, HadRival, RivalFinished } ]]
	local multiplier = if input.FirstClear then 1 else Config.REPLAY_MULTIPLIER
	local lines = {}
	local coins, xp = 0, 0
	local function add(label: string, reward)
		local c = math.floor(reward.Coins * multiplier + 0.5)
		local x = math.floor(reward.XP * multiplier + 0.5)
		coins += c
		xp += x
		table.insert(lines, { Label = label, Coins = c, XP = x })
	end
	add(if input.FirstClear then "LEVEL COMPLETE" else "LEVEL REPLAY", Config.LEVEL_REWARD)
	local noDeath = input.Deaths == 0
	local underPar = input.Time <= input.ParTime
	if noDeath then
		add("NO DEATHS", Config.NO_DEATH_BONUS)
	end
	if underPar then
		add("TIME BONUS", Config.TIME_BONUS)
	end
	local perfect = noDeath and underPar
	if perfect then
		add("PERFECT", Config.PERFECT_BONUS)
	end
	local rivalResult = nil
	if input.HadRival then
		if input.RivalFinished then
			rivalResult = "Lost"
		else
			rivalResult = "Won"
			add("BEAT YOUR RIVAL", Config.RIVAL_WIN_BONUS)
		end
	end
	return {
		Lines = lines,
		Coins = coins,
		XP = xp,
		NoDeath = noDeath,
		UnderPar = underPar,
		Perfect = perfect,
		RivalResult = rivalResult,
	}
end

function RewardService:GrantFinish(run)
	local services = self.Services
	local player = run.Player
	local data = services.DataService:GetData(player)
	local key = Progression.LevelKey(run.LevelId)
	local time = run.FinishTime
	local firstClear = data == nil or not data.CompletedLevels[key]

	local calc = RewardService.Calculate({
		FirstClear = firstClear,
		Deaths = run.Deaths,
		Time = time,
		ParTime = run.Def.ParTime,
		HadRival = run.RoleHistory.Rival == true,
		RivalFinished = run.RivalFinished,
	})

	local previousBest = data and data.BestTimes[key]
	local newBest = previousBest == nil or time < previousBest
	local levelsGained = 0

	if data then
		services.DataService:Update(player, function(d)
			d.Coins += calc.Coins
			d.CompletedLevels[key] = true
			if newBest then
				d.BestTimes[key] = math.floor(time * 100) / 100
			end
			d.Stats.LevelsCompleted += 1
			d.Stats.UniqueLevelsCompleted = countKeys(d.CompletedLevels)
			if calc.NoDeath then
				d.Stats.NoDeathClears += 1
			end
			if calc.UnderPar then
				d.Stats.TimeBonuses += 1
			end
			if calc.RivalResult == "Won" then
				d.Stats.RivalWins += 1
			end
		end)
		levelsGained = services.DataService:AddXP(player, calc.XP)
		if newBest then
			services.LeaderboardService:Submit(player, run.LevelId, time)
		end
	end

	local global = services.LeaderboardService:GetBest(run.LevelId)
	return {
		LevelId = run.LevelId,
		Name = run.Def.Name,
		Time = time,
		ParTime = run.Def.ParTime,
		BestTime = if newBest then time else previousBest,
		NewBest = newBest,
		Deaths = run.Deaths,
		DoppelDeaths = run.DoppelDeaths,
		Lines = calc.Lines,
		Coins = calc.Coins,
		XP = calc.XP,
		Perfect = calc.Perfect,
		RivalResult = calc.RivalResult,
		LevelsGained = levelsGained,
		FirstClear = firstClear,
		GlobalBest = global,
		Mode = run.Mode,
		Betrayal = services.DuoService:GetBetrayalSummary(run, player),
	}
end

-- Duo partner (the human doppelgänger) rewards
function RewardService:GrantPartner(run)
	local services = self.Services
	local partner = run.Partner
	local data = services.DataService:GetData(partner)
	local key = Progression.LevelKey(run.LevelId)
	local firstClear = data == nil or not data.CompletedLevels[key]
	local multiplier = Config.DUO_PARTNER_MULTIPLIER * (if firstClear then 1 else Config.REPLAY_MULTIPLIER)
	local lines = {}
	local coins = math.floor(Config.LEVEL_REWARD.Coins * multiplier + 0.5)
	local xp = math.floor(Config.LEVEL_REWARD.XP * multiplier + 0.5)
	table.insert(lines, { Label = "DUO CLEAR", Coins = coins, XP = xp })

	local betrayal = services.DuoService:GetBetrayalSummary(run, partner)
	if betrayal and betrayal.IsTraitor and betrayal.Succeeded then
		local bonus = Config.BETRAYAL_TRAITOR_BONUS
		coins += bonus.Coins
		xp += bonus.XP
		table.insert(lines, { Label = "SECRET MISSION", Coins = bonus.Coins, XP = bonus.XP })
	end

	local levelsGained = 0
	if data then
		services.DataService:Update(partner, function(d)
			d.Coins += coins
			d.CompletedLevels[key] = true
			d.Stats.LevelsCompleted += 1
			d.Stats.UniqueLevelsCompleted = countKeys(d.CompletedLevels)
		end)
		levelsGained = services.DataService:AddXP(partner, xp)
	end
	return {
		LevelId = run.LevelId,
		Name = run.Def.Name,
		Time = run.FinishTime,
		ParTime = run.Def.ParTime,
		Deaths = run.PartnerDeaths,
		Lines = lines,
		Coins = coins,
		XP = xp,
		LevelsGained = levelsGained,
		IsPartner = true,
		Mode = run.Mode,
		Betrayal = betrayal,
	}
end

return RewardService
