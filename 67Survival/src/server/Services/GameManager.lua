--[[
	GameManager - runs on the Roblox server.

	  * StartRun: builds a Run (server/Sim/Run.lua) for the player (and their party), teleports
	    them into the arena. In a party the 67 events of the player who pressed PLAY are
	    mirrored into every member's run (WaveManager.TriggerEvent)
	  * ONE Heartbeat connection steps every active run at a fixed rate (GameConfig.Sim.Rate) and
	    ships its output: a binary Frame every SnapshotEvery steps + batched reliable RunEvents
	  * reads the player's position from their character (with a movement sanity check: the
	    simulation never moves faster than the player's walk speed allows, so teleport hacks
	    cannot vacuum gems or dodge damage)
	  * level-up choices / rerolls / skips / revives / quitting (validated by the Run)
	  * run end -> RewardManager -> Results screen
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local GameConfig = require(Shared.GameConfig)
local HeroData = require(Shared.HeroData)
local WeaponData = require(Shared.WeaponData)
local CosmeticData = require(Shared.CosmeticData)
local LiveEvents = require(Shared.LiveEvents)
local DifficultyData = require(Shared.DifficultyData)

local Guard = require(script.Parent.Parent.Util.Guard)
local Run = require(script.Parent.Parent.Sim.Run)
local WaveManager = require(script.Parent.Parent.Sim.WaveManager)

local GameManager = {}

local STEP = 1 / GameConfig.Sim.Rate
local CENTER = GameConfig.Arena.Center

function GameManager:Init(services)
	self.Services = services
	self.Entries = {} -- [Player] = entry
	self.GateNotified = {} :: { [Player]: number } -- a locked gate says why, not 30 times a second
	self.Presses = {} :: { [Player]: number } -- the DO NOT PRESS button of 67 LAND
	self.FellAt = {} :: { [Player]: number }
	self.Acc = 0
	self.Remotes = {
		Frame = Net.Event("Frame"),
		RunEvent = Net.Event("RunEvent"),
	}
	self.Stats = { Steps = 0, Frames = 0, Bytes = 0 }
end

function GameManager:GetRun(player: Player)
	local entry = self.Entries[player]
	return entry and entry.Run
end

function GameManager:ActiveRuns(): number
	local n = 0
	for _ in self.Entries do
		n += 1
	end
	return n
end

-- the global enemy budget is shared between all active runs
function GameManager:Rebudget()
	local count = math.max(1, self:ActiveRuns())
	local cap = math.min(GameConfig.Sim.MaxEnemiesPerRun, math.floor(GameConfig.Sim.GlobalEnemyBudget / count))
	for _, entry in self.Entries do
		local run = entry.Run
		run.BaseMaxEnemies = math.max(80, cap)
		if run.Wave and run.Wave.InvasionUntil > run.Time then
			run.MaxEnemies = WaveManager.InvasionCap(run)
		else
			run.MaxEnemies = run.BaseMaxEnemies
		end
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

---------------------------------------------------------------------------
-- start
---------------------------------------------------------------------------
local function freeSpot(self): number
	local used = {}
	for _, other in self.Entries do
		used[other.Spot] = true
	end
	for i = 1, #GameConfig.Arena.StartOffsets do
		if not used[i] then
			return i
		end
	end
	return 1
end

-- hero + starting ability for a run: explicit choice, else the active loadout
local function loadoutFor(data, heroKey: any, startWeapon: any): (string, string?)
	local loadout = data.Loadouts[data.Loadout] or data.Loadouts[1]
	local hero = if type(heroKey) == "string" and HeroData.ByKey[heroKey] and data.Heroes[heroKey] then heroKey else nil
	hero = hero or (if loadout.Hero ~= "" and data.Heroes[loadout.Hero] then loadout.Hero else data.Selected)
	local weapon = if type(startWeapon) == "string" then startWeapon else loadout.StartWeapon
	if not (weapon ~= "" and WeaponData.IsBase(weapon) and data.Weapons[weapon]) then
		weapon = nil
	end
	return hero, weapon
end

function GameManager:CreateEntry(player: Player, opts)
	local session = self.Services.PlayerManager:Get(player)
	if not session or self.Entries[player] then
		return nil
	end
	local data = session.Data
	local heroKey, weapon = loadoutFor(data, opts.Hero, opts.StartWeapon)
	data.Selected = heroKey

	if not player.Character or not rootOf(player) then
		player:LoadCharacter()
	end
	if not rootOf(player) then
		return nil
	end
	local offset = opts.Offset
	local run = Run.new({
		Seed = opts.Seed,
		Hero = heroKey,
		Meta = data.Meta,
		Unlocked = data.Weapons,
		StartWeapon = weapon,
		Colliders = self.Services.MapBuilder.Colliders,
		StartX = offset.X,
		StartZ = offset.Z,
		LiveEvent = LiveEvents.Mods(os.time()),
		Follower = opts.Follower,
		Difficulty = opts.Difficulty,
	})
	local entry = {
		Player = player,
		Run = run,
		Spot = opts.Spot,
		Steps = 0,
		Session = session,
		LastX = offset.X,
		LastZ = offset.Z,
		Drift = 0,
		WalkSpeed = -1,
		StartedAt = os.clock(),
		Group = opts.Group,
	}
	self.Entries[player] = entry
	player:SetAttribute("InRun", true)
	local CM = self.Services.CharacterManager
	CM:Teleport(player, CFrame.new(CENTER + offset + Vector3.new(0, 0.5, 0)))
	CM:SetJump(player, false)
	CM:Refresh(player)

	local names = {}
	for _, p in opts.Group.Players do
		if p ~= player then
			table.insert(names, p.DisplayName)
		end
	end
	self.Remotes.RunEvent:FireClient(player, {
		{
			Name = "RunStart",
			Payload = {
				Hero = heroKey,
				StartX = offset.X,
				StartZ = offset.Z,
				Center = CENTER,
				GroundY = GameConfig.Arena.GroundY,
				SpawnEffect = CosmeticData.Style(data.Cosmetics.Equipped, "SpawnEffect"),
				Party = names,
				LiveEvents = LiveEvents.Active(os.time()),
				Difficulty = run.Difficulty,
			},
		},
	})
	self:SendEvents(entry)
	return entry
end

--[[
	PLAY: starts a run for the player, and for every party member waiting in the lobby.
	The one who pressed PLAY leads the 67 events of the group.
]]
function GameManager:StartRun(player: Player, heroKey: any, startWeapon: any): boolean
	if self.Entries[player] or not self.Services.PlayerManager:Get(player) then
		return false
	end
	local members = self.Services.PartyManager:Members(player)
	local group = { Players = {}, Leader = player }
	for _, p in members do
		if p.Parent and not self.Entries[p] and self.Services.PlayerManager:Get(p) then
			table.insert(group.Players, p)
		end
	end
	local spot = freeSpot(self)
	local base = GameConfig.Arena.StartOffsets[spot]
	local seed = math.random(1, 2 ^ 30)
	-- the leader's difficulty (validated against what the leader has opened) for the whole party
	local leaderData = self.Services.PlayerManager:Get(player).Data
	local difficulty = math.clamp(leaderData.Difficulty.Selected, 1, DifficultyData.Unlocked(leaderData.Difficulty.Best))
	local leaderEntry = nil
	local followers = {}
	local slot = 0
	for _, p in group.Players do
		local isLeader = p == player
		local offset = base
		if not isLeader then
			slot += 1
			local a = slot * (math.pi * 2 / 3)
			offset = base + Vector3.new(math.cos(a) * 8, 0, math.sin(a) * 8)
		end
		local entry = self:CreateEntry(p, {
			Hero = if isLeader then heroKey else nil,
			StartWeapon = if isLeader then startWeapon else nil,
			Offset = offset,
			Spot = spot,
			Seed = seed + slot,
			Follower = not isLeader,
			Group = group,
			Difficulty = difficulty,
		})
		if entry then
			if isLeader then
				leaderEntry = entry
			else
				table.insert(followers, entry)
			end
		end
	end
	group.Size = #group.Players
	if leaderEntry and #followers > 0 then
		-- 67 events happen for the whole party at the same moment
		leaderEntry.Run.OnEvent67 = function(key: string, variant: string?)
			for _, f in followers do
				if self.Entries[f.Player] == f and not f.Run.Ended then
					WaveManager.TriggerEvent(f.Run, key, variant)
				end
			end
		end
	end
	self:Rebudget()
	return leaderEntry ~= nil
end

---------------------------------------------------------------------------
-- stepping
---------------------------------------------------------------------------
function GameManager:SendEvents(entry)
	local events = entry.Run:TakeEvents()
	if #events > 0 then
		self.Remotes.RunEvent:FireClient(entry.Player, events)
	end
end

-- Server-side position with a speed limit. Returns x, z, fx, fz in arena coordinates.
function GameManager:ReadPosition(entry): (number?, number?, number?, number?)
	local root = rootOf(entry.Player)
	if not root then
		return nil
	end
	local p = root.Position - CENTER
	local look = root.CFrame.LookVector
	local run = entry.Run
	local maxStep = run.Stats.WalkSpeed * STEP * 1.35 + 0.35
	local dx, dz = p.X - entry.LastX, p.Z - entry.LastZ
	local d = math.sqrt(dx * dx + dz * dz)
	local x, z = p.X, p.Z
	if d > maxStep then
		-- faster than possible: only move as far as allowed
		x, z = entry.LastX + dx / d * maxStep, entry.LastZ + dz / d * maxStep
		entry.Drift += STEP
	else
		entry.Drift = math.max(0, entry.Drift - STEP * 0.5)
	end
	if entry.Drift > 1.5 then
		-- the character is somewhere else for too long: put it back where the server thinks it is
		entry.Drift = 0
		self.Services.CharacterManager:Teleport(entry.Player, CFrame.new(CENTER + Vector3.new(x, 0.5, z)))
	end
	entry.LastX, entry.LastZ = x, z
	return x, z, look.X, look.Z
end

function GameManager:StepEntry(entry)
	local run = entry.Run
	if not run:IsPaused() then
		local x, z, fx, fz = self:ReadPosition(entry)
		if x then
			run:SetPlayer(x, z, fx, fz)
		end
	end
	run:Step(STEP)
	entry.Steps += 1

	-- the hero teleported inside the simulation (THE GLITCH): move the character too
	local tp = run.TeleportTo
	if tp then
		run.TeleportTo = nil
		entry.LastX, entry.LastZ = tp.X, tp.Z
		entry.Drift = 0
		self.Services.CharacterManager:Teleport(entry.Player, CFrame.new(CENTER + Vector3.new(tp.X, 0.5, tp.Z)))
	end

	-- walk speed follows stats (slower in water); frozen while choosing / dead / paused
	local wade = if run:InWater(run.PX, run.PZ) then GameConfig.Water.PlayerSpeed else 1
	local speed = if run:IsPaused() then 0 else run.Stats.WalkSpeed * wade
	if speed ~= entry.WalkSpeed then
		entry.WalkSpeed = speed
		self.Services.CharacterManager:SetWalkSpeed(entry.Player, speed)
	end

	if entry.Steps % GameConfig.Sim.SnapshotEvery == 0 or run.Ended then
		local frame = run:Flush()
		self.Stats.Frames += 1
		self.Stats.Bytes += buffer.len(frame)
		self.Remotes.Frame:FireClient(entry.Player, frame)
		self:SendEvents(entry)
	end
	if run.Ended then
		self:Finish(entry)
	end
end

function GameManager:Heartbeat(dt: number)
	self.Acc += dt
	local steps = 0
	while self.Acc >= STEP and steps < GameConfig.Sim.MaxStepsPerHeartbeat do
		self.Acc -= STEP
		steps += 1
		self.Stats.Steps += 1
		for _, entry in table.clone(self.Entries) do
			local ok, err = pcall(self.StepEntry, self, entry)
			if not ok then
				warn("[GameManager] run step failed: " .. tostring(err))
				entry.Run:End("Error")
				pcall(self.Finish, self, entry)
			end
		end
	end
	if self.Acc > STEP * GameConfig.Sim.MaxStepsPerHeartbeat then
		self.Acc = 0 -- server hitch: skip time instead of spiralling
	end
end

---------------------------------------------------------------------------
-- end
---------------------------------------------------------------------------
function GameManager:Finish(entry)
	if self.Entries[entry.Player] ~= entry then
		return
	end
	self.Entries[entry.Player] = nil
	self:Rebudget()
	local player = entry.Player
	local session = entry.Session
	local summary = entry.Run:Summary()
	local party = self.Services.PartyManager
	local rewards = self.Services.RewardManager:OnRunEnd(session, summary, {
		Party = if entry.Group then entry.Group.Size or 1 else 1,
		Friends = party:FriendsOnline(player),
	})
	party:AddKills(summary.Kills)
	player:SetAttribute("InRun", false)
	if player.Parent and not session.Leaving then
		self.Services.CharacterManager:SetWalkSpeed(player, 0)
		self.Remotes.RunEvent:FireClient(player, {
			{ Name = "Results", Payload = { Summary = summary, Rewards = rewards } },
		})
		self.Services.PlayerManager:Sync(player)
		task.spawn(function()
			self.Services.DataManager:Save(session, false)
		end)
	end
end

function GameManager:EndRun(player: Player, reason: string)
	local entry = self.Entries[player]
	if entry then
		entry.Run:End(reason)
		self:Finish(entry)
	end
end

function GameManager:ReturnToLobby(player: Player)
	if self.Entries[player] then
		return
	end
	self.Services.CharacterManager:SpawnInLobby(player)
end

function GameManager:OnPlayerLeaving(player: Player)
	self:EndRun(player, "Quit")
end

function GameManager:OnCharacterDied(player: Player)
	if self.Entries[player] then
		self:EndRun(player, "Death")
	end
	player:LoadCharacter()
	self.Services.CharacterManager:SpawnInLobby(player)
end

-- Extra Reroll product: +1 reroll in the current run. Returns true when applied.
function GameManager:ApplyExtraReroll(player: Player): boolean
	local entry = self.Entries[player]
	if entry and not entry.Run.Ended then
		entry.Run:AddRerolls(1)
		self:SendEvents(entry)
		return true
	end
	return false
end

-- Robux revive (MonetizationManager). Returns true when it was applied to a dead run.
function GameManager:ApplyRobuxRevive(player: Player): boolean
	local run = self:GetRun(player)
	if run and run.Dead and not run.RobuxRevived and not run.Ended then
		run:Revive("Robux")
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- remotes
---------------------------------------------------------------------------
--[[
	67 LAND (the lobby event map): walking into the EVENT GATE of a tier plays it. An open
	gate selects the tier (the same check as the difficulty menu) and starts the run; a locked
	one says what opens it.
]]
function GameManager:EnterGate(player: Player, index: number)
	if self.Entries[player] then
		return
	end
	local session = self.Services.PlayerManager:Get(player)
	if not session then
		return
	end
	local i = math.clamp(math.floor(index), 1, DifficultyData.Count)
	if i > DifficultyData.Unlocked(session.Data.Difficulty.Best) then
		local now = os.clock()
		if (self.GateNotified[player] or 0) > now then
			return
		end
		self.GateNotified[player] = now + 3
		local tier = DifficultyData.Get(i)
		self.Services.PlayerManager:Notify(player, string.format("%s is locked: %s", tier.Name, if tier.Unlock then tier.Unlock.Text else ""), "Error")
		return
	end
	self.Services.PlayerManager:SelectDifficulty(player, i)
	self:StartRun(player, nil, nil)
end

-- the DO NOT PRESS button: it does nothing. Almost.
local PRESS_LINES = {
	[1] = "Nothing happened.",
	[6] = "Still nothing.",
	[20] = "It says DO NOT PRESS.",
	[40] = "Please stop.",
	[60] = "Seven more. Not that anyone is counting.",
	[66] = "One more. Probably.",
}
function GameManager:PressButton(player: Player)
	local count = (self.Presses[player] or 0) + 1
	self.Presses[player] = count
	if count == 67 then
		self.Services.RewardManager:FoundSecret(player, "Button67")
	elseif PRESS_LINES[count] then
		self.Services.PlayerManager:Notify(player, PRESS_LINES[count], "Info")
	end
end

-- fell off the island: back to the spawn, with a word of comfort
function GameManager:CatchFall(player: Player, root: BasePart)
	if self.Entries[player] or root.Position.Y > GameConfig.Lobby.Center.Y - 30 then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(self.Services.MapBuilder:SpawnPoint("Lobby") + Vector3.new(0, 3, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	local now = os.clock()
	if (self.FellAt[player] or 0) < now then
		self.FellAt[player] = now + 20
		self.Services.PlayerManager:Notify(player, "You fell off 67 LAND. It happens to the best of us.", "Info")
	end
end

function GameManager:Start()
	Guard.Connect(Net.Event("StartRun"), { Rate = 0.5, Burst = 2 }, function(player, heroKey, startWeapon)
		if Guard.Str(heroKey, 32) or heroKey == nil then
			self:StartRun(player, heroKey, Guard.Str(startWeapon, 32))
		end
	end)
	Guard.Connect(Net.Event("Choose"), { Rate = 6, Burst = 6 }, function(player, index)
		local run = self:GetRun(player)
		local i = Guard.Int(index, 1, 8)
		if run and i then
			run:Choose(i)
			self:SendEvents(self.Entries[player])
		end
	end)
	Guard.Connect(Net.Event("Reroll"), { Rate = 2, Burst = 3 }, function(player)
		local run = self:GetRun(player)
		if run and run:RerollOffer() then
			self:SendEvents(self.Entries[player])
		end
	end)
	Guard.Connect(Net.Event("Skip"), { Rate = 2, Burst = 3 }, function(player)
		local run = self:GetRun(player)
		if run and run:SkipOffer() then
			self:SendEvents(self.Entries[player])
		end
	end)
	Guard.Connect(Net.Event("Revive"), { Rate = 1, Burst = 2 }, function(player)
		local run = self:GetRun(player)
		if run and run.Dead and not run.RobuxRevived then
			-- the purchase dialog takes time: keep the run waiting (once)
			run.ReviveGrace = run.ReviveGrace or 25
			self.Services.MonetizationManager:PromptProduct(player, "Revive")
		end
	end)
	Guard.Connect(Net.Event("GiveUp"), { Rate = 1, Burst = 2 }, function(player)
		local run = self:GetRun(player)
		if run then
			self:EndRun(player, if run.Dead then "Death" else "Quit")
		end
	end)
	Guard.Connect(Net.Event("Pause"), { Rate = 2, Burst = 4 }, function(player, paused)
		local run = self:GetRun(player)
		if run and Guard.Bool(paused) ~= nil then
			run.UserPaused = paused
		end
	end)
	Guard.Connect(Net.Event("ReturnToLobby"), { Rate = 1, Burst = 2 }, function(player)
		self:ReturnToLobby(player)
	end)

	RunService.Heartbeat:Connect(function(dt)
		self:Heartbeat(dt)
	end)

	-- walking into the PLAY portal in the lobby starts a run; an EVENT GATE starts its tier;
	-- the DO NOT PRESS button counts
	local map = Workspace:FindFirstChild("Map")
	if map then
		local function playerOf(hit: BasePart): Player?
			local character = hit:FindFirstAncestorOfClass("Model")
			return character and Players:GetPlayerFromCharacter(character)
		end
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("PlayPortal") then
				d.Touched:Connect(function(hit)
					local player = playerOf(hit)
					if player and not self.Entries[player] then
						self:StartRun(player, nil, nil)
					end
				end)
			elseif d:IsA("BasePart") and type(d:GetAttribute("EventGate")) == "number" then
				local index = d:GetAttribute("EventGate") :: number
				d.Touched:Connect(function(hit)
					local player = playerOf(hit)
					if player then
						self:EnterGate(player, index)
					end
				end)
			elseif d:IsA("ProximityPrompt") and d.Parent and d.Parent:GetAttribute("Button67") then
				d.Triggered:Connect(function(player)
					self:PressButton(player)
				end)
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		self.GateNotified[player] = nil
		self.Presses[player] = nil
		self.FellAt[player] = nil
	end)

	-- secret places (checked by position, not by trusting the client)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root then
					local key = self.Services.MapBuilder:RegionAt(root.Position)
					if key then
						self.Services.RewardManager:FoundSecret(player, key)
					end
					self:CatchFall(player, root)
				end
			end
		end
	end)
end

return GameManager
