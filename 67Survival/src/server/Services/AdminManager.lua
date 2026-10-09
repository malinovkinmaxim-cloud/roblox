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
	  boss <1-4|key>  that boss slot is announced now (its lair), or any enemy by key near you
	  main [key]      the main boss (of this tier, or any tier's by key) comes to the arena now
	  spawn <key>     one enemy of that kind near you (any tier's)
	  item <key>      an item at your feet (no key: a random one of the loot)
	  elite <key>     an elite now                  chips <n>    +n CHIPS
	  affix <key>     an elite with that affix now (SHIELDED, ECHO, Gilded67...)
	  vault           a 67 VAULT wakes up           rush         a 67 RUSH starts
	  unlockitems     every premium item / boss relic unlocked
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
local BossDirector = require(Sim.BossDirector)
local Items = require(Sim.Items)
local Elites = require(Sim.Elites)
local BossData = require(Shared.BossData)
local ItemData = require(Shared.ItemData)

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
	elseif command == "chips" then
		session.Data.Chips += math.clamp(n or 1000, 0, 1e6)
		PM:Sync(player)
		say("CHIPS added")
	elseif command == "unlockitems" then
		for _, def in ItemData.List do
			if ItemData.NeedsUnlock(def) then
				session.Data.ItemUnlocks[def.Key] = true
			end
		end
		PM:Sync(player)
		say("every item unlocked")
	elseif command == "afk" then
		local afk = session.Data.Afk
		afk.Since = math.max(1, (if afk.Since > 0 then afk.Since else os.time()) - (n or 60) * 60)
		PM:Sync(player)
		say("AFK camp +" .. (n or 60) .. " minutes")
	elseif command == "unlockall" then
		for _, def in WeaponData.List do
			if def.Evolution == nil and not def.Premium then -- (premium: bought, never unlocked here)
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
		for _, def in ItemData.List do
			if ItemData.NeedsUnlock(def) then
				session.Data.ItemUnlocks[def.Key] = true
			end
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
		-- a slot (1-4) or a boss of the timeline: announced at its lair, like the real one
		local def = arg and BossData.ByKey[arg]
		local slot = if def then def.Slot else (n or run.BossNext)
		if def and def.Slot == 5 then
			if not BossDirector.ForceMain(run, def.Key) then
				say("the main boss is already out")
			end
		elseif BossData.Slots[slot] then
			BossDirector.Force(run, slot, if def then def.Key else nil, EnemyManager)
			say("boss " .. slot .. " is coming (" .. BossData.Slots[slot].Zone .. ")")
		elseif arg and EnemyData.ByKey[arg] then
			EnemyManager.Spawn(run, arg, run.PX + 30, run.PZ, { Force = true })
		else
			say("boss <1-4 | boss key | enemy key>")
		end
	elseif command == "main" then
		if not BossDirector.ForceMain(run, arg) then
			say("the main boss is already out")
		end
	elseif command == "spawn" then
		if arg and EnemyData.ByKey[arg] then
			local e = EnemyManager.Spawn(run, arg, run.PX + run.FX * 14, run.PZ + run.FZ * 14, { Force = true })
			local pair = e and e.Def.Params.Pair
			if pair then
				local mate = EnemyManager.Spawn(run, pair, e.X + 2.4, e.Z, { Force = true })
				if mate then
					EnemyManager.Pair(e, mate)
				end
			end
		else
			say("spawn <enemy key>")
		end
	elseif command == "elite" then
		if not Elites.Spawn(run, if arg and EnemyData.ByKey[arg] then arg else nil) then
			say("no room for an elite here")
		end
	elseif command == "affix" then
		-- an elite with that affix right in front of you (any tier's affix)
		local key, keys = nil, {}
		for _, a in EnemyData.EliteAffixes do
			table.insert(keys, a.Key)
			if arg and string.lower(a.Key) == string.lower(arg) then
				key = a.Key
			end
		end
		if not key then
			say("affix <" .. table.concat(keys, " | ") .. ">")
		elseif not Elites.Spawn(run, if key == "Echo" then "Spitter" else nil, run.PX + run.FX * 18, run.PZ + run.FZ * 18, { key }) then
			say("no room for an elite here")
		end
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
			EnemyManager.Damage(run, e, e.MaxHP * 10 + 1, 0, 0, 0, 0) -- (armoured elites take less)
		end
	elseif command == "die" then
		-- (straight to zero HP: barrier charges, dodges and guards of the build don't save you)
		if not run.Dead and not run.Ended then
			run.Invulnerable = 0
			run.HP = 0
			run:OnZeroHP()
		end
	elseif command == "item" then
		local key = if arg and ItemData.ByKey[arg] then arg else Items.Roll(run, "Boss4")
		if key then
			Items.Drop(run, key, run.PX + run.FX * 5, run.PZ + run.FZ * 5)
		else
			say("every item is maxed")
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
