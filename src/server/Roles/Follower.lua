--[[
	Follower ("ECHO") - Level 1 / 3
	Walks in the player's exact footsteps, FOLLOW_DISTANCE studs behind.
	Because it uses the real trail it presses every button you walked over - a moment later.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RoleBase = require(script.Parent.RoleBase)

local Follower = RoleBase.Extend("Follower")
Follower.ReplaysPlayer = true

function Follower.new(ctx)
	local self = setmetatable(RoleBase.new(ctx), Follower)
	self.PlayT = nil
	self.Blocked = 0
	return self
end

function Follower:Start()
	self.PlayT = os.clock()
	self.Blocked = 0
end

function Follower:ResetPlayback()
	local recorder = self.Recorder
	local t = recorder and recorder:TimeAtDistanceBehind(Config.FOLLOW_DISTANCE)
	self.PlayT = t or os.clock()
	self.Blocked = 0
end

-- Shared trail-following step (also used by Ally / Troll while following).
function Follower:FollowStep(dt: number, now: number)
	local actor = self.Actor
	local recorder = self.Recorder
	local limitT = recorder:TimeAtDistanceBehind(Config.FOLLOW_DISTANCE)
	local target = now - Config.FOLLOW_DELAY
	if limitT then
		target = math.min(target, limitT)
	end
	local playT = self.PlayT or target
	if target <= playT then
		-- close enough: stand still, but keep checking ground (platform may vanish under us)
		actor:DriveTo(actor.Position, nil, actor.Grounded, { IgnoreBlockers = true })
		return
	end
	local lag = target - playT
	local rate = if lag > 0.8 then Config.FOLLOW_CATCHUP_MULTIPLIER else 1
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
	local result = actor:DriveTo(sample.Position, sample.Yaw, sample.Grounded)
	if result == "blocked" then
		self.Blocked += dt
		if self.Blocked > Config.FOLLOW_REGROUP_AFTER then
			self:Regroup()
		end
		return
	end
	self.Blocked = 0
	self.PlayT = nextT
	-- hopelessly behind (e.g. was stuck for long): regroup
	if now - nextT > 8 then
		self:Regroup()
	end
end

function Follower:Regroup()
	local cf = self:GetPositionNearPlayer()
	if cf then
		self.Actor:Glitch()
		self.Actor:Teleport(cf)
	end
	self:ResetPlayback()
end

function Follower:Update(dt: number, now: number)
	if not self.Actor:IsControllable() or not self.Run.AIEnabled then
		return
	end
	self:FollowStep(dt, now)
end

function Follower:OnPlayerRespawn(checkpoint)
	self.Actor:Respawn(checkpoint.DoppelCFrame)
	self.PlayT = os.clock()
	self.Blocked = 0
end

function Follower:GetRespawnCFrame(): CFrame
	return self:GetPositionNearPlayer() or self:GetCheckpoint().DoppelCFrame
end

function Follower:OnDoppelRespawned()
	self:ResetPlayback()
end

return Follower
