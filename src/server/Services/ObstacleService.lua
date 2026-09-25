--[[
	ObstacleService
	Drives every time-based obstacle of every active level from ONE Heartbeat connection:
	  - moving platforms (horizontal / vertical / circular / back-and-forth, optionally powered)
	  - blinking lasers and trap lasers
	  - disappearing platforms
	  - timed doors
	and applies power changes coming from InteractionService (doors, bridges, lasers, movers).
	Falling and fake platforms are triggered by InteractionService.

	No per-object loops, no per-object connections.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local LevelKit = require(script.Parent.Parent.Level.LevelKit)

local ObstacleService = {}
ObstacleService.Instances = {}

local DOOR_TWEEN = TweenInfo.new(Config.DOOR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function ObstacleService:Init(services)
	self.Services = services
end

function ObstacleService:Start()
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, inst in self.Instances do
			if not inst.Destroyed then
				local ok, err = pcall(self._step, self, inst, dt, now)
				if not ok then
					warn("[ObstacleService] step error: " .. tostring(err))
				end
			end
		end
	end)
end

function ObstacleService:Register(inst)
	table.insert(self.Instances, inst)
	-- initial state
	for _, laser in inst.Lasers do
		self:_applyLaser(laser, laser.On, os.clock(), true)
	end
end

function ObstacleService:Unregister(inst)
	local index = table.find(self.Instances, inst)
	if index then
		table.remove(self.Instances, index)
	end
end

---------------------------------------------------------------------------
-- Motion math (pure)
---------------------------------------------------------------------------

local function smooth(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha)
end

-- Position of a moving platform after `clock` seconds of (powered) movement.
function ObstacleService.MotionAt(basePosition: Vector3, motion, clock: number): Vector3
	if motion.Kind == "Circle" then
		local radius = motion.Radius or 8
		local angle = 2 * math.pi * clock / (motion.Period or 6)
		if motion.Reverse then
			angle = -angle
		end
		return basePosition + Vector3.new(math.cos(angle) * radius - radius, 0, math.sin(angle) * radius)
	end
	local period = motion.Period or 4
	local pause = math.min(motion.Pause or 0.5, period * 0.4)
	local travel = (period - 2 * pause) / 2
	local p = clock % period
	local alpha
	if p < pause then
		alpha = 0
	elseif p < pause + travel then
		alpha = (p - pause) / travel
	elseif p < 2 * pause + travel then
		alpha = 1
	else
		alpha = 1 - (p - 2 * pause - travel) / travel
	end
	return basePosition + (motion.Offset or Vector3.zero) * smooth(alpha)
end

-- (on, warning) for a cycle { On = , Off = , Phase = } at time t
local function cycleState(cycle, t: number, onKey: string, offKey: string, warnTime: number): (boolean, boolean)
	local onTime = cycle[onKey] or 1
	local offTime = cycle[offKey] or 1
	local period = onTime + offTime
	local p = (t + (cycle.Phase or 0)) % period
	local on = p < onTime
	local warning = (not on) and (period - p) < warnTime
	return on, warning
end

---------------------------------------------------------------------------
-- Heartbeat step
---------------------------------------------------------------------------

function ObstacleService:_step(inst, dt: number, now: number)
	local t = now - inst.StartClock

	-- moving platforms
	for _, mover in inst.Movers do
		if mover.Powered then
			mover.Clock += dt
		end
		mover.AlignPosition.Position = ObstacleService.MotionAt(mover.BaseCFrame.Position, mover.Motion, mover.Clock)
	end

	-- cyclic elements
	for _, element in inst.Cyclic do
		if element.Type == "Disappearing" then
			local visible, warning = cycleState(element.Cycle, t, "Visible", "Hidden", 0)
			-- blink during the last 0.6 s of the visible phase
			local cycle = element.Cycle
			local period = (cycle.Visible or 2) + (cycle.Hidden or 1.5)
			local p = (t + (cycle.Phase or 0)) % period
			local blinking = visible and ((cycle.Visible or 2) - p) < 0.6
			self:_applyVanish(element, visible, blinking, now)
			local _ = warning
		elseif element.Type == "Door" and element.Cycle then
			local open = cycleState(element.Cycle, t, "Open", "Closed", 0)
			if element.Powered then
				open = true
			end
			if open ~= element.Open then
				self:_moveDoor(element, open)
			end
		end
	end

	-- lasers
	for _, laser in inst.Lasers do
		local base, warning = true, false
		if laser.Spec.Cycle then
			base, warning = cycleState(laser.Spec.Cycle, t, "On", "Off", Config.LASER_WARNING)
		end
		local on
		if laser.Trap then
			on = laser.Powered and base
			if on and not laser.On then
				-- trap: flicker as a warning before it becomes solid
				if not laser.PendingOn then
					laser.PendingOn = now + Config.TRAP_WARNING
				end
				if now < laser.PendingOn then
					on = false
					warning = true
				end
			end
			if not laser.Powered then
				laser.PendingOn = nil
			end
		else
			on = base and not laser.Powered
			if laser.Powered then
				warning = false
			end
		end
		if on ~= laser.On then
			if on then
				laser.PendingOn = nil
			end
			self:_applyLaser(laser, on, now, false)
		end
		self:_laserWarning(laser, (not on) and warning, now)
	end
end

---------------------------------------------------------------------------
-- Visual / physical state changes
---------------------------------------------------------------------------

function ObstacleService:_applyLaser(laser, on: boolean, now: number, initial: boolean)
	laser.On = on
	local part = laser.Part :: BasePart
	if on then
		laser.LethalAt = if initial then now else now + Config.HAZARD_GRACE
		part.Transparency = 0.1
	else
		part.Transparency = 0.92
	end
end

function ObstacleService:_laserWarning(laser, warning: boolean, now: number)
	laser.Warning = warning
	if laser.On then
		return
	end
	local part = laser.Part :: BasePart
	if warning then
		local flicker = math.floor(now * 12) % 2 == 0
		part.Transparency = if flicker then 0.45 else 0.85
	elseif part.Transparency ~= 0.92 then
		part.Transparency = 0.92
	end
end

function ObstacleService:_applyVanish(element, visible: boolean, blinking: boolean, now: number)
	local part = element.Part :: BasePart
	if visible ~= element.Visible then
		element.Visible = visible
		part.CanCollide = visible
		part.Transparency = if visible then 0 else 0.85
	end
	if visible then
		if blinking then
			part.Transparency = if math.floor(now * 10) % 2 == 0 then 0 else 0.45
			element.Blinking = true
		elseif element.Blinking then
			element.Blinking = false
			part.Transparency = 0
		end
	end
end

function ObstacleService:_moveDoor(element, open: boolean)
	element.Open = open
	local part = element.Part :: BasePart
	if element.Tween then
		element.Tween:Cancel()
	end
	local tween = TweenService:Create(part, DOOR_TWEEN, { CFrame = if open then element.OpenCFrame else element.ClosedCFrame })
	element.Tween = tween
	tween:Play()
end

-- Called by InteractionService when the sources linked to a target change.
function ObstacleService:SetPowered(inst, target: any, powered: boolean)
	local kind: string = target.Type
	if kind == "Door" then
		if target.Powered == powered then
			return
		end
		target.Powered = powered
		if target.Cycle then
			if powered and not target.Open then
				self:_moveDoor(target, true)
			end
		else
			self:_moveDoor(target, powered)
		end
	elseif kind == "Laser" then
		target.Powered = powered
	elseif kind == "MovingPlatform" then
		if target.RequiresPower then
			target.Powered = powered
		end
	end
	local _ = inst
end

function ObstacleService:TriggerFalling(inst, element)
	if element.Triggered then
		return
	end
	element.Triggered = true
	local part = element.Part :: BasePart
	local base = element.BaseCFrame
	task.spawn(function()
		-- shake
		local shakeEnd = os.clock() + Config.FALLING_PLATFORM_DELAY
		while os.clock() < shakeEnd and not inst.Destroyed do
			part.CFrame = base * CFrame.new((math.random() - 0.5) * 0.3, 0, (math.random() - 0.5) * 0.3)
			task.wait(0.05)
		end
		if inst.Destroyed then
			return
		end
		part.CFrame = base
		part.CanCollide = false
		TweenService:Create(part, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = base - Vector3.new(0, 12, 0),
			Transparency = 1,
		}):Play()
		task.wait(Config.FALLING_PLATFORM_RESPAWN)
		if inst.Destroyed then
			return
		end
		part.CFrame = base
		part.Transparency = 0
		part.CanCollide = true
		element.Triggered = false
	end)
end

function ObstacleService:CollapseFake(inst, element)
	if element.Revealed or not element.IsFake then
		return
	end
	element.Revealed = true
	local part = element.Part :: BasePart
	part.CanCollide = false
	part.Material = Enum.Material.ForceField
	part.Color = LevelKit.Colors.Kill
	part.Transparency = 0.2
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/snap.mp3"
	sound.Volume = 0.8
	sound.Parent = part
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)
	local _ = inst
