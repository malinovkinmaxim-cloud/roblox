--[[
	Ally - Phase 6
	Follows you like the Echo, but you can COMMAND it:
	  ABILITY (SEND)   : face a button / pressure plate / platform and press -> it glides there and holds it
	  INTERACT (RECALL): it comes back and follows you again
	Help is never automatic: the player has to figure out WHERE to send it.
	Sent onto a fake platform it falls instead of you ("tester").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Follower = require(script.Parent.Follower)
local RoleBase = require(script.Parent.RoleBase)
local DoppelActor = require(script.Parent.Parent.Doppelganger.DoppelActor)

local Ally = RoleBase.Extend("Ally", Follower)
Ally.ReplaysPlayer = true

function Ally.new(ctx)
	local self = setmetatable(Follower.new(ctx), Ally)
	self.Mode = "Follow" -- Follow | Travel | Hold | Return
	self.Travel = nil
	self.Target = nil
	self.HoldPosition = nil
	self.LastCommand = -math.huge
	self.Helped = false
	return self
end

function Ally:GetAbilityInfo()
	return { Ability = "SEND", Interact = "RECALL" }
end

function Ally:Start()
	Follower.Start(self)
	self.Mode = "Follow"
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

function Ally:FindTarget()
	local root = self:GetPlayerRoot()
	if not root then
		return nil
	end
	return self.Services.InteractionService:FindTargetInFront(self.Instance, root, Config.ALLY_SEND_RANGE, Config.ALLY_SEND_CONE)
end

function Ally:UseAbility(): (boolean, string?)
	local now = os.clock()
	if now - self.LastCommand < Config.ALLY_COOLDOWN then
		return false, nil
	end
	if not self.Actor:IsControllable() then
		return false, "Your doppelgänger is not here right now."
	end
	local target = self:FindTarget()
	if not target then
		return false, "Face a CYAN button, a plate or a platform, then SEND."
	end
	self.LastCommand = now
	self:SendTo(target)
	return true
end

function Ally:UseInteract(): (boolean, string?)
	if self.Mode == "Hold" or self.Mode == "Travel" then
		self:Recall()
		return true
	end
	return false, nil
end

local function standPosition(target, rootOffset: number): Vector3
	local part = target.Part :: BasePart
	return part.Position + Vector3.new(0, part.Size.Y / 2 + rootOffset, 0)
end

function Ally:SendTo(target)
	self.Target = target
	self:_travelTo(standPosition(target, self.Actor.RootOffset), "Hold")
	self.Actor:SetEmote(nil)
end

function Ally:Recall()
	local destination = self:GetPositionNearPlayer()
	if not destination then
		return
	end
	self.Target = nil
	self:_travelTo(destination.Position, "Return")
end

function Ally:_travelTo(destination: Vector3, thenMode: string)
	local from = self.Actor.Position
	local distance = (destination - from).Magnitude
	self.Travel = {
		From = from,
		To = destination,
		T = 0,
		Duration = math.max(0.45, distance / Config.ALLY_GLIDE_SPEED),
		Height = math.clamp(distance * 0.2, 2.5, 9),
		Then = thenMode,
		Yaw = DoppelActor.YawFromLook(Vector3.new(destination.X - from.X, 0, destination.Z - from.Z).Unit),
	}
	if (destination - from).Magnitude < 0.1 then
		self.Travel.Yaw = nil
	end
	self.Mode = "Travel"
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

function Ally:Update(dt: number, now: number)
	local actor = self.Actor
	if not actor:IsControllable() then
		return
	end
	if not self.Run.AIEnabled then
		actor:Hold()
		return
	end
	local mode = self.Mode
	if mode == "Follow" then
		self:FollowStep(dt, now)
	elseif mode == "Travel" then
		self:_stepTravel(dt, now)
	elseif mode == "Hold" then
		-- stand on the target; if it is a fake platform, the ground check makes it fall
		actor:DriveTo(self.HoldPosition or actor.Position, nil, true, { IgnoreBlockers = true })
	end
end

function Ally:_stepTravel(dt: number, now: number)
	local travel = self.Travel
	if not travel then
		self.Mode = "Follow"
		return
	end
	travel.T += dt
	local alpha = math.clamp(travel.T / travel.Duration, 0, 1)
	local flat = travel.From:Lerp(travel.To, alpha)
	local y = travel.From.Y + (travel.To.Y - travel.From.Y) * alpha + 4 * travel.Height * alpha * (1 - alpha)
	local arrived = alpha >= 1
	local result = self.Actor:DriveTo(Vector3.new(flat.X, y, flat.Z), travel.Yaw, arrived, { IgnoreBlockers = true })
	if result == "fell" then
		self.Travel = nil
		return
	end
	if arrived then
		self.Travel = nil
		self:_onArrived(travel.Then, now)
	end
end

function Ally:_onArrived(thenMode: string, _now: number)
	if thenMode == "Hold" then
		self.Mode = "Hold"
		self.HoldPosition = self.Actor.Position
		if not self.Helped then
			self.Helped = true
			self:Reveal()
		end
	else
		self.Mode = "Follow"
		self:ResetPlayback()
	end
end

---------------------------------------------------------------------------
-- Respawn
---------------------------------------------------------------------------

function Ally:OnPlayerRespawn(checkpoint)
	Follower.OnPlayerRespawn(self, checkpoint)
	self.Mode = "Follow"
	self.Travel = nil
	self.Target = nil
	self.Actor:SetEmote(nil)
end

function Ally:OnDoppelRespawned()
	Follower.OnDoppelRespawned(self)
	self.Mode = "Follow"
	self.Travel = nil
	self.Target = nil
	self.Actor:SetEmote(nil)
end

return Ally
