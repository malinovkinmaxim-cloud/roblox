--[[
	RoleBase
	Every role module (Follower, Rival, Shadow, Ally, Troll) extends this.

	Contract (called by DoppelgangerService / RoleService):
	  Name, Description, Difficulty
	  .new(ctx)                  ctx = { Run, Actor, Recorder, Services, Rng, Reveal(), Status(key, text), Toast(text) }
	  :Start()                   role becomes active (actor already exists)
	  :Update(dt, now)           every Heartbeat while the run is active
	  :Stop()                    role is replaced / run finished
	  :OnPlayerRespawn(cp)       player respawned at checkpoint `cp` -> put the doppel in a sane place
	  :GetRespawnCFrame()        where the doppel re-forms after its own death
	  :OnDoppelRespawned()
	  :UseAbility() / :UseInteract()   -> (ok, message?)
	  :GetAbilityInfo()          -> { Ability = "FREEZE"?, Interact = "RELEASE"? }
	  :OnSourcePressed(source, presser)
	  :OnReachFinish()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoleConfig = require(ReplicatedStorage.Shared.RoleConfig)

local RoleBase = {}
RoleBase.__index = RoleBase
RoleBase.Name = "Base"
RoleBase.Description = ""
RoleBase.Difficulty = 0
RoleBase.ReplaysPlayer = false -- true: position comes from the player's recording (skip launch/teleport pads)

function RoleBase.new(ctx)
	local self = setmetatable({}, RoleBase)
	self.Ctx = ctx
	self.Run = ctx.Run
	self.Actor = ctx.Actor
	self.Recorder = ctx.Recorder
	self.Services = ctx.Services
	self.Instance = ctx.Run.Instance
	self.Def = ctx.Run.Def
	self.Rng = ctx.Rng or Random.new()
	self.Stopped = false
	return self
end

-- Inherit helper: local Shadow = RoleBase.Extend("Shadow")
function RoleBase.Extend(name: string, parent: any?)
	local base = parent or RoleBase
	local class = setmetatable({}, { __index = base })
	class.__index = class
	class.Name = name
	local info = RoleConfig.Get(name)
	if info then
		class.Description = info.Description
		class.Difficulty = info.Difficulty
	end
	return class
end

function RoleBase:Start() end

function RoleBase:Update(_dt: number, _now: number) end

function RoleBase:Stop()
	self.Stopped = true
	if self.Actor and not self.Actor.Destroyed then
		self.Actor:SetFrozen(false)
		self.Actor:SetEmote(nil)
		self.Actor.Ghost = false
	end
end

function RoleBase:GetCheckpoint()
	local inst = self.Instance
	return inst.Checkpoints[self.Run.CheckpointIndex] or inst.Checkpoints[0]
end

function RoleBase:OnPlayerRespawn(checkpoint)
	self.Actor:Respawn(checkpoint.DoppelCFrame)
end

function RoleBase:GetRespawnCFrame(): CFrame
	return self:GetCheckpoint().DoppelCFrame
end

function RoleBase:OnDoppelRespawned() end

function RoleBase:UseAbility(): (boolean, string?)
	return false, nil
end

function RoleBase:UseInteract(): (boolean, string?)
	return false, nil
end

function RoleBase:GetAbilityInfo()
	return { Ability = nil, Interact = nil }
end

function RoleBase:OnSourcePressed(_source, _presser) end

function RoleBase:OnReachFinish() end

-- Living player root (or nil)
function RoleBase:GetPlayerRoot(): (BasePart?, number)
	local root, _, offset = self.Services.CharacterService:GetLiving(self.Run.Player)
	return root, offset
end

-- Latest recorded point (at or before time t) where the doppel can stand on solid ground.
-- Returns (CFrame, snapshotTime) or nil. offset = lane offset (SPLIT).
function RoleBase:FindSafeTrailPoint(t: number, offset: Vector3?)
	local recorder = self.Recorder
	if not recorder then
		return nil
	end
	local shift = offset or Vector3.zero
	local actor = self.Actor
	local snapshot = recorder:FindBefore(t, function(s)
		return s.Grounded and actor:HasGroundAt(s.Position + shift)
	end, 45)
	if snapshot then
		return CFrame.new(snapshot.Position + shift) * CFrame.Angles(0, snapshot.Yaw, 0), snapshot.T
	end
	return nil
end

-- Position a few studs behind the player, for regrouping / respawning next to them.
function RoleBase:GetPositionNearPlayer(): CFrame?
	local recorder = self.Recorder
	if recorder then
		local t = recorder:TimeAtDistanceBehind(4)
		local sample = t and recorder:Sample(t)
		if sample then
			return CFrame.new(sample.Position) * CFrame.Angles(0, sample.Yaw, 0)
		end
	end
	local root = self:GetPlayerRoot()
	if root then
		local back = root.CFrame * CFrame.new(0, 0, 4)
		return CFrame.new(back.Position) * root.CFrame.Rotation
	end
	return nil
end

function RoleBase:Reveal()
	if self.Ctx.Reveal then
		self.Ctx.Reveal()
	end
end

function RoleBase:SetStatus(key: string?, text: string?)
	if self.Ctx.Status then
		self.Ctx.Status(key, text)
	end
end

function RoleBase:Toast(text: string, kind: string?)
	if self.Ctx.Toast then
		self.Ctx.Toast(text, kind)
	end
end

return RoleBase
