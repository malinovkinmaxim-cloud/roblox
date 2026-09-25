--[[
	DoppelgangerService
	Owns every doppelgänger on the server:
	  creation (appearance + skin + visuals), recording the player (TrailRecorder),
	  the single update loop (role -> actor), death, respawn and cleanup.
	Also runs the optional lobby doppelgänger that follows players around the lobby.

	ONE Heartbeat connection for all doppelgängers of all players.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RoleConfig = require(ReplicatedStorage.Shared.RoleConfig)

local Doppelganger = script.Parent.Parent.Doppelganger
local Appearance = require(Doppelganger.Appearance)
local DoppelActor = require(Doppelganger.DoppelActor)
local Skins = require(Doppelganger.Skins)
local TrailRecorder = require(Doppelganger.TrailRecorder)

local DoppelgangerService = {}
DoppelgangerService.LobbyRuns = {} :: { [Player]: any }

local SAMPLE_INTERVAL = 1 / Config.SHADOW_SAMPLE_RATE

function DoppelgangerService:Init(services)
	self.Services = services
end

function DoppelgangerService:Start()
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, run in self.Services.RoundService.ActiveRuns do
			if not run.Ended then
				self:_stepRun(run, dt, now)
			end
		end
		for _, lobbyRun in self.LobbyRuns do
			self:_stepRun(lobbyRun, dt, now)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAppearanceLoaded:Connect(function()
			Appearance.Prewarm(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:RemoveLobbyDoppel(player)
		Appearance.Forget(player)
	end)
end

---------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------

local function isGrounded(root: BasePart, rootOffset: number, params: RaycastParams): boolean
	local result = Workspace:Blockcast(CFrame.new(root.Position), Vector3.new(1.6, 0.4, 1), Vector3.new(0, -(rootOffset + 0.7), 0), params)
	return result ~= nil
end

function DoppelgangerService:_record(run, now: number)
	if now < (run.NextSample or 0) then
		return
	end
	run.NextSample = now + SAMPLE_INTERVAL
	if run.State ~= "Playing" or not run.Recorder then
		return
	end
	local root, _, rootOffset = self.Services.CharacterService:GetLiving(run.Player)
	if not root then
		return
	end
	local cf = root.CFrame
	local grounded = isGrounded(root, rootOffset, run.Instance.GroundParams)
	run.Recorder:Push(now, cf.Position, DoppelActor.YawFromLook(cf.LookVector), grounded, root.AssemblyLinearVelocity.Y)
end

function DoppelgangerService:_stepRun(run, dt: number, now: number)
	self:_record(run, now)
	local actor = run.Doppel
	if not actor or actor.Destroyed then
		return
	end
	local role = run.Role
	if role and not role.Stopped and run.State ~= "Finished" then
		local ok, err = pcall(role.Update, role, dt, now)
		if not ok then
			warn("[DoppelgangerService] role update error: " .. tostring(err))
		end
	end
	actor:Step(dt, now)
end

---------------------------------------------------------------------------
-- Run hooks (called by RoundService)
---------------------------------------------------------------------------

function DoppelgangerService:OnRunStarted(run)
	run.Recorder = TrailRecorder.new(Config.SHADOW_BUFFER_SECONDS)
	run.NextSample = 0
	run.DoppelGen = 0
	self:RemoveLobbyDoppel(run.Player)
	if run.Partner then
		self:RemoveLobbyDoppel(run.Partner)
	end
end

function DoppelgangerService:_createActor(player: Player, inst, spawnCFrame: CFrame)
	local model = Appearance.GetModel(player) -- may yield the very first time
	if inst.Destroyed then
		model:Destroy()
		return nil
	end
	local data = self.Services.DataService:GetData(player)
	Skins.Apply(model, data and data.EquippedCosmetic or "Default")
	local visuals = Appearance.AddVisuals(model, RoleConfig.HiddenColor)
	model:PivotTo(spawnCFrame)
	local actor = DoppelActor.new(model, inst, visuals)
	actor:Teleport(spawnCFrame)
	return actor
end

function DoppelgangerService:SpawnForRun(run)
	task.spawn(function()
		local inst = run.Instance
		local ok, actor = pcall(self._createActor, self, run.Player, inst, inst.DoppelStartCFrame)
		if not ok then
			warn("[DoppelgangerService] failed to create doppelgänger: " .. tostring(actor))
			return
		end
		if not actor then
			return
		end
		if run.Ended then
			actor:Destroy()
			return
		end
		run.Doppel = actor
		actor.OnDied = function(cause)
			self:_onDoppelDied(run, actor, cause)
		end
		-- if the player already moved on (slow appearance load), start next to them
		local checkpoint = inst.Checkpoints[run.CheckpointIndex] or inst.Checkpoints[0]
		if checkpoint and run.CheckpointIndex > 0 then
			actor:Teleport(checkpoint.DoppelCFrame)
		end
		local pending = run.PendingRole
		run.PendingRole = nil
		if pending then
			self.Services.RoleService:SetRole(run, pending, { Reveal = true, Initial = true })
		else
			self.Services.RoleService:AssignInitialRole(run)
		end
	end)
end

function DoppelgangerService:OnRunEnded(run)
	if run.Role then
		pcall(run.Role.Stop, run.Role)
		run.Role = nil
	end
	if run.Doppel then
		run.Doppel:Destroy()
		run.Doppel = nil
	end
	run.Recorder = nil
	if run.Player.Parent then
		Net.Event("DoppelStatus"):FireClient(run.Player, nil, nil)
	end
end

function DoppelgangerService:OnRunFinished(run)
	if run.Role then
		run.Role:Stop()
	end
	local actor = run.Doppel
	if actor and actor:IsAlive() then
		actor:SetFrozen(false)
		actor:SetEmote(if run.RivalFinished then "Cheer" else "Wave")
	end
	Net.Event("DoppelStatus"):FireClient(run.Player, nil, nil)
end

function DoppelgangerService:OnPlayerRespawned(run)
	run.DoppelGen = (run.DoppelGen or 0) + 1
	if run.Recorder then
		run.Recorder:Clear()
		run.Recorder:MarkTeleport()
	end
	local actor = run.Doppel
	if not actor or run.State == "Finished" then
		return
	end
	local checkpoint = run.Instance.Checkpoints[run.CheckpointIndex] or run.Instance.Checkpoints[0]
	if run.Role then
		run.Role:OnPlayerRespawn(checkpoint)
	else
		actor:Respawn(checkpoint.DoppelCFrame)
	end
end

function DoppelgangerService:KillDoppel(run, cause: string)
	local actor = run.Doppel
	if actor and actor:IsAlive() then
		actor:Die(cause)
	end
end

function DoppelgangerService:_onDoppelDied(run, actor, cause: string)
	if run.Ended or run.Doppel ~= actor then
		return
	end
	run.DoppelDeaths += 1
	if run.Player.Parent and run.State == "Playing" then
		Net.Event("DoppelStatus"):FireClient(run.Player, "Died", "YOUR DOPPELGÄNGER FELL!")
	end
	-- SPLIT-style levels: you are linked, if it dies you die
	if run.Def.LinkedFate and run.State == "Playing" and cause ~= "Linked" then
		self.Services.RoundService:KillPlayer(run, run.Player, "Linked")
		return -- it comes back together with the player
	end
	local generation = run.DoppelGen
	task.delay(Config.DOPPEL_RESPAWN_DELAY, function()
		if run.Ended or run.Doppel ~= actor or actor:IsAlive() or run.DoppelGen ~= generation then
			return
		end
		if run.State ~= "Playing" then
			return -- player is dead: the doppel respawns with them
		end
		local cf = if run.Role then run.Role:GetRespawnCFrame() else run.Instance.DoppelStartCFrame
		actor:Respawn(cf)
		if run.Role then
			run.Role:OnDoppelRespawned()
		end
		if run.Player.Parent then
			Net.Event("DoppelStatus"):FireClient(run.Player, "Back", nil)
		end
	end)
end

function DoppelgangerService:OnSourcePressed(run, source, presser)
	if run.Role then
		run.Role:OnSourcePressed(source, presser)
	end
end

function DoppelgangerService:OnDoppelReachedFinish(run)
	if run.Role then
		run.Role:OnReachFinish()
	end
end

function DoppelgangerService:OnRivalFinished(run)
	if run.RivalFinished or run.State == "Finished" then
		return
	end
	run.RivalFinished = true
	run.RivalFinishTime = os.clock() - run.StartClock
	if run.Player.Parent then
		Net.Event("DoppelStatus"):FireClient(run.Player, "Won", "YOUR DOPPELGÄNGER WON THE RACE!")
	end
end

-- Debug
function DoppelgangerService:SetAIEnabled(run, enabled: boolean)
	run.AIEnabled = enabled
end

---------------------------------------------------------------------------
-- Lobby doppelgänger (a Follower that walks behind you in the lobby)
---------------------------------------------------------------------------

local lobbyInstance = nil

local function getLobbyInstance()
	if lobbyInstance then
		return lobbyInstance
	end
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	local actors = lobby:FindFirstChild("LobbyActors")
	if not actors then
		actors = Instance.new("Folder")
		actors.Name = "LobbyActors"
		actors.Parent = lobby
	end
	local blockers = lobby:FindFirstChild("LobbyBlockers") or Instance.new("Folder")
	blockers.Name = "LobbyBlockers"
	blockers.Parent = lobby

	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Include
	ground.FilterDescendantsInstances = { lobby }
	ground.RespectCanCollide = true
	local blockerParams = RaycastParams.new()
	blockerParams.FilterType = Enum.RaycastFilterType.Include
	blockerParams.FilterDescendantsInstances = { blockers }
	blockerParams.RespectCanCollide = true

	lobbyInstance = {
		Def = {},
		Actors = actors,
		GroundParams = ground,
		BlockerParams = blockerParams,
		KillY = Config.LOBBY_POSITION.Y - 60,
		Checkpoints = {},
		Destroyed = false,
		Rng = Random.new(),
	}
	return lobbyInstance
end

function DoppelgangerService:EnsureLobbyDoppel(player: Player)
	if not Config.LOBBY_DOPPEL or self.LobbyRuns[player] or self.Services.RoundService:GetRun(player) then
		return
	end
	local inst = getLobbyInstance()
	local root = self.Services.CharacterService:GetLiving(player)
	if not inst or not root then
		return
	end
	local lobbyRun = {
		IsLobby = true,
		Player = player,
		Instance = inst,
		Def = inst.Def,
		State = "Playing",
		CheckpointIndex = 0,
		AIEnabled = true,
		Recorder = TrailRecorder.new(10),
		NextSample = 0,
		RoleHistory = {},
		Loading = true,
	}
	self.LobbyRuns[player] = lobbyRun
	task.spawn(function()
		local spawnCFrame = root.CFrame * CFrame.new(0, 0, 5)
		local ok, actor = pcall(self._createActor, self, player, inst, spawnCFrame)
		if self.LobbyRuns[player] ~= lobbyRun then
			if ok and actor then
				actor:Destroy()
			end
			return
		end
		if not ok or not actor then
			self.LobbyRuns[player] = nil
			return
		end
		lobbyRun.Doppel = actor
		lobbyRun.Loading = false
		actor:SetRoleDisplay("YOU?", RoleConfig.HiddenColor)
		local Follower = self.Services.RoleService.Modules.Follower
		local role = Follower.new({
			Run = lobbyRun,
			Actor = actor,
			Recorder = lobbyRun.Recorder,
			Services = self.Services,
			Rng = inst.Rng,
		})
		lobbyRun.Role = role
		role:Start()
		actor.OnDied = function()
			task.delay(1, function()
				if self.LobbyRuns[player] == lobbyRun and not actor.Destroyed then
					local near = role:GetPositionNearPlayer()
					if near then
						actor:Respawn(near)
						role:ResetPlayback()
					end
				end
			end)
		end
	end)
end

function DoppelgangerService:RemoveLobbyDoppel(player: Player)
	local lobbyRun = self.LobbyRuns[player]
	if not lobbyRun then
		return
	end
	self.LobbyRuns[player] = nil
	if lobbyRun.Role then
		lobbyRun.Role:Stop()
	end
	if lobbyRun.Doppel then
		lobbyRun.Doppel:Destroy()
	end
end

-- The lobby doppel must be reset when the player teleports (no walking across the map).
function DoppelgangerService:OnLobbySpawn(player: Player)
	local lobbyRun = self.LobbyRuns[player]
	if lobbyRun then
		self:RemoveLobbyDoppel(player)
	end
	task.delay(0.5, function()
		if player.Parent and not self.Services.RoundService:GetRun(player) then
			self:EnsureLobbyDoppel(player)
		end
	end)
end

return DoppelgangerService
