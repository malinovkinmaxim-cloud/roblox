--[[
	CharacterManager - the player's HERO on top of the Roblox character.

	The Roblox rig still does the walking (Humanoid physics, replication, mobile controls)
	but is made invisible; the selected hero's own model (shared/HeroModels.lua) is welded
	to a "HeroRoot" part joined to the HumanoidRootPart with a Motor6D ("HeroJoint"), so
	the client (Controllers/HeroAnimator.lua) can bob / tilt / emote it by setting
	HeroJoint.Transform. Strong silhouette first: one readable shape per hero.

	Also: collision groups (players never push each other), name tag (+ name effect),
	cosmetics worn on the character (hat, hero skin, trail, aura, lobby decor), emotes,
	walk speed, teleports.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local GameConfig = require(Shared.GameConfig)
local MetaData = require(Shared.MetaData)
local HeroData = require(Shared.HeroData)
local HeroModels = require(Shared.HeroModels)
local CosmeticData = require(Shared.CosmeticData)

local Guard = require(script.Parent.Parent.Util.Guard)

local CharacterManager = {}

local GROUP = "Survivors"
local rgb = Color3.fromRGB

function CharacterManager:Init(services)
	self.Services = services
	Players.CharacterAutoLoads = false
	pcall(function()
		StarterPlayer.LoadCharacterAppearance = false -- heroes have their own models
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)
end

local function style(session, category: string): string
	return CosmeticData.Style(session and session.Data.Cosmetics.Equipped, category)
end

-- the 67 Aura boost (developer product) shows the 67 aura whatever is equipped
local function auraStyle(session): string
	if session and session.Data.CosmeticBoostUntil > os.time() then
		return "Aura67"
	end
	return style(session, "Aura")
end

---------------------------------------------------------------------------
-- the invisible rig + the hero model
---------------------------------------------------------------------------
local function hideRig(character: Model)
	local hero = character:FindFirstChild("HeroModel")
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and not (hero and d:IsDescendantOf(hero)) and d.Name ~= "LobbyDecor" then
			d.Transparency = 1
		end
		if d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
			d:Destroy()
		elseif d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			d:Destroy()
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

function CharacterManager:BuildHero(character: Model, heroKey: string, session)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local old = character:FindFirstChild("HeroModel")
	if old then
		old:Destroy()
	end
	local oldJoint = root:FindFirstChild("HeroJoint")
	if oldJoint then
		oldJoint:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "HeroModel"
	local heroRoot = Instance.new("Part")
	heroRoot.Name = "HeroRoot"
	heroRoot.Size = Vector3.new(0.5, 0.5, 0.5)
	heroRoot.Transparency = 1
	heroRoot.CanCollide = false
	heroRoot.CanQuery = false
	heroRoot.CanTouch = false
	heroRoot.Massless = true
	heroRoot.CFrame = root.CFrame
	heroRoot.Parent = model
	model.PrimaryPart = heroRoot
	HeroModels.Build(heroKey, root.CFrame, model, {
		Skin = style(session, "HeroSkin"),
		Hat = style(session, "Hat"),
		WeldTo = heroRoot,
		Ring = true,
	})
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP
		end
	end
	local joint = Instance.new("Motor6D")
	joint.Name = "HeroJoint"
	joint.Part0 = root
	joint.Part1 = heroRoot
	joint.C0 = CFrame.identity
	joint.C1 = CFrame.identity
	joint.Parent = root
	model.Parent = character
	character:SetAttribute("Hero", heroKey)
	character:SetAttribute("HeroTop", HeroModels.Top(heroKey))
	return model
end

---------------------------------------------------------------------------
-- name tag, trail, aura, lobby decor
---------------------------------------------------------------------------
function CharacterManager:ApplyNameTag(player: Player, character: Model, session)
	local anchor = character:FindFirstChild("HumanoidRootPart")
	if not anchor then
		return
	end
	local old = anchor:FindFirstChild("HeroTag")
	if old then
		old:Destroy()
	end
	local level = if session then MetaData.Level(session.Data.XP) else 1
	local effect = style(session, "NameEffect")
	local def = CosmeticData.ById["NameEffect." .. effect]
	local heroKey = character:GetAttribute("Hero") or HeroData.Default
	local gui = Instance.new("BillboardGui")
	gui.Name = "HeroTag"
	gui.Size = UDim2.fromOffset(200, 44)
	gui.StudsOffset = Vector3.new(0, HeroModels.Top(heroKey) + 0.9, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui:SetAttribute("NameEffect", effect)
	gui.Parent = anchor
	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.Size = UDim2.new(1, 0, 0.6, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.BuilderSansExtraBold
	name.TextScaled = true
	name.Text = player.DisplayName
	name.TextColor3 = if def and def.Color then def.Color else rgb(255, 255, 255)
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.fromScale(0, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.BuilderSansBold
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

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 80, 80)),
	ColorSequenceKeypoint.new(0.25, rgb(255, 220, 60)),
	ColorSequenceKeypoint.new(0.5, rgb(80, 230, 110)),
	ColorSequenceKeypoint.new(0.75, rgb(80, 160, 255)),
	ColorSequenceKeypoint.new(1, rgb(200, 90, 255)),
})

function CharacterManager:ApplyTrail(character: Model, session)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for _, name in { "HeroTrail", "TrailTop", "TrailBottom" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local trailStyle = style(session, "Trail")
	if trailStyle == "None" then
		return
	end
	local def = CosmeticData.ById["Trail." .. trailStyle]
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, -1.2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -2.8, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "HeroTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.25, 1)
	if trailStyle == "Rainbow" then
		trail.Color = RAINBOW
	elseif def and def.Color then
		trail.Color = ColorSequence.new(def.Color, def.Color2 or def.Color)
	end
	trail.Parent = root
end

function CharacterManager:ApplyAura(character: Model, session)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local old = root:FindFirstChild("HeroAura")
	if old then
		old:Destroy()
	end
	local auraKey = auraStyle(session)
	if auraKey == "None" then
		return
	end
	local def = CosmeticData.ById["Aura." .. auraKey]
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "HeroAura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Rate = if auraKey == "Aura67" then 14 else 8
	aura.Lifetime = NumberRange.new(0.8, 1.4)
	aura.Speed = NumberRange.new(0.6, 1.6)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Size = NumberSequence.new(0.45, 0)
	aura.LightEmission = 0.9
	local c1 = if def and def.Color then def.Color else rgb(255, 255, 255)
	aura.Color = ColorSequence.new(c1, if def and def.Color2 then def.Color2 else c1)
	aura.Parent = root
end

-- a decoration under the hero, only in the lobby
function CharacterManager:ApplyDecor(player: Player, character: Model, session)
	local old = character:FindFirstChild("LobbyDecor")
	if old then
		old:Destroy()
	end
	local decor = style(session, "LobbyDecor")
	if decor == "None" or player:GetAttribute("InRun") then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local def = CosmeticData.ById["LobbyDecor." .. decor]
	if not root or not def then
		return
	end
	local part = Instance.new("Part")
	part.Name = "LobbyDecor"
	part.Shape = if decor == "Tile67" then Enum.PartType.Block else Enum.PartType.Cylinder
	part.Size = if decor == "Tile67" then Vector3.new(5, 0.2, 5) else Vector3.new(0.2, 5.5, 5.5)
	part.Color = def.Color or rgb(255, 255, 255)
	part.Material = if decor == "GrassPatch" then Enum.Material.Grass elseif decor == "GoldPedestal" then Enum.Material.SmoothPlastic else Enum.Material.Neon
	part.Transparency = if decor == "NeonRing" then 0.35 else 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CollisionGroup = GROUP
	local cf = root.CFrame * CFrame.new(0, -2.95, 0)
	if part.Shape == Enum.PartType.Cylinder then
		cf *= CFrame.Angles(0, 0, math.pi / 2)
	end
	part.CFrame = cf
	if decor == "Tile67" then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.LightInfluence = 0
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "67"
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = rgb(60, 30, 90)
		label.Parent = gui
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = root
	weld.Parent = part
	part.Parent = character
end

---------------------------------------------------------------------------
-- refresh / lifecycle
---------------------------------------------------------------------------
function CharacterManager:Refresh(player: Player)
	local character = player.Character
	local session = self.Services.PlayerManager:Get(player)
	if not character or not session then
		return
	end
	hideRig(character)
	self:BuildHero(character, session.Data.Selected, session)
	self:ApplyNameTag(player, character, session)
	self:ApplyTrail(character, session)
	self:ApplyAura(character, session)
	self:ApplyDecor(player, character, session)
	player:SetAttribute("Hero", session.Data.Selected)
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
		elseif d:IsA("Accessory") or d:IsA("Clothing") then
			task.defer(function()
				d:Destroy()
			end)
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
	self:Refresh(player)
end

-- plays an owned emote (lobby only): every client animates it (HeroAnimator)
function CharacterManager:Emote(player: Player, emote: string)
	local session = self.Services.PlayerManager:Get(player)
	local character = player.Character
	if not session or not character or player:GetAttribute("InRun") then
		return
	end
	local id = "Emote." .. emote
	if not session.Data.Cosmetics.Owned[id] then
		return
	end
	character:SetAttribute("Emote", emote)
	character:SetAttribute("EmoteAt", Workspace:GetServerTimeNow())
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
	Guard.Connect(Net.Event("Emote"), { Rate = 1, Burst = 3 }, function(player, emote)
		if Guard.Str(emote, 24) then
			self:Emote(player, emote)
		end
	end)
end

return CharacterManager