end

-- The Troll can stand on fake platforms without breaking them - but they flicker. That's the tell.
function ObstacleService:GhostShimmer(element, now: number)
	if element.Revealed then
		return
	end
	if element.LastShimmer and now - element.LastShimmer < 0.5 then
		return
	end
	element.LastShimmer = now
	local part = element.Part :: BasePart
	part.Transparency = 0.4
	task.delay(0.12, function()
		if not element.Revealed and part.Parent then
			part.Transparency = 0
		end
	end)
end

-- Seconds a vanishing platform stays visible from now (0 when hidden). Other elements: huge.
function ObstacleService:VisibleRemaining(inst, element): number
	if not element or element.Type ~= "Disappearing" then
		return math.huge
	end
	local cycle = element.Cycle
	local visible = cycle.Visible or 2
	local period = visible + (cycle.Hidden or 1.5)
	local p = (os.clock() - inst.StartClock + (cycle.Phase or 0)) % period
	if p < visible then
		return visible - p
	end
	return 0
end

-- Is there solid ground at a node attached to a platform? (used by AI)
function ObstacleService:IsElementSolid(element): boolean
	if not element then
		return true
	end
	if element.Type == "Fake" then
		return not element.Revealed
	elseif element.Type == "Disappearing" then
		return element.Visible
	elseif element.Type == "Falling" then
		return not element.Triggered
	end
	return true
end

return ObstacleService
