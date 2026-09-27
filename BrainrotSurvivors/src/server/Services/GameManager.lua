--[[
	GameManager - runs on the Roblox server.

	  * StartRun: builds a Run (server/Sim/Run.lua) for the player, teleports them into the arena
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
local CharacterData = require(Shared.CharacterData)
local WeaponData = require(Shared.WeaponData)

local Guard = require(script.Parent.Parent.Util.Guard)
local Run = require(script.Parent.Parent.Sim.Run)

local GameManager = {}

local STEP = 1 / GameConfig.Sim.Rate
local CENTER = GameConfig.Arena.Center

function GameManager:Init(services)
	self.Services = services
	self.Entries = {} -- [Player] = entry
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
		entry.Run.MaxEnemies = math.max(80, cap)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

---------------------------------------------------------------------------
-- start
---------------------------------------------------------------------------
function GameManager:StartRun(player: Player, characterKey: any, startWeapon: any): boolean
	local PM = self.Services.PlayerManager
	local session = PM:Get(player)
	if not session or self.Entries[player] then
		return false
	end
	local data = session.Data
	if type(characterKey) ~= "string" or not CharacterData.ByKey[characterKey] or not data.Characters[characterKey] then
		characterKey = data.Selected
	end
	data.Selected = characterKey
	local weapon = nil
	if type(startWeapon) == "string" and startWeapon ~= "" and WeaponData.ByKey[startWeapon] and data.Weapons[startWeapon] then
		if self.Services.MonetizationManager:HasPass(player, "ExtraLoadout") then
			weapon = startWeapon
			data.StartWeapon = startWeapon
		end
	end

	if not player.Character or not rootOf(player) then
		player:LoadCharacter()
	end
	local root = rootOf(player)
	if not root then
		return false
	end

	-- spread players over the start spots
	local used = {}
	for _, other in self.Entries do
		used[other.Spot] = true
	end
	local spot = 1
	for i = 1, #GameConfig.Arena.StartOffsets do
		if not used[i] then
			spot = i
			break
		end
	end
	local offset = GameConfig.Arena.StartOffsets[spot]

	local run = Run.new({
		Seed = math.random(1, 2 ^ 30),
		Character = characterKey,
		Meta = data.Meta,
		Unlocked = data.Weapons,
		StartWeapon = weapon,
		Colliders = self.Services.MapBuilder.Colliders,
		StartX = offset.X,
		StartZ = offset.Z,
	})
	local entry = {
		Player = player,
		Run = run,
		Spot = spot,
		Steps = 0,
		Session = session,
		LastX = offset.X,
		LastZ = offset.Z,
		Drift = 0,
		WalkSpeed = -1,
		StartedAt = os.clock(),
	}
	self.Entries[player] = entry
	self:Rebudget()

	local CM = self.Services.CharacterManager
	CM:Teleport(player, CFrame.new(CENTER + offset + Vector3.new(0, 0.5, 0)))
	CM:SetJump(player, false)
	CM:Refresh(player)
	player:SetAttribute("InRun", true)

	self.Remotes.RunEvent:FireClient(player, {
		{
			Name = "RunStart",
			Payload = {
				Character = characterKey,
				StartX = offset.X,
				StartZ = offset.Z,
				Center = CENTER,
				GroundY = GameConfig.Arena.GroundY,
			},
		},
	})
	self:SendEvents(entry)
	return true
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

	-- walk speed follows stats; frozen while choosing / dead / paused
	local speed = if run:IsPaused() then 0 else run.Stats.WalkSpeed
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
	local rewards = self.Services.RewardManager:OnRunEnd(session, summary)
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
function GameManager:Start()
	Guard.Connect(Net.Event("StartRun"), { Rate = 0.5, Burst = 2 }, function(player, characterKey, startWeapon)
		if Guard.Str(characterKey, 32) or characterKey == nil then
			self:StartRun(player, characterKey, Guard.Str(startWeapon, 32))
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

	-- walking into the PLAY portal in the lobby starts a run
	local map = Workspace:FindFirstChild("Map")
	if map then
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("PlayPortal") then
				d.Touched:Connect(function(hit)
					local character = hit:FindFirstAncestorOfClass("Model")
					local player = character and Players:GetPlayerFromCharacter(character)
					if player and not self.Entries[player] then
						self:StartRun(player, nil, nil)
					end
				end)
			end
		end
	end

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
				end
			end
		end
	end)
end

return GameManager
