--[[
	AdminManager - debug commands for testing in Studio (or for GameConfig.AdminUserIds / the
	place owner). Use the DEBUG panel in the lobby / run HUD, or chat: "/time 300", "/boss TheFinalOne"...

	  time <sec>      jump the run timeline         level <n>    +n levels
	  boss <key>      spawn a boss                  event <key>  start a random event
	  weapon <key>    give a weapon                 max          max every weapon
	  god             toggle invulnerability        killall      kill every enemy
	  die             lose all HP                   coins <n>    +n coins
	  fragments <n>   +n fragments                  afk <min>    the AFK camp rested n minutes
	  evolve          max abilities + their evolution passives
	  miniboss <key>  a mini-boss comes out now     relic <key>  a relic at your feet
	  vault           a 67 VAULT wakes up           rush         a 67 RUSH starts
	  unlockall       unlock everything             reset        wipe your profile (Studio)
	  stats           server performance numbers
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local EnemyData = require(Shared.EnemyData)
local WeaponData = require(Shared.WeaponData)
local HeroData = require(Shared.HeroData)
local UpgradeData = require(Shared.UpgradeData)
local MetaData = require(Shared.MetaData)
local WaveData = require(Shared.WaveData)

local Guard = require(script.Parent.Parent.Util.Guard)
local Defaults = require(script.Parent.Parent.Data.Defaults)
local Sim = script.Parent.Parent.Sim
local EnemyManager = require(Sim.EnemyManager)
local WaveManager = require(Sim.WaveManager)
local ArenaDirector = require(Sim.ArenaDirector)
local Relics = require(Sim.Relics)
local MiniBossData = require(Shared.MiniBossData)
local RelicData = require(Shared.RelicData)

local AdminManager = {}

function AdminManager:Init(services)
	self.Services = services
end

function AdminManager:Run(player: Player, command: string, arg: string?)
	local PM = self.Services.PlayerManager
	if not PM:IsAdmin(player) then
		return
	end
	local session = PM:Get(player)
	if not session then
		return
	end
	local run = self.Services.GameManager:GetRun(player)
	local n = tonumber(arg)
	local function say(text: string)
		PM:Notify(player, "[debug] " .. text, "Info")
	end
	command = string.lower(command)

	if command == "coins" then
		self.Services.RewardManager:GiveCoins(session, n or 1000)
		PM:Sync(player)
		say("coins added")
	elseif command == "fragments" then
		self.Services.RewardManager:GiveFragments(session, n or 100)
		PM:Sync(player)
		say("fragments added")
	elseif command == "afk" then
		local afk = session.Data.Afk
		afk.Since = math.max(1, (if afk.Since > 0 then afk.Since else os.time()) - (n or 60) * 60)
		PM:Sync(player)
		say("AFK camp +" .. (n or 60) .. " minutes")
	elseif command == "unlockall" then
		for _, def in WeaponData.List do
			if def.Evolution == nil then
				session.Data.Weapons[def.Key] = true
			end
		end
		for _, def in UpgradeData.Passives do
			if def.Secret then
				session.Data.Weapons[def.Key] = true
			end
		end
		for _, def in HeroData.List do
			session.Data.Heroes[def.Key] = true
		end
		self.Services.RewardManager:CheckAchievements(session)
		PM:Sync(player)
		say("everything unlocked")
	elseif command == "maxmeta" then
		for _, def in MetaData.Upgrades do
			session.Data.Meta[def.Key] = def.MaxLevel
		end
		PM:Sync(player)
		say("permanent upgrades maxed")
	elseif command == "reset" and RunService:IsStudio() then
		session.Data = Defaults.New()
		self.Services.PlayerManager:RollQuests(session)
		self.Services.PlayerManager:RollWeekly(session)
		PM:Sync(player)
		say("profile reset")
	elseif command == "stats" then
		local gm = self.Services.GameManager
		say(string.format("runs %d, steps %d, frames %d, avg frame %d bytes", gm:ActiveRuns(), gm.Stats.Steps, gm.Stats.Frames, gm.Stats.Bytes // math.max(1, gm.Stats.Frames)))
	elseif not run then
		say("start a run first")
	elseif command == "time" and n then
		run.Time = math.max(0, n)
		say("time -> " .. n)
	elseif command == "level" then
		for _ = 1, math.clamp(n or 1, 1, 50) do
			run.Level += 1
			run.PendingLevels += 1
		end
	elseif command == "boss" then
		local key = if arg and EnemyData.ByKey[arg] then arg else "TheGiant"
		EnemyManager.Spawn(run, key, run.PX + 30, run.PZ, { Force = true })
	elseif command == "event" then
		local key = if arg and WaveData.EventByKey[arg] then arg else "Percent67"
		WaveManager.TriggerEvent(run, key)
	elseif command == "weapon" and arg and WeaponData.ByKey[arg] then
		run:AddWeapon(arg)
	elseif command == "max" or command == "evolve" then
		for _, w in run.Weapons do
			w.Level = w.Def.MaxLevel
			local evo = WeaponData.EvolutionOf[w.Key]
			if command == "evolve" and evo and not run.Passives[evo.Evolution.With] then
				run.Passives[evo.Evolution.With] = 1
				table.insert(run.PassiveOrder, evo.Evolution.With)
			end
		end
		run:RefreshStats()
		run:SendLoadout()
		run:CheckEvolutions()
		if command == "evolve" then
			run.PendingChests += 1
		end
	elseif command == "god" then
		run.Invulnerable = if run.Invulnerable > 1000 then 0 else 1e9
		say("god mode " .. (if run.Invulnerable > 0 then "ON" else "OFF"))
	elseif command == "killall" then
		for _, e in table.clone(run.Enemies) do
			EnemyManager.Damage(run, e, e.HP + 1, 0, 0, 0, 0)
		end
	elseif command == "die" then
		run.Invulnerable = 0
		run:HurtPlayer(1e9, true)
	elseif command == "miniboss" then
		local key = if arg and MiniBossData.ByKey[arg] then arg else nil
		if not ArenaDirector.Summon(run, "Debug", false, key, true) then
			say("no mini-boss can come out now")
		end
	elseif command == "relic" then
		local key = if arg and RelicData.ByKey[arg] then arg else Relics.Roll(run, 4)
		if key then
			Relics.Drop(run, key, run.PX + run.FX * 5, run.PZ + run.FZ * 5)
		end
	elseif command == "vault" then
		run.Map.VaultAt = 0
		run.Map.QuietUntil = 0
	elseif command == "rush" then
		run.Map.HotAt = 0
		run.Map.QuietUntil = 0
	else
		say("unknown command " .. command)
	end
end

function AdminManager:Start()
	Guard.Connect(Net.Event("Admin"), { Rate = 5, Burst = 10 }, function(player, command, arg)
		if Guard.Str(command, 32) then
			self:Run(player, command, if type(arg) == "string" then string.sub(arg, 1, 32) else nil)
		end
	end)
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			local command, arg = string.match(message, "^/(%w+)%s*(%S*)")
			if command then
				self:Run(player, command, if arg ~= "" then arg else nil)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return AdminManager
