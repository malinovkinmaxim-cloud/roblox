--[[
	Shadow - Level 5+
	Replays the player's recorded movement ShadowDelay seconds later (Config.SHADOW_DELAY,
	levels can override with ShadowDelay). It really exists in the world:
	  - walks over the same buttons / plates -> presses them later
	  - walks into lasers that turned on since -> dies
	  - stands on platforms that vanished since -> falls
	  - closed doors stop it; when they open it catches up (or phases through after a while)

	Level options:
	  ShadowDelay  = 1.5
	  ShadowOffset = Vector3.new(0, 0, -24)  -- SPLIT: mirrors you on a parallel lane
	  ShadowPhase  = false                   -- never phase through closed doors
	  AllowFreeze  = true                    -- ABILITY: freeze the shadow in place
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RoleBase = require(script.Parent.RoleBase)

local Shadow = RoleBase.Extend("Shadow")
Shadow.ReplaysPlayer = true

function Shadow.new(ctx)
	local self = setmetatable(RoleBase.new(ctx), Shadow)
	self.Delay = self.Def.ShadowDelay or Config.SHADOW_DELAY
	self.Offset = self.Def.ShadowOffset or Vector3.zero
	self.CanPhase = self.Def.ShadowPhase ~= false
	self.PlayT = nil
	self.Blocked = 0
	self.FrozenUntil = 0
	self.LastFreeze = -math.huge
	return self
end

function Shadow:Start()
	self.PlayT = os.clock() - self.Delay
	self.Blocked = 0
	self:_sendAbilityState()
end

function Shadow:Stop()
	RoleBase.Stop(self)
	self.FrozenUntil = 0
end

function Shadow:Update(dt: number, now: number)
	local actor = self.Actor
	if not actor:IsControllable() then
		return
	end
	if actor.Frozen then
		if now >= self.FrozenUntil then
			self:SetFrozen(false)
		else
			-- frozen: stays put, still checks that it's standing on something
			actor:DriveTo(actor.Position, nil, actor.Grounded, { IgnoreBlockers = true })
			return
		end
	end
	if not self.Run.AIEnabled then
		actor:Hold()
		return
	end

	local recorder = self.Recorder
	local target = now - self.Delay
	local playT = math.min(self.PlayT or target, target)
	local lag = target - playT
	local rate = if lag > 0.1 then Config.SHADOW_CATCHUP_MULTIPLIER else 1
	local nextT = math.min(target, playT + dt * rate)
	local oldest = recorder:Oldest()
	if oldest and nextT < oldest.T then
		nextT = oldest.T
	end

	local sample = recorder:Sample(nextT)
	if not sample then
		self.PlayT = nextT
		actor:Hold()
		return
	end

	local result = actor:DriveTo(sample.Position + self.Offset, sample.Yaw, sample.Grounded)
	if result == "blocked" then
		self.Blocked += dt
		if self.CanPhase and self.Blocked > Config.SHADOW_PHASE_AFTER then
			self:_phase(target)
		end
		return
	end
	self.Blocked = 0
	self.PlayT = nextT
end

-- Skip ahead through whatever blocks us (visible glitch so it never feels like a bug).
function Shadow:_phase(target: number)
	self.Blocked = 0
	local sample = self.Recorder:Sample(target)
	if sample then
		self.Actor:Glitch()
		self.Actor:Teleport(CFrame.new(sample.Position + self.Offset) * CFrame.Angles(0, sample.Yaw, 0))
		self.PlayT = target
	end
end

---------------------------------------------------------------------------
-- FREEZE ability
---------------------------------------------------------------------------

function Shadow:GetAbilityInfo()
	if self.Def.AllowFreeze then
		return { Ability = "FREEZE", Interact = "RELEASE" }
	end
	return { Ability = nil, Interact = nil }
end

function Shadow:SetFrozen(frozen: boolean)
	if self.Actor.Frozen == frozen then
		return
	end
	self.Actor:SetFrozen(frozen)
	if not frozen then
		self.FrozenUntil = 0
	end
	self:_sendAbilityState()
end

function Shadow:_sendAbilityState()
	local player = self.Run.Player
	if not player.Parent then
		return
	end
	local remaining = math.max(0, self.FrozenUntil - os.clock())
	Net.Event("AbilityState"):FireClient(player, {
		Frozen = self.Actor.Frozen,
		FrozenUntil = if self.Actor.Frozen then Workspace:GetServerTimeNow() + remaining else nil,
		Duration = Config.FREEZE_DURATION,
		Cooldown = Config.FREEZE_COOLDOWN,
	})
end

function Shadow:UseAbility(): (boolean, string?)
	if not self.Def.AllowFreeze then
		return false, "Your shadow can't be frozen on this level."
	end
	local actor = self.Actor
	if actor.Frozen then
		self:SetFrozen(false)
		return true
	end
	local now = os.clock()
	if now - self.LastFreeze < Config.FREEZE_COOLDOWN then
		return false, nil
	end
	if not actor:IsControllable() then
		return false, "Your shadow is not here right now."
	end
	self.LastFreeze = now
	self.FrozenUntil = now + Config.FREEZE_DURATION
	self:SetFrozen(true)
	self.Services.DataService:IncrementStat(self.Run.Player, "Freezes", 1)
	return true
end

function Shadow:UseInteract(): (boolean, string?)
	if self.Actor.Frozen then
		self:SetFrozen(false)
		return true
	end
	return false, nil
end

---------------------------------------------------------------------------
-- Respawn handling
---------------------------------------------------------------------------

function Shadow:OnPlayerRespawn(checkpoint)
	self:SetFrozen(false)
	-- the shadow re-forms exactly where you appear (plus lane offset)
	local spawn = checkpoint.SpawnCFrame + self.Offset
	self.Actor:Respawn(spawn)
	self.PlayT = os.clock()
	self.Blocked = 0
end

function Shadow:GetRespawnCFrame(): CFrame
	local sample = self.Recorder:Sample(os.clock() - self.Delay)
	if sample then
		return CFrame.new(sample.Position + self.Offset) * CFrame.Angles(0, sample.Yaw, 0)
	end
	return self:GetCheckpoint().SpawnCFrame + self.Offset
end

function Shadow:OnDoppelRespawned()
	self.PlayT = os.clock() - self.Delay
	self.Blocked = 0
	self:SetFrozen(false)
end

return Shadow
