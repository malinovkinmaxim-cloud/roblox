--[[
	RoundService
	The run lifecycle (one "run" = one player playing one level, optionally with a Duo partner):
	  StartRun -> Playing -> (Dead -> Respawn at checkpoint)* -> Finish -> results -> EndRun

	The server alone decides: start/finish, time, deaths, checkpoints, roles and rewards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local RoundService = {}
RoundService.ActiveRuns = {} -- array of runs
RoundService.RunsByPlayer = {} :: { [Player]: any }

local nextRunId = 0

function RoundService:Init(services)
	self.Services = services
end

function RoundService:Start()
	local playLimiter = RateLimiter.new(1, 2)
	local actionLimiter = RateLimiter.new(4, 6)

	Net.Event("RequestPlay").OnServerEvent:Connect(function(player, levelId)
		if typeof(levelId) ~= "number" or levelId ~= levelId or levelId % 1 ~= 0 then
			return
		end
		if not playLimiter:Allow(player) then
			return
		end
		local run = self:GetRun(player)
		if run and run.Partner == player then
			Net.Event("Toast"):FireClient(player, "Only the Duo host can choose levels.", "Error")
			return
		end
		if run and run.Partner then
			-- Duo host picked a new level: keep the duo together
			self.Services.DuoService:StartDuoLevel(player, levelId)
			return
		end
		local ok, message = self:StartRun(player, levelId)
		if not ok then
			Net.Event("Toast"):FireClient(player, message or "Can't start that level.", "Error")
		end
	end)

	Net.Event("RequestLeave").OnServerEvent:Connect(function(player)
		if not actionLimiter:Allow(player) then
			return
		end
		local run = self:GetRun(player)
		if run then
			self:EndRun(run, "Left")
		end
	end)

	Net.Event("RequestRestart").OnServerEvent:Connect(function(player, kind)
		if kind ~= "Checkpoint" and kind ~= "Level" then
			return
		end
		if not actionLimiter:Allow(player) then
			return
		end
		local run = self:GetRun(player)
		if not run then
			return
		end
		if kind == "Level" then
			if run.Partner == player then
				return -- only the host restarts a duo level
			end
			if run.Partner then
				self.Services.DuoService:StartDuoLevel(player, run.LevelId)
			else
				self:StartRun(player, run.LevelId, { Force = true })
			end
		elseif run.State == "Playing" then
			self:KillPlayer(run, player, "Restart")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local run = self.RunsByPlayer[player]
		if run then
			if run.Partner == player then
				self.Services.DuoService:OnPartnerLeft(run)
			else
				self:EndRun(run, "PlayerRemoving")
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------

function RoundService:GetRun(player: Player)
	return self.RunsByPlayer[player]
end

function RoundService:IsUnlocked(player: Player, levelId: number): boolean
	local LevelService = self.Services.LevelService
	if not LevelService:GetLevel(levelId) then
		return false
	end
	if self.Services.DebugService:IsDebug(player) then
		return true
	end
	local index = table.find(LevelService.Order, levelId)
	if index == 1 then
		return true
	end
	local data = self.Services.DataService:GetData(player)
	if not data then
		return false
	end
	if data.CompletedLevels[Progression.LevelKey(levelId)] then
		return true
	end
	local previous = LevelService.Order[(index or 1) - 1]
	return previous ~= nil and data.CompletedLevels[Progression.LevelKey(previous)] == true
end

-- Actors = everything that can press buttons, die on hazards, hit checkpoints.
function RoundService:GetActors(run)
	local CharacterService = self.Services.CharacterService
	local actors = {}
	if run.State == "Playing" or run.State == "Finished" then
		local root, humanoid, offset = CharacterService:GetLiving(run.Player)
		if root and humanoid then
			table.insert(actors, {
				Kind = "Player",
				Player = run.Player,
				Root = root,
				Humanoid = humanoid,
				Position = root.Position,
				RootOffset = offset,
				Ghost = false,
			})
		end
	end
	if run.Partner then
		local root, humanoid, offset = CharacterService:GetLiving(run.Partner)
		if root and humanoid then
			table.insert(actors, {
				Kind = "Doppel",
				Player = run.Partner,
				IsPartner = true,
				Root = root,
				Humanoid = humanoid,
				Position = root.Position,
				RootOffset = offset,
				Ghost = false,
			})
		end
	end
	local doppel = run.Doppel
	if doppel and doppel:IsAlive() then
		table.insert(actors, {
			Kind = "Doppel",
			Actor = doppel,
			Root = doppel.Root,
			Position = doppel.Position,
			RootOffset = doppel.RootOffset,
			Ghost = doppel.Ghost,
		})
	end
	return actors
end

function RoundService:GetRunInfo(run, forPlayer: Player)
	local data = self.Services.DataService:GetData(run.Player)
	local key = Progression.LevelKey(run.LevelId)
	return {
		RunId = run.Id,
		LevelId = run.LevelId,
		Name = run.Def.Name,
		Subtitle = run.Def.Subtitle or "",
		ParTime = run.Def.ParTime,
		CheckpointIndex = run.CheckpointIndex,
		CheckpointCount = run.Instance.CheckpointCount,
		StartServerTime = run.StartServerTime,
		BestTime = data and data.BestTimes[key] or nil,
		IsPartner = forPlayer == run.Partner,
		Mode = run.Mode,
		HostName = run.Player.DisplayName,
		PartnerName = run.Partner and run.Partner.DisplayName or nil,
		Hint = run.Def.Hint,
	}
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

--[[
	opts:
	  Force   : skip unlock check (restart / debug)
	  Partner : Player (Duo mode)
	  Mode    : "Solo" | "DuoTrust" | "DuoBetrayal"
	  Role    : force a role (debug)
]]
function RoundService:StartRun(player: Player, levelId: number, opts: { [string]: any }?)
	opts = opts or {}
	local services = self.Services
	local def = services.LevelService:GetLevel(levelId)
	if not def then
		return false, "That level does not exist."
	end
	if not services.DataService:GetData(player) then
		return false, "Your data is still loading..."
	end
	if not (opts :: any).Force and not self:IsUnlocked(player, levelId) then
		return false, "Complete the previous level first!"
	end

	-- end any previous run of the host / partner
	local previous = self.RunsByPlayer[player]
	if previous then
		self:EndRun(previous, "Restart", true)
	end
	local partner: Player? = (opts :: any).Partner
	if partner then
		local partnerRun = self.RunsByPlayer[partner]
		if partnerRun then
			self:EndRun(partnerRun, "Restart", true)
		end
	end

	local ok, inst = pcall(function()
		return services.LevelService:BuildInstance(levelId, player.Name)
	end)
	if not ok then
		warn("[RoundService] failed to build level " .. levelId .. ": " .. tostring(inst))
		return false, "Level failed to load."
	end

	nextRunId += 1
	local data = services.DataService:GetData(player)
	local run: any = {
		Id = nextRunId,
		Player = player,
		Partner = partner,
		Mode = (opts :: any).Mode or "Solo",
		LevelId = levelId,
		Def = def,
		Instance = inst,
		State = "Playing",
		Ended = false,
		StartClock = os.clock(),
		StartServerTime = Workspace:GetServerTimeNow(),
		CheckpointIndex = 0,
		CheckpointsRewarded = {},
		Deaths = 0,
		PartnerDeaths = 0,
		DoppelDeaths = 0,
		DeathCause = {},
		Generation = 0,
		FirstClear = not (data and data.CompletedLevels[Progression.LevelKey(levelId)]),
		RoleHistory = {},
		RivalFinished = false,
		AIEnabled = true,
		ForcedRole = (opts :: any).Role,
		Doppel = nil,
		Role = nil,
		RoleName = nil,
		RoleRevealed = false,
		Recorder = nil,
	}
	inst.Run = run
	self.RunsByPlayer[player] = run
	player:SetAttribute("InLevel", levelId) -- read by the client spectator UI
	if partner then
		self.RunsByPlayer[partner] = run
		partner:SetAttribute("InLevel", levelId)
	end
	table.insert(self.ActiveRuns, run)

	services.ObstacleService:Register(inst)
	services.DoppelgangerService:OnRunStarted(run)

	-- players to the start
	services.CharacterService:Teleport(player, inst.StartCFrame)
	if partner then
		services.CharacterService:Teleport(partner, inst.DoppelStartCFrame)
	end

	Net.Event("RunStarted"):FireClient(player, self:GetRunInfo(run, player))
	if partner then
		Net.Event("RunStarted"):FireClient(partner, self:GetRunInfo(run, partner))
	end

	if partner then
		services.DuoService:OnRunStarted(run)
	else
		-- AI doppelgänger (appearance may take a moment the very first time)
		services.DoppelgangerService:SpawnForRun(run)
	end
	return true
end

-- keepPlayers = true when a new run replaces this one immediately (no lobby teleport)
function RoundService:EndRun(run, reason: string, keepPlayers: boolean?)
	if run.Ended then
		return
	end
	run.Ended = true
	run.State = "Ended"
	local services = self.Services

	local index = table.find(self.ActiveRuns, run)
	if index then
		table.remove(self.ActiveRuns, index)
	end
	services.DoppelgangerService:OnRunEnded(run)
	services.ObstacleService:Unregister(run.Instance)
	services.LevelService:DestroyInstance(run.Instance)

	for _, player in { run.Player, run.Partner } do
		if player and self.RunsByPlayer[player] == run then
			self.RunsByPlayer[player] = nil
			if player.Parent then
				player:SetAttribute("InLevel", nil)
			end
			if player.Parent and reason ~= "Finished" then
				Net.Event("RunEnded"):FireClient(player, { Aborted = true, Reason = reason })
			end
			if player.Parent and not keepPlayers then
				self:SendToLobby(player)
			end
		end
	end
	services.DuoService:OnRunEnded(run, reason)
end

function RoundService:SendToLobby(player: Player)
	local CharacterService = self.Services.CharacterService
	if CharacterService:Teleport(player, CharacterService:GetLobbySpawn()) then
		self.Services.DoppelgangerService:OnLobbySpawn(player)
	end
end

-- Kill a player of this run (host or partner) with a cause for the death screen.
function RoundService:KillPlayer(run, player: Player, cause: string)
	if run.Ended then
		return
	end
	local _, humanoid = self.Services.CharacterService:GetLiving(player)
	if humanoid then
		run.DeathCause[player] = cause
		humanoid.Health = 0
	end
end

function RoundService:OnCharacterDied(player: Player, _character: Model)
	local services = self.Services
	local run = self.RunsByPlayer[player]
	if not run or run.Ended then
		services.CharacterService:RespawnInLobbyLater(player)
		return
	end

	local isPartner = player == run.Partner
	local cause = run.DeathCause[player] or "Fell"
	run.DeathCause[player] = nil

	if run.State == "Finished" then
		-- died after finishing (reset button etc.): quietly respawn at the finish
		task.delay(1, function()
			if self.RunsByPlayer[player] == run and not run.Ended then
				services.CharacterService:Respawn(player)
			end
		end)
		return
	end

	if isPartner then
		run.PartnerDeaths += 1
	else
		run.Deaths += 1
		run.State = "Dead"
		run.Generation += 1
	end
	services.DataService:IncrementStat(player, "Deaths", 1)

	local doppelAlive
	if run.Partner then
		local other = if isPartner then run.Player else run.Partner
		doppelAlive = (services.CharacterService:GetLiving(other :: Player)) ~= nil
	else
		doppelAlive = run.Doppel ~= nil and run.Doppel:IsAlive()
	end

	local info = {
		Cause = cause,
		DoppelAlive = doppelAlive,
		RespawnDelay = Config.RESPAWN_DELAY,
		Deaths = if isPartner then run.PartnerDeaths else run.Deaths,
		IsPartner = isPartner,
	}
	Net.Event("PlayerDied"):FireClient(player, info)
	services.DuoService:OnPlayerDied(run, player)

	task.delay(Config.RESPAWN_DELAY, function()
		if self.RunsByPlayer[player] == run and not run.Ended then
			services.CharacterService:Respawn(player)
		end
	end)
end

-- Called by CharacterService for every new character. Returns where it should stand (nil = lobby).
function RoundService:OnCharacterSpawned(player: Player, _character: Model): CFrame?
	local run = self.RunsByPlayer[player]
	if not run or run.Ended then
		return nil
	end
	local inst = run.Instance
	local checkpoint = inst.Checkpoints[run.CheckpointIndex] or inst.Checkpoints[0]
	if player == run.Partner then
		task.defer(function()
			self.Services.DuoService:OnPartnerSpawned(run)
		end)
		return checkpoint and checkpoint.DoppelCFrame or inst.DoppelStartCFrame
	end
	if run.State == "Finished" then
		return inst.FinishPart and (inst.FinishPart.CFrame + Vector3.new(0, 3.5, 0)) or inst.StartCFrame
	end
	run.State = "Playing"
	task.defer(function()
		if run.Ended then
			return
		end
		self.Services.DoppelgangerService:OnPlayerRespawned(run)
		Net.Event("PlayerRespawned"):FireClient(player)
	end)
	return checkpoint and checkpoint.SpawnCFrame or inst.StartCFrame
end

function RoundService:Finish(run: any)
	if run.State ~= "Playing" or run.Ended then
		return
	end
	run.State = "Finished"
	run.FinishTime = os.clock() - run.StartClock
	local services = self.Services
	services.DoppelgangerService:OnRunFinished(run)

	local results = services.RewardService:GrantFinish(run)
	results.NextLevelId = services.LevelService:GetNextLevelId(run.LevelId)
	Net.Event("RunEnded"):FireClient(run.Player, results)
	if run.Partner then
		local partnerResults = services.RewardService:GrantPartner(run)
		partnerResults.NextLevelId = results.NextLevelId
		Net.Event("RunEnded"):FireClient(run.Partner, partnerResults)
	end

	local runId = run.Id
	task.delay(Config.RESULTS_AUTO_RETURN, function()
		local state: string = (run :: any).State
		if not run.Ended and run.Id == runId and state == "Finished" then
			self:EndRun(run, "Timeout")
		end
	end)
end

-- Debug / tools: finish instantly
function RoundService:ForceFinish(run)
	if run.State == "Dead" then
		return
	end
	self:Finish(run)
end

return RoundService
