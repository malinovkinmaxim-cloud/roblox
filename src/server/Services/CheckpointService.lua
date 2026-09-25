--[[
	CheckpointService
	Server-side checkpoint progress. The client never tells the server it reached a checkpoint:
	InteractionService detects the player standing on the pad and calls Reach().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local LevelKit = require(script.Parent.Parent.Level.LevelKit)

local CheckpointService = {}

function CheckpointService:Init(services)
	self.Services = services
end

local function activateVisual(checkpoint)
	local element = checkpoint.Element
	if not element or element.Activated then
		return
	end
	element.Activated = true
	local pad = element.Part :: BasePart
	TweenService:Create(pad, TweenInfo.new(0.35), { Color = LevelKit.Colors.CheckpointActive }):Play()
	if element.Flag then
		element.Flag.Color = LevelKit.Colors.CheckpointActive
		element.Flag.Material = Enum.Material.Neon
	end
	-- one-shot burst, then the emitter is cleaned up
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 1, 0)
	attachment.Parent = pad
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(LevelKit.Colors.CheckpointActive)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(24)
	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

function CheckpointService:Reach(run, index: number, byPlayer: Player)
	if run.Ended or run.State ~= "Playing" then
		return
	end
	if index <= run.CheckpointIndex then
		return
	end
	local inst = run.Instance
	local checkpoint = inst.Checkpoints[index]
	if not checkpoint then
		return
	end
	local previousIndex = run.CheckpointIndex
	run.CheckpointIndex = index
	for i = previousIndex + 1, index do
		local cp = inst.Checkpoints[i]
		if cp then
			activateVisual(cp)
		end
	end

	for _, player in { run.Player, run.Partner } do
		if player then
			Net.Event("CheckpointReached"):FireClient(player, index, inst.CheckpointCount)
		end
	end

	-- small coin reward, first playthrough only (no farming by restarting)
	if run.FirstClear and not run.CheckpointsRewarded[index] then
		run.CheckpointsRewarded[index] = true
		self.Services.DataService:AddCoins(run.Player, Config.CHECKPOINT_REWARD)
	end

	-- some checkpoints change the doppelgänger's role (Level 10)
	if checkpoint.SetRole and not run.Partner then
		self.Services.RoleService:SetRole(run, checkpoint.SetRole, { Reveal = true, Checkpoint = index })
	end
	self.Services.DuoService:OnCheckpoint(run, index, byPlayer)
end

function CheckpointService:GetCheckpoint(run, index: number?)
	local inst = run.Instance
	return inst.Checkpoints[index or run.CheckpointIndex] or inst.Checkpoints[0]
end

-- Debug: jump to a checkpoint (activates it and moves the player + doppelgänger there).
function CheckpointService:TeleportTo(run, index: number)
	local inst = run.Instance
	index = math.clamp(index, 0, inst.CheckpointCount)
	if index > run.CheckpointIndex then
		self:Reach(run, index, run.Player)
	else
		run.CheckpointIndex = index
		for _, player in { run.Player, run.Partner } do
			if player then
				Net.Event("CheckpointReached"):FireClient(player, index, inst.CheckpointCount)
			end
		end
	end
	local checkpoint = self:GetCheckpoint(run, index)
	self.Services.CharacterService:Teleport(run.Player, checkpoint.SpawnCFrame)
	if run.Partner then
		self.Services.CharacterService:Teleport(run.Partner, checkpoint.DoppelCFrame)
	end
	self.Services.DoppelgangerService:OnPlayerRespawned(run)
end

return CheckpointService
