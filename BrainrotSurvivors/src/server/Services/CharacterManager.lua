--[[
	CharacterManager - Roblox characters: spawning in the lobby / arena, collision groups
	(players never push each other), the selected survivor's look (a small accessory made
	of parts), name tags and purchased trails, walk speed.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Shared.GameConfig)
local MetaData = require(Shared.MetaData)

local CharacterManager = {}

local GROUP = "Survivors"
local rgb = Color3.fromRGB

function CharacterManager:Init(services)
	self.Services = services
	Players.CharacterAutoLoads = false
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)
end

local function weld(part: BasePart, to: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = to
	w.Parent = part
end

local function deco(name: string, size: Vector3, color: Color3, head: BasePart, offset: CFrame, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = head.CFrame * offset
	weld(p, head)
	return p
end

-- the survivor look: a few welded parts on the head
function CharacterManager:ApplyLook(character: Model, key: string)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local old = character:FindFirstChild("SurvivorLook")
	if old then
		old:Destroy()
	end
	local look = Instance.new("Model")
	look.Name = "SurvivorLook"
	look.Parent = character
	local function add(p: BasePart)
		p.Parent = look
	end
	if key == "Sigma" then
		add(deco("Shades", Vector3.new(1.3, 0.3, 0.2), rgb(15, 15, 20), head, CFrame.new(0, 0.15, -0.6)))
		add(deco("Jaw", Vector3.new(1.1, 0.35, 0.4), rgb(230, 190, 150), head, CFrame.new(0, -0.55, -0.45)))
	elseif key == "SixSeven" then
		local anchor = deco("Anchor67", Vector3.new(0.2, 0.2, 0.2), rgb(255, 205, 50), head, CFrame.new(0, 1.2, 0))
		anchor.Transparency = 1
		add(anchor)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(3, 1.5)
		gui.StudsOffset = Vector3.new(0, 0.6, 0)
		gui.LightInfluence = 0
		gui.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "67"
		label.TextScaled = true
		label.Font = Enum.Font.LuckiestGuy
		label.TextColor3 = rgb(255, 215, 50)
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
	elseif key == "Brainrot" then
		add(deco("Brain", Vector3.new(1.4, 0.9, 1.3), rgb(255, 150, 190), head, CFrame.new(0, 0.75, 0), Enum.PartType.Ball))
		add(deco("BrainLobe", Vector3.new(0.9, 0.7, 0.9), rgb(255, 130, 175), head, CFrame.new(0.25, 0.95, 0.1), Enum.PartType.Ball))
	elseif key == "TheNPC" then
		add(deco("Cap", Vector3.new(1.3, 0.3, 1.4), rgb(40, 127, 71), head, CFrame.new(0, 0.65, -0.1)))
	else
		add(deco("Antenna", Vector3.new(0.15, 0.8, 0.15), rgb(60, 60, 70), head, CFrame.new(0, 0.9, 0)))
		add(deco("AntennaBall", Vector3.new(0.45, 0.45, 0.45), rgb(120, 220, 90), head, CFrame.new(0, 1.35, 0), Enum.PartType.Ball))
	end
end

-- cosmetic hats (shared/SkinData.lua)
local HATS = {}

function HATS.Cone(head: BasePart, add)
	for i = 0, 2 do
		local r = 1.3 - i * 0.35
		add(deco("Cone" .. i, Vector3.new(0.55, r, r), if i % 2 == 0 then rgb(255, 120, 30) else rgb(255, 255, 255), head, CFrame.new(0, 0.85 + i * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder))
	end
end

function HATS.BrainHat(head: BasePart, add)
	add(deco("HatBrain", Vector3.new(1.5, 1, 1.4), rgb(255, 150, 190), head, CFrame.new(0, 0.8, 0), Enum.PartType.Ball))
	add(deco("HatLobe", Vector3.new(0.9, 0.8, 1), rgb(255, 125, 170), head, CFrame.new(0.3, 1.05, 0.1), Enum.PartType.Ball))
end

function HATS.Shades(head: BasePart, add)
	add(deco("HatShades", Vector3.new(1.35, 0.32, 0.2), rgb(10, 10, 15), head, CFrame.new(0, 0.15, -0.62)))
	add(deco("HatShadesBridge", Vector3.new(1.45, 0.08, 0.1), rgb(255, 205, 60), head, CFrame.new(0, 0.3, -0.66)))
end

function HATS.Propeller(head: BasePart, add)
	add(deco("CapTop", Vector3.new(0.5, 1.35, 1.35), rgb(60, 140, 255), head, CFrame.new(0, 0.72, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder))
	add(deco("CapStick", Vector3.new(0.1, 0.4, 0.1), rgb(40, 40, 40), head, CFrame.new(0, 1.15, 0)))
	add(deco("Blade", Vector3.new(1.6, 0.06, 0.25), rgb(255, 60, 70), head, CFrame.new(0, 1.35, 0)))
	add(deco("Blade2", Vector3.new(0.25, 0.06, 1.6), rgb(255, 215, 60), head, CFrame.new(0, 1.35, 0)))
end

function HATS.Headband67(head: BasePart, add)
	local band = deco("Headband", Vector3.new(1.3, 0.3, 1.3), rgb(255, 205, 50), head, CFrame.new(0, 0.35, 0), nil)
	band.Material = Enum.Material.Neon
	add(band)
	local tag = deco("Tag67", Vector3.new(0.6, 0.3, 0.05), rgb(40, 20, 60), head, CFrame.new(0, 0.35, -0.68))
	add(tag)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.CanvasSize = Vector2.new(120, 60)
	gui.Parent = tag
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "67"
	label.TextScaled = true
	label.Font = Enum.Font.LuckiestGuy
	label.TextColor3 = rgb(255, 215, 50)
	label.Parent = gui
end

function HATS.Halo(head: BasePart, add)
	local halo = deco("Halo", Vector3.new(0.15, 1.5, 1.5), rgb(255, 245, 170), head, CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	halo.Material = Enum.Material.Neon
	add(halo)
end

function HATS.GoldAntenna(head: BasePart, add)
	add(deco("GoldStick", Vector3.new(0.15, 0.9, 0.15), rgb(220, 170, 30), head, CFrame.new(0, 0.95, 0)))
	local ball = deco("GoldBall", Vector3.new(0.55, 0.55, 0.55), rgb(255, 215, 50), head, CFrame.new(0, 1.45, 0), Enum.PartType.Ball)
	ball.Material = Enum.Material.Neon
	add(ball)
end

function HATS.Crown(head: BasePart, add)
	local band = deco("CrownBand", Vector3.new(1.3, 0.35, 1.3), rgb(255, 205, 50), head, CFrame.new(0, 0.8, 0))
	band.Material = Enum.Material.Neon
	add(band)
	for i = -1, 1 do
		local spike = deco("CrownSpike", Vector3.new(0.3, 0.45, 0.3), rgb(255, 215, 60), head, CFrame.new(i * 0.45, 1.15, -0.5))
		spike.Material = Enum.Material.Neon
		add(spike)
	end
	add(deco("CrownGem", Vector3.new(0.25, 0.25, 0.1), rgb(255, 60, 120), head, CFrame.new(0, 0.8, -0.68), Enum.PartType.Ball))
end

function CharacterManager:ApplyHat(character: Model, key: string)
	local old = character:FindFirstChild("SurvivorHat")
	if old then
		old:Destroy()
	end
	local builder = HATS[key]
	local head = character:FindFirstChild("Head") :: BasePart?
	if not builder or not head then
		return
	end
	local hat = Instance.new("Model")
	hat.Name = "SurvivorHat"
	hat.Parent = character
	builder(head, function(p: BasePart)
		p.Parent = hat
	end)
end

function CharacterManager:ApplyNameTag(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("SurvivorTag")
	if old then
		old:Destroy()
	end
	local session = self.Services.PlayerManager:Get(player)
	local level = if session then MetaData.BrainLevel(session.Data.BrainXP) else 1
	local vip = self.Services.MonetizationManager:HasPass(player, "VIP")
	local gui = Instance.new("BillboardGui")
	gui.Name = "SurvivorTag"
	gui.Size = UDim2.fromOffset(200, 44)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = head
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.6, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.Text = (if vip then "👑 " else "") .. player.DisplayName
	name.TextColor3 = if vip then rgb(255, 215, 60) else rgb(255, 255, 255)
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.fromScale(0, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Text = string.format("Lv.%d %s", level, MetaData.TitleFor(level))
	title.TextColor3 = rgb(200, 205, 225)
	title.Parent = gui
	for _, label in { name, title } do
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = rgb(25, 20, 45)
		stroke.Parent = label
	end
end

function CharacterManager:ApplyTrail(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local old = root:FindFirstChild("SurvivorTrail")
	if old then
		old:Destroy()
	end
	local Monetization = self.Services.MonetizationManager
	local rainbow = Monetization:HasPass(player, "Cosmetics")
	local gold = Monetization:HasPass(player, "VIP")
	player:SetAttribute("VIP", gold)
	local oldAura = root:FindFirstChild("SurvivorAura")
	if oldAura then
		oldAura:Destroy()
	end
	if rainbow then
		-- Cosmetic Pack: a soft sparkle aura around the character
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "SurvivorAura"
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Rate = 6
		aura.Lifetime = NumberRange.new(0.8, 1.4)
		aura.Speed = NumberRange.new(0.5, 1.5)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Size = NumberSequence.new(0.4, 0)
		aura.LightEmission = 0.8
		aura.Color = ColorSequence.new(rgb(255, 120, 220), rgb(120, 220, 255))
		aura.Parent = root
	end
	if not (rainbow or gold) then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SurvivorTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.2, 1)
	if rainbow then
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, rgb(255, 220, 60)),
			ColorSequenceKeypoint.new(0.5, rgb(80, 230, 110)),
			ColorSequenceKeypoint.new(0.75, rgb(80, 160, 255)),
			ColorSequenceKeypoint.new(1, rgb(200, 90, 255)),
		})
	else
		trail.Color = ColorSequence.new(rgb(255, 215, 60), rgb(255, 170, 40))
	end
	trail.Parent = root
end

function CharacterManager:Refresh(player: Player)
	local character = player.Character
	local session = self.Services.PlayerManager:Get(player)
	if not character or not session then
		return
	end
	self:ApplyLook(character, session.Data.Selected)
	self:ApplyHat(character, session.Data.EquippedSkin)
	self:ApplyNameTag(player, character)
	self:ApplyTrail(player, character)
end

function CharacterManager:OnCharacter(player: Player, character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid.WalkSpeed = GameConfig.Player.BaseWalkSpeed
		humanoid.Died:Connect(function()
			task.wait(2)
			if player.Parent then
				self.Services.GameManager:OnCharacterDied(player)
			end
		end)
	end
	task.defer(function()
		self:Refresh(player)
	end)
end

function CharacterManager:SetWalkSpeed(player: Player, speed: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

function CharacterManager:SetJump(player: Player, enabled: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = if enabled then 7.2 else 0
	end
end

function CharacterManager:Teleport(player: Player, cf: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(cf + Vector3.new(0, 3, 0))
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

function CharacterManager:SpawnInLobby(player: Player)
	if not player.Character or not player.Character.Parent then
		player:LoadCharacter()
	end
	self:Teleport(player, self.Services.MapBuilder:SpawnPoint("Lobby"))
	self:SetWalkSpeed(player, GameConfig.Player.BaseWalkSpeed)
	self:SetJump(player, true)
end

function CharacterManager:Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			self:OnCharacter(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			self:OnCharacter(player, character)
		end)
	end
end

return CharacterManager
