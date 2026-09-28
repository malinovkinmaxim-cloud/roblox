--[[
	HeroAnimator - brings the hero models to life on every client.

	Every character has a HeroJoint (Motor6D, HumanoidRootPart -> HeroRoot, built by the
	server's CharacterManager) and one Motor6D per arm / leg (HeroRoot -> limb, "LimbArmL"...).
	Setting their Transform each frame animates the hero without touching physics:
	  * walking: a light bob, a lean into the movement, legs and arms swinging in step
	  * idle: slow breathing, arms resting
	  * emotes (character attributes Emote / EmoteAt, played from the lobby) with arm poses:
	    a real wave, flexing, the 6 7 hands...
	Readability: the local hero gets a thin white outline (Highlight) that stays visible
	through the horde, plus the glowing ring under its feet (part of the model).
	Also animates name tag effects (rainbow / glitch).

	HeroAnimator.Pose(style, t) is shared with the victory screen (ResultsController).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HeroAnimator = {}

local EMOTE_TIME = 2.6
local sin, abs = math.sin, math.abs

function HeroAnimator:Init(controllers)
	self.C = controllers
	self.Phase = {}
end

-- an emote / victory pose at time t (seconds): CFrame relative to the hero root
function HeroAnimator.Pose(style: string, t: number): CFrame
	if style == "Wave" then
		return CFrame.Angles(0, 0, sin(t * 9) * 0.22)
	elseif style == "Jump" then
		return CFrame.new(0, abs(sin(t * 7)) * 2.2, 0)
	elseif style == "Dance" then
		return CFrame.new(sin(t * 6) * 0.6, abs(sin(t * 12)) * 0.5, 0) * CFrame.Angles(0, sin(t * 3) * 0.8, sin(t * 6) * 0.25)
	elseif style == "Flex" then
		local k = math.min(1, t * 3)
		return CFrame.new(0, 0.3 * k, 0) * CFrame.Angles(-0.25 * k, 0, sin(t * 14) * 0.04 * k)
	elseif style == "Spin" then
		return CFrame.new(0, abs(sin(t * 4)) * 0.8, 0) * CFrame.Angles(0, t * 11, 0)
	elseif style == "SixSeven" then
		-- six (left), seven (right), in rhythm
		local beat = math.floor(t * 3) % 2
		local side = if beat == 0 then 1 else -1
		return CFrame.new(side * 0.4, abs(sin(t * math.pi * 3)) * 0.9, 0) * CFrame.Angles(0, side * 0.35, side * 0.3)
	end
	return CFrame.new()
end

local function outline(self, character: Model, run: boolean)
	local hero = character:FindFirstChild("HeroModel")
	local h = character:FindFirstChild("HeroOutline") :: Highlight?
	if not hero then
		return
	end
	if not h then
		h = Instance.new("Highlight")
		h.Name = "HeroOutline"
		h.FillTransparency = 1
		h.OutlineColor = Color3.fromRGB(255, 255, 255)
		h.Parent = character
	end
	if h.Adornee ~= hero then
		h.Adornee = hero
	end
	h.OutlineTransparency = if run then 0.15 else 0.6
	h.DepthMode = if run then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
end

local ang = CFrame.Angles
local IDENTITY = CFrame.identity

-- arm / leg poses of an emote at time t (limb name -> rotation around its joint)
function HeroAnimator.LimbPose(style: string, t: number): { [string]: CFrame }
	if style == "Wave" then
		return { ArmR = ang(0, 0, 2.5 + sin(t * 10) * 0.35), ArmL = ang(0, 0, -0.15) }
	elseif style == "Jump" then
		local up = abs(sin(t * 7))
		return { ArmL = ang(0, 0, -0.4 - up * 2.2), ArmR = ang(0, 0, 0.4 + up * 2.2), LegL = ang(up * 0.5, 0, 0), LegR = ang(up * 0.5, 0, 0) }
	elseif style == "Dance" then
		local s = sin(t * 6)
		return { ArmL = ang(0, 0, -1.3 - s * 0.9), ArmR = ang(0, 0, 1.3 - s * 0.9), LegL = ang(s * 0.3, 0, 0), LegR = ang(-s * 0.3, 0, 0) }
	elseif style == "Flex" then
		local k = math.min(1, t * 3)
		return { ArmL = ang(0.3 * k, 0, -2.0 * k), ArmR = ang(0.3 * k, 0, 2.0 * k) }
	elseif style == "Spin" then
		return { ArmL = ang(0, 0, -1.5), ArmR = ang(0, 0, 1.5) }
	elseif style == "SixSeven" then
		-- the 6 7 hands: forearms forward, palms up, weighing six against seven
		local d = sin(t * math.pi * 3) * 0.4
		return { ArmL = ang(1.35 + d, 0, 0), ArmR = ang(1.35 - d, 0, 0) }
	end
	return {}
end

-- the Motor6Ds of a hero's arms and legs (rebuilt when the hero model is rebuilt)
local function limbMotors(phase, character: Model)
	local hero = character:FindFirstChild("HeroModel")
	if phase.Hero ~= hero then
		phase.Hero = hero
		phase.Motors = {}
		phase.Spins = {}
		local heroRoot = hero and hero:FindFirstChild("HeroRoot")
		if heroRoot then
			for _, name in { "ArmL", "ArmR", "LegL", "LegR" } do
				local motor = heroRoot:FindFirstChild("Limb" .. name)
				if motor and motor:IsA("Motor6D") then
					phase.Motors[name] = motor
				end
			end
			-- spinning hat parts (propeller blades, orbiting sparks)
			for _, motor in heroRoot:GetChildren() do
				if motor:IsA("Motor6D") and string.sub(motor.Name, 1, 4) == "Spin" then
					table.insert(phase.Spins, motor)
				end
			end
		end
	end
	return phase.Motors
end

function HeroAnimator:AnimateCharacter(character: Model, dt: number, now: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local joint = root and root:FindFirstChild("HeroJoint") :: Motor6D?
	if not root or not joint then
		return
	end
	local phase = self.Phase[character]
	if not phase then
		phase = { T = math.random() * 6, Lean = 0, Side = 0, Swing = 0 }
		self.Phase[character] = phase
	end
	local motors = limbMotors(phase, character)
	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local cf
	local limbs: { [string]: CFrame } = {}
	local emote = character:GetAttribute("Emote")
	local emoteAt = character:GetAttribute("EmoteAt")
	local emoteT = if type(emoteAt) == "number" then Workspace:GetServerTimeNow() - emoteAt else math.huge
	if type(emote) == "string" and emoteT >= 0 and emoteT < EMOTE_TIME and speed < 2 then
		cf = HeroAnimator.Pose(emote, emoteT)
		limbs = HeroAnimator.LimbPose(emote, emoteT)
		phase.Swing = 0
	elseif speed > 1 then
		phase.T += dt * (8 + speed * 0.25)
		-- lean into the movement (in root space)
		local localVel = root.CFrame:VectorToObjectSpace(flat)
		local lean = math.clamp(-localVel.Z / 40, -0.25, 0.25)
		local side = math.clamp(localVel.X / 50, -0.2, 0.2)
		phase.Lean += (lean - phase.Lean) * math.min(1, dt * 10)
		phase.Side += (side - phase.Side) * math.min(1, dt * 10)
		phase.Swing += (math.clamp(speed / 16, 0.45, 1) - phase.Swing) * math.min(1, dt * 8)
		cf = CFrame.new(0, abs(sin(phase.T)) * 0.28, 0) * CFrame.Angles(-phase.Lean, 0, -phase.Side + sin(phase.T) * 0.05)
		local s = sin(phase.T) * phase.Swing
		limbs.LegL = ang(s * 0.62, 0, 0)
		limbs.LegR = ang(-s * 0.62, 0, 0)
		limbs.ArmL = ang(-s * 0.48, 0, 0)
		limbs.ArmR = ang(s * 0.48, 0, 0)
	else
		phase.Lean *= math.max(0, 1 - dt * 8)
		phase.Side *= math.max(0, 1 - dt * 8)
		phase.Swing *= math.max(0, 1 - dt * 6)
		local breath = sin(now * 2.2 + phase.T)
		cf = CFrame.new(0, breath * 0.05, 0) * CFrame.Angles(-phase.Lean, 0, -phase.Side)
		-- arms rest and breathe; a walk that just ended settles out
		local s = sin(phase.T) * phase.Swing
		limbs.ArmL = ang(-s * 0.48, 0, -0.03 - breath * 0.03)
		limbs.ArmR = ang(s * 0.48, 0, 0.03 + breath * 0.03)
		limbs.LegL = ang(s * 0.62, 0, 0)
		limbs.LegR = ang(-s * 0.62, 0, 0)
	end
	joint.Transform = cf
	for name, motor in motors do
		motor.Transform = limbs[name] or IDENTITY
	end
	for _, motor in phase.Spins or {} do
		motor.Transform = CFrame.Angles(0, now * (motor:GetAttribute("Speed") or 6), 0)
	end
end

-- rainbow / glitch name tags
local function nameEffects(now: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local tag = root and root:FindFirstChild("HeroTag")
		if tag then
			local effect = tag:GetAttribute("NameEffect")
			local label = tag:FindFirstChild("PlayerName") :: TextLabel?
			if label and effect == "Rainbow" then
				label.TextColor3 = Color3.fromHSV((now * 0.3) % 1, 0.65, 1)
			elseif label and effect == "Glitch" then
				label.TextColor3 = if math.random() < 0.08 then Color3.fromRGB(255, 0, 200) else Color3.fromRGB(0, 255, 210)
				label.Position = if math.random() < 0.05 then UDim2.fromOffset(math.random(-3, 3), 0) else UDim2.new()
			end
		end
	end
end

function HeroAnimator:Update(dt: number)
	local now = os.clock()
	local inRun = self.C.RunClient.Active
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			self:AnimateCharacter(character, dt, now)
			if player == Players.LocalPlayer then
				outline(self, character, inRun)
			end
		end
	end
	for character in self.Phase do
		if not character.Parent then
			self.Phase[character] = nil
		end
	end
	if not inRun then
		nameEffects(now)
	end
end

function HeroAnimator:Start()
	RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

return HeroAnimator
