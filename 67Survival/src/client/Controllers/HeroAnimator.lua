--[[
	HeroAnimator - brings the hero models to life on every client.

	Every character has a HeroJoint (Motor6D, HumanoidRootPart -> HeroRoot, built by the
	server's CharacterManager). Setting HeroJoint.Transform each frame animates the whole
	hero without touching physics:
	  * walking: a bouncy bob + a lean into the movement direction
	  * idle: slow breathing
	  * emotes (character attributes Emote / EmoteAt, played from the lobby)
	Readability: the local hero gets a thin white outline (Highlight) that stays visible
	through the horde, plus the glowing ring under its feet (part of the model).
	Also animates name tag effects (rainbow / glitch) and the lobby hero showcase.

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

function HeroAnimator:AnimateCharacter(character: Model, dt: number, now: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local joint = root and root:FindFirstChild("HeroJoint") :: Motor6D?
	if not root or not joint then
		return
	end
	local phase = self.Phase[character]
	if not phase then
		phase = { T = math.random() * 6, Lean = 0, Side = 0 }
		self.Phase[character] = phase
	end
	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local cf
	local emote = character:GetAttribute("Emote")
	local emoteAt = character:GetAttribute("EmoteAt")
	local emoteT = if type(emoteAt) == "number" then Workspace:GetServerTimeNow() - emoteAt else math.huge
	if type(emote) == "string" and emoteT >= 0 and emoteT < EMOTE_TIME and speed < 2 then
		cf = HeroAnimator.Pose(emote, emoteT)
	elseif speed > 1 then
		phase.T += dt * (8 + speed * 0.25)
		-- lean into the movement (in root space)
		local localVel = root.CFrame:VectorToObjectSpace(flat)
		local lean = math.clamp(-localVel.Z / 40, -0.25, 0.25)
		local side = math.clamp(localVel.X / 50, -0.2, 0.2)
		phase.Lean += (lean - phase.Lean) * math.min(1, dt * 10)
		phase.Side += (side - phase.Side) * math.min(1, dt * 10)
		cf = CFrame.new(0, abs(sin(phase.T)) * 0.45, 0) * CFrame.Angles(-phase.Lean, 0, -phase.Side + sin(phase.T) * 0.06)
	else
		phase.Lean *= math.max(0, 1 - dt * 8)
		phase.Side *= math.max(0, 1 - dt * 8)
		cf = CFrame.new(0, sin(now * 2.2 + phase.T) * 0.06, 0) * CFrame.Angles(-phase.Lean, 0, -phase.Side)
	end
	joint.Transform = cf
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
		-- lobby showcase heroes turn slowly
		local showcase = self.Showcase
		if showcase then
			for i, entry in showcase do
				local model = entry.Model
				if model.Parent then
					model:PivotTo(entry.Base * CFrame.new(0, sin(now * 2 + i) * 0.15, 0) * CFrame.Angles(0, sin(now * 0.6 + i) * 0.5, 0))
				end
			end
		end
	end
end

function HeroAnimator:Start()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map", 30)
		if not map then
			return
		end
		task.wait(1)
		local list = {}
		for _, d in map:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("Showcase") then
				table.insert(list, { Model = d, Base = d:GetPivot() })
			end
		end
		self.Showcase = list
	end)
	RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

return HeroAnimator
