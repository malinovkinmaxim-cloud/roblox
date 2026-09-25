--[[
	DoppelActor
	The physical doppelgänger: a server-owned R15 rig driven kinematically.

	Why kinematic (AlignPosition, rigid) instead of Humanoid:MoveTo?
	  - the Shadow must copy the player's path EXACTLY (physics NPCs drift and miss jumps)
	  - no pathfinding, no stuck NPCs, cheap on the server
	  - physics replication interpolates it smoothly on clients
	It still interacts with the world for real:
	  - closed doors block it (blockcast against the level's Blockers)
	  - it falls when there is no ground (fake / vanished / moved platforms, misjumps)
	  - InteractionService treats it like any other actor (buttons, plates, lasers...)

	States: "Driven" (a role controls it) | "Falling" | "Airborne" (launch pad) | "Dead"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DoppelActor = {}
DoppelActor.__index = DoppelActor

local ANIMATIONS = {
	Idle = "rbxassetid://507766666",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
	Wave = "rbxassetid://507770239",
	Cheer = "rbxassetid://507770677",
	Point = "rbxassetid://507770453",
	Laugh = "rbxassetid://507770818",
}

local SNAP_DISTANCE = 12 -- bigger jumps between two targets are treated as teleports
local FOOT_BOX = Vector3.new(1.6, 0.4, 1.0)
local BODY_BOX = Vector3.new(1.3, 2.4, 1.3)

function DoppelActor.YawFromLook(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

--[[
	DoppelActor.new(model, inst, visuals)
	  model   : rig from Appearance (not parented yet)
	  inst    : level instance (ground / blocker params, kill height, actors folder)
	  visuals : table from Appearance.AddVisuals
]]
function DoppelActor.new(model: Model, inst, visuals)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	assert(root and humanoid, "doppel rig needs a HumanoidRootPart and a Humanoid")

	local self = setmetatable({
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Instance = inst,
		Visuals = visuals,
		State = "Driven",
		Position = root.Position,
		Yaw = 0,
		Velocity = Vector3.zero,
		Grounded = true,
		Ghost = false,
		Frozen = false,
		Destroyed = false,
		FallVelocity = Vector3.zero,
		DieOnLand = true,
		LandedAt = nil,
		LastMoveClock = os.clock(),
		LastStepPosition = root.Position,
		Emote = nil,
		Tracks = {},
		CurrentTrack = nil,
		CurrentTrackName = nil,
		PartTransparency = {},
		DecalTransparency = {},
		OnDied = nil, -- callback(cause)
		RootOffset = 3,
	}, DoppelActor)

	-- physics setup: nothing collides, only the root has mass
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = descendant ~= root
			descendant.CollisionGroup = "Doppel"
			self.PartTransparency[descendant] = descendant.Transparency
		elseif descendant:IsA("Decal") then
			self.DecalTransparency[descendant] = descendant.Transparency
		end
	end

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		self.RootOffset = 3
	else
		self.RootOffset = humanoid.HipHeight + root.Size.Y / 2
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		humanoid.EvaluateStateMachine = false
	end)

	local attachment = Instance.new("Attachment")
	attachment.Name = "DoppelDrive"
	attachment.Parent = root

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.RigidityEnabled = true
	alignPosition.Position = root.Position
	alignPosition.Parent = root
	self.AlignPosition = alignPosition

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.RigidityEnabled = true
	alignOrientation.CFrame = CFrame.new()
	alignOrientation.Parent = root
	self.AlignOrientation = alignOrientation

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	self.Animator = animator

	model.Parent = inst.Actors
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return self
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

function DoppelActor:IsAlive(): boolean
	return self.State ~= "Dead" and not self.Destroyed
end

-- A role may steer the actor only in this state.
function DoppelActor:IsControllable(): boolean
	return self.State == "Driven" and not self.Destroyed
end

function DoppelActor:GetFeetPosition(): Vector3
	return self.Position - Vector3.new(0, self.RootOffset, 0)
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

function DoppelActor:_apply(position: Vector3, yaw: number?)
	if yaw ~= nil then
		self.Yaw = yaw
	end
	self.Position = position
	self.AlignPosition.Position = position
	self.AlignOrientation.CFrame = CFrame.Angles(0, self.Yaw, 0)
end

-- Instantly place the rig (no interpolation through walls).
function DoppelActor:Teleport(cf: CFrame)
	if self.Destroyed then
		return
	end
	local position = cf.Position
	local yaw = DoppelActor.YawFromLook(cf.LookVector)
	self.Root.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	self.Root.AssemblyLinearVelocity = Vector3.zero
	self.Velocity = Vector3.zero
	self.LastStepPosition = position
	self:_apply(position, yaw)
	if self.State == "Falling" or self.State == "Airborne" then
		self.State = "Driven"
	end
	self.Grounded = true
end

-- narrow = a thin ray instead of the foot box (used to detect small gaps when planning a walk)
function DoppelActor:HasGroundAt(position: Vector3, extra: number?, narrow: boolean?): boolean
	local direction = Vector3.new(0, -(self.RootOffset + (extra or 1.3)), 0)
	if narrow then
		return workspace:Raycast(position, direction, self.Instance.GroundParams) ~= nil
	end
	local result = workspace:Blockcast(CFrame.new(position), FOOT_BOX, direction, self.Instance.GroundParams)
	return result ~= nil
end

function DoppelActor:IsBlocked(from: Vector3, to: Vector3): boolean
	local delta = to - from
	local distance = delta.Magnitude
	if distance < 0.01 then
		return false
	end
	local direction = delta.Unit * (distance + 0.4)
	local result = workspace:Blockcast(CFrame.new(from + Vector3.new(0, 0.3, 0)), BODY_BOX, direction, self.Instance.BlockerParams)
	return result ~= nil
end

--[[
	DriveTo(position, yaw, grounded, opts) -> "ok" | "blocked" | "fell" | "teleported" | "busy"
	  grounded = the target is supposed to be standing on something (checked -> falls if not)
	  opts.IgnoreBlockers, opts.NoGroundCheck
]]
function DoppelActor:DriveTo(position: Vector3, yaw: number?, grounded: boolean, opts: { [string]: any }?): string
	if self.State ~= "Driven" or self.Destroyed then
		return "busy"
	end
	local now = os.clock()
	local current = self.Position
	local delta = position - current
	local distance = delta.Magnitude

	if distance > SNAP_DISTANCE then
		self:Teleport(CFrame.new(position) * CFrame.Angles(0, yaw or self.Yaw, 0))
		self.LastMoveClock = now
		return "teleported"
	end

	if distance > 0.02 and not (opts and opts.IgnoreBlockers) then
		if self:IsBlocked(current, position) then
			self.Velocity = Vector3.zero
			return "blocked"
		end
	end

	local dt = math.max(now - self.LastMoveClock, 1 / 120)
	self.LastMoveClock = now
	local velocity = delta / dt

	if grounded and not (opts and opts.NoGroundCheck) then
		if not self:HasGroundAt(position) then
			self:_apply(position, yaw)
			self:StartFall(velocity)
			return "fell"
		end
	end

	self.Grounded = grounded
	self:_apply(position, yaw)
	return "ok"
end

-- Stand still (keeps animation state sane).
function DoppelActor:Hold()
	self.LastMoveClock = os.clock()
end

function DoppelActor:StartFall(velocity: Vector3?)
	if self.State == "Dead" then
		return
	end
	local v = velocity or Vector3.zero
	local horizontal = Vector3.new(v.X, 0, v.Z)
	local maxSpeed = Config.DOPPELGANGER_SPEED * 1.5
	if horizontal.Magnitude > maxSpeed then
		horizontal = horizontal.Unit * maxSpeed
	end
	self.FallVelocity = Vector3.new(horizontal.X, math.min(v.Y, 0), horizontal.Z)
	self.State = "Falling"
	self.DieOnLand = true
	self.LandedAt = nil
	self.Grounded = false
end

-- Launch pad (for AI roles; replaying roles copy the player's recorded arc instead).
function DoppelActor:Launch(velocity: Vector3)
	if self.State == "Dead" or self.Destroyed then
		return
	end
	self.FallVelocity = velocity
	self.State = "Airborne"
	self.DieOnLand = false
	self.LandedAt = nil
	self.Grounded = false
end

function DoppelActor:Step(dt: number, now: number)
	if self.Destroyed then
		return
	end
	if self.State == "Falling" or self.State == "Airborne" then
		self:_stepBallistic(dt, now)
	end
	-- velocity estimate for animations
	local moved = self.Position - self.LastStepPosition
	self.LastStepPosition = self.Position
	if dt > 0 then
		self.Velocity = self.Velocity:Lerp(moved / dt, math.clamp(dt * 12, 0, 1))
	end
	self:_updateAnimation()
end

function DoppelActor:_stepBallistic(dt: number, now: number)
	if self.LandedAt then
		-- landed after a fall: dazed for a moment, then gone
		if now - self.LandedAt > 0.45 then
			self:Die("Fell")
		end
		return
	end
	local velocity = self.FallVelocity - Vector3.new(0, Config.DOPPEL_GRAVITY * dt, 0)
	velocity = Vector3.new(velocity.X * 0.995, math.max(velocity.Y, -120), velocity.Z * 0.995)
	local nextPosition = self.Position + velocity * dt
	if velocity.Y < 0 then
		local result = workspace:Blockcast(
			CFrame.new(self.Position),
			FOOT_BOX,
			(nextPosition - self.Position) + Vector3.new(0, -self.RootOffset, 0),
			self.Instance.GroundParams
		)
		if result then
			local landY = result.Position.Y + self.RootOffset
			local landed = Vector3.new(nextPosition.X, math.max(landY, nextPosition.Y), nextPosition.Z)
			self:_apply(landed, nil)
			self.FallVelocity = Vector3.zero
			self.Grounded = true
			if self.DieOnLand then
				self.LandedAt = now
			else
				self.State = "Driven"
				self.LastMoveClock = now
			end
			return
		end
	end
	self.FallVelocity = velocity
	self:_apply(nextPosition, nil)
	if nextPosition.Y < self.Instance.KillY then
		self:Die("Fell")
	end
end

---------------------------------------------------------------------------
-- Life & death
---------------------------------------------------------------------------

local function burst(root: BasePart, color: Color3, amount: number)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(amount)
	task.delay(1.2, function()
		attachment:Destroy()
	end)
end

function DoppelActor:SetVisible(visible: boolean)
	for part, transparency in self.PartTransparency do
		if part.Parent then
			part.Transparency = if visible then transparency else 1
		end
	end
	for decal, transparency in self.DecalTransparency do
		if decal.Parent then
			decal.Transparency = if visible then transparency else 1
		end
	end
	local visuals = self.Visuals
	if visuals then
		visuals.Highlight.Enabled = visible
		visuals.Billboard.Enabled = visible
		if visuals.Aura then
			visuals.Aura.Enabled = visible
		end
	end
end

function DoppelActor:Die(cause: string)
	if self.State == "Dead" or self.Destroyed then
		return
	end
	self.State = "Dead"
	self.Frozen = false
	burst(self.Root, self:GetColor(), 30)
	self:SetVisible(false)
	self:_stopTracks()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/swoosh.wav"
	sound.Volume = 0.7
	sound.PlaybackSpeed = 0.7
	sound.Parent = self.Root
	sound:Play()
	task.delay(1.5, function()
		sound:Destroy()
	end)
	if self.OnDied then
		task.spawn(self.OnDied, cause)
	end
end

function DoppelActor:Respawn(cf: CFrame)
	if self.Destroyed then
		return
	end
	self.State = "Driven"
	self.Frozen = false
	self.LandedAt = nil
	self.Emote = nil
	self:Teleport(cf)
	self:SetVisible(true)
	self:_refreshFrozenVisual()
	burst(self.Root, self:GetColor(), 16)
end

-- Short visual glitch (used when a follower / shadow phases through or regroups).
function DoppelActor:Glitch()
	if self.Destroyed or self.State == "Dead" then
		return
	end
	burst(self.Root, self:GetColor(), 12)
	task.spawn(function()
		for i = 1, 4 do
			if self.Destroyed or self.State == "Dead" then
				return
			end
			self:SetVisible(i % 2 == 0)
			task.wait(0.05)
		end
		if not self.Destroyed and self.State ~= "Dead" then
			self:SetVisible(true)
		end
	end)
end

---------------------------------------------------------------------------
-- Visual state
---------------------------------------------------------------------------

function DoppelActor:GetColor(): Color3
	return self.RoleColor or Color3.fromRGB(110, 205, 255)
end

function DoppelActor:SetRoleDisplay(text: string, color: Color3)
	self.RoleColor = color
	local visuals = self.Visuals
	if not visuals then
		return
	end
	visuals.RoleLabel.Text = text
	visuals.RoleLabel.TextColor3 = color
	if not self.Frozen then
		visuals.Highlight.FillColor = color
		visuals.Highlight.OutlineColor = color
	end
	if visuals.Aura then
		visuals.Aura.Color = ColorSequence.new(color)
	end
end

-- Brief colour flash of the highlight (the Troll's tell).
function DoppelActor:FlashColor(color: Color3, duration: number)
	local visuals = self.Visuals
	if not visuals or self.Frozen then
		return
	end
	visuals.Highlight.OutlineColor = color
	visuals.Highlight.FillColor = color
	task.delay(duration, function()
		if not self.Destroyed and not self.Frozen then
			visuals.Highlight.OutlineColor = self:GetColor()
			visuals.Highlight.FillColor = self:GetColor()
		end
	end)
end

function DoppelActor:SetFrozen(frozen: boolean)
	self.Frozen = frozen
	self:_refreshFrozenVisual()
end

function DoppelActor:_refreshFrozenVisual()
	local visuals = self.Visuals
	if not visuals then
		return
	end
	if self.Frozen then
		local ice = Color3.fromRGB(170, 235, 255)
		visuals.Highlight.FillColor = ice
		visuals.Highlight.OutlineColor = ice
		visuals.Highlight.FillTransparency = 0.45
		visuals.NameLabel.Text = "FROZEN"
	else
		visuals.Highlight.FillColor = self:GetColor()
		visuals.Highlight.OutlineColor = self:GetColor()
		visuals.Highlight.FillTransparency = 0.82
		visuals.NameLabel.Text = "DOPPELGÄNGER"
	end
	if self.CurrentTrack then
		self.CurrentTrack:AdjustSpeed(if self.Frozen then 0 else 1)
	end
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------

function DoppelActor:_getTrack(name: string): AnimationTrack?
	local track = self.Tracks[name]
	if track == nil then
		local ok, result = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = ANIMATIONS[name]
			local loaded = self.Animator:LoadAnimation(animation)
			loaded.Looped = name ~= "Jump"
			loaded.Priority = if name == "Wave" or name == "Cheer" or name == "Point" or name == "Laugh"
				then Enum.AnimationPriority.Action
				else Enum.AnimationPriority.Core
			return loaded
		end)
		track = if ok then result else false
		self.Tracks[name] = track
	end
	return if track then track else nil
end

function DoppelActor:_play(name: string, speed: number?)
	if self.CurrentTrackName == name then
		if self.CurrentTrack and speed and not self.Frozen then
			self.CurrentTrack:AdjustSpeed(speed)
		end
		return
	end
	local track = self:_getTrack(name)
	if self.CurrentTrack then
		self.CurrentTrack:Stop(0.15)
	end
	self.CurrentTrackName = name
	self.CurrentTrack = track
	if track then
		track:Play(0.15)
		track:AdjustSpeed(if self.Frozen then 0 else (speed or 1))
	end
end

function DoppelActor:_stopTracks()
	for _, track in self.Tracks do
		if track then
			track:Stop(0)
		end
	end
	self.CurrentTrack = nil
	self.CurrentTrackName = nil
end

-- Emote overrides locomotion until cleared (nil).
function DoppelActor:SetEmote(name: string?)
	self.Emote = name
end

function DoppelActor:_updateAnimation()
	if self.State == "Dead" then
		return
	end
	if self.Emote then
		self:_play(self.Emote)
		return
	end
	if self.State == "Falling" or self.State == "Airborne" or not self.Grounded then
		if self.Velocity.Y > 2 then
			self:_play("Jump")
		else
			self:_play("Fall")
		end
		return
	end
	local horizontal = Vector3.new(self.Velocity.X, 0, self.Velocity.Z).Magnitude
	if horizontal > 1 then
		self:_play("Run", math.clamp(horizontal / 16, 0.4, 1.6))
	else
		self:_play("Idle")
	end
end

function DoppelActor:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.State = "Dead"
	self.OnDied = nil
	self.Model:Destroy()
end

return DoppelActor
