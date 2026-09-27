--[[
	PickupRenderer - XP gems, pickups (pizza, magnet, bomb, chest, coins) and GOOBER ARMY allies.

	Gems are pooled neon crystals (colour = tier) that sit still (cheap) and fly into the player
	when collected. Items bob and spin (there are only a few). Allies are small goobers moved
	with interpolation, like enemies.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Shared.GameConfig)

local EnemyModels = require(script.Parent.Parent.Render.EnemyModels)

local PickupRenderer = {}

local rgb = Color3.fromRGB
local PARK = CFrame.new(0, -400, 0)
local GEM_COLORS = { rgb(80, 180, 255), rgb(90, 255, 130), rgb(190, 100, 255), rgb(255, 70, 90) }
local GEM_SIZES = { 0.9, 1.15, 1.45, 1.9 }
local SNAP = GameConfig.Sim.SnapshotEvery / GameConfig.Sim.Rate

local function basic(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CFrame = PARK
	return p
end

local function weldTo(root: BasePart, p: BasePart, offset: CFrame)
	p.Anchored = false
	p.Massless = true
	p.CFrame = root.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
end

-- item models: a root part + welded details
local ITEM_BUILDERS = {}

function ITEM_BUILDERS.Pizza(model: Model): BasePart
	local root = basic("Pizza", Vector3.new(0.5, 3, 3), rgb(255, 190, 70), nil, Enum.PartType.Cylinder)
	root.Parent = model
	for i = 1, 3 do
		local a = i * 2.1
		local pep = basic("Pepperoni", Vector3.new(0.2, 0.7, 0.7), rgb(200, 40, 40), nil, Enum.PartType.Cylinder)
		pep.Parent = model
		weldTo(root, pep, CFrame.new(0.2, math.cos(a) * 0.8, math.sin(a) * 0.8))
	end
	return root
end

function ITEM_BUILDERS.Magnet(model: Model): BasePart
	local root = basic("Magnet", Vector3.new(2.6, 0.7, 0.7), rgb(220, 40, 50))
	root.Parent = model
	for _, side in { -1, 1 } do
		local arm = basic("Arm", Vector3.new(0.7, 1.8, 0.7), rgb(220, 40, 50))
		arm.Parent = model
		weldTo(root, arm, CFrame.new(side * 0.95, 1.1, 0))
		local tip = basic("Tip", Vector3.new(0.72, 0.5, 0.72), rgb(230, 230, 240))
		tip.Parent = model
		weldTo(root, tip, CFrame.new(side * 0.95, 2.2, 0))
	end
	return root
end

function ITEM_BUILDERS.Nuke(model: Model): BasePart
	local root = basic("Bomb", Vector3.new(2.4, 2.4, 2.4), rgb(35, 35, 45), nil, Enum.PartType.Ball)
	root.Parent = model
	local fuse = basic("Fuse", Vector3.new(0.3, 0.8, 0.3), rgb(150, 120, 80))
	fuse.Parent = model
	weldTo(root, fuse, CFrame.new(0, 1.4, 0))
	local spark = basic("Spark", Vector3.new(0.5, 0.5, 0.5), rgb(255, 180, 40), Enum.Material.Neon, Enum.PartType.Ball)
	spark.Parent = model
	weldTo(root, spark, CFrame.new(0, 1.9, 0))
	return root
end

function ITEM_BUILDERS.Chest(model: Model): BasePart
	local root = basic("Chest", Vector3.new(3.4, 2.2, 2.4), rgb(140, 85, 40), Enum.Material.WoodPlanks)
	root.Parent = model
	local lid = basic("Lid", Vector3.new(3.5, 0.9, 2.5), rgb(160, 100, 50), Enum.Material.WoodPlanks)
	lid.Parent = model
	weldTo(root, lid, CFrame.new(0, 1.5, 0))
	local band = basic("Band", Vector3.new(3.6, 0.4, 2.6), rgb(255, 205, 50), Enum.Material.Neon)
	band.Parent = model
	weldTo(root, band, CFrame.new(0, 1.05, 0))
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 210, 90)
	light.Range = 12
	light.Brightness = 2
	light.Parent = root
	return root
end

function ITEM_BUILDERS.CoinBag(model: Model): BasePart
	local root = basic("Bag", Vector3.new(2.2, 2.2, 2.2), rgb(150, 110, 60), nil, Enum.PartType.Ball)
	root.Parent = model
	local tie = basic("Tie", Vector3.new(0.9, 0.5, 0.9), rgb(255, 205, 50), Enum.Material.Neon)
	tie.Parent = model
	weldTo(root, tie, CFrame.new(0, 1.2, 0))
	return root
end

function ITEM_BUILDERS.Coin(model: Model): BasePart
	local root = basic("Coin", Vector3.new(0.3, 1.6, 1.6), rgb(255, 205, 50), Enum.Material.Neon, Enum.PartType.Cylinder)
	root.Parent = model
	return root
end

function PickupRenderer:Init(controllers)
	self.C = controllers
	local folder = Instance.new("Folder")
	folder.Name = "RunPickups"
	folder.Parent = Workspace
	self.Folder = folder
	self.Gems = {} -- id -> { Part, X, Z, Tier }
	self.GemFree = {}
	self.Flying = {}
	self.Items = {}
	self.ItemFree = {}
	self.Allies = {}
	self.AllyModels = {}
	self.GemsCreated = 0
end

---------------------------------------------------------------------------
-- gems
---------------------------------------------------------------------------
local GEM_ROT = CFrame.Angles(math.rad(45), 0, math.rad(45))

function PickupRenderer:GemPart(): BasePart
	local p = table.remove(self.GemFree)
	if not p then
		p = basic("Gem", Vector3.new(1, 1, 1), GEM_COLORS[1], Enum.Material.Neon)
		p.Parent = self.Folder
		self.GemsCreated += 1
	end
	return p
end

function PickupRenderer:AddGem(id: number, x: number, z: number, tier: number)
	local old = self.Gems[id]
	if old then
		self:ReleaseGem(old)
	end
	local p = self:GemPart()
	local s = GEM_SIZES[tier] or 1
	p.Size = Vector3.new(s, s, s)
	p.Color = GEM_COLORS[tier] or GEM_COLORS[1]
	local run = self.C.RunClient
	p.CFrame = CFrame.new(run:World(x, z, 1 + s * 0.4)) * GEM_ROT
	self.Gems[id] = { Part = p, X = x, Z = z, Tier = tier }
end

function PickupRenderer:ReleaseGem(g)
	g.Part.CFrame = PARK
	table.insert(self.GemFree, g.Part)
end

function PickupRenderer:GemTier(id: number, tier: number)
	local g = self.Gems[id]
	if g then
		g.Tier = tier
		local s = GEM_SIZES[tier] or 1
		g.Part.Size = Vector3.new(s, s, s)
		g.Part.Color = GEM_COLORS[tier] or GEM_COLORS[1]
		g.Part.CFrame = CFrame.new(self.C.RunClient:World(g.X, g.Z, 1 + s * 0.4)) * GEM_ROT
	end
end

function PickupRenderer:TakeGem(id: number)
	local g = self.Gems[id]
	if not g then
		return
	end
	self.Gems[id] = nil
	if #self.Flying < 60 then
		table.insert(self.Flying, { Part = g.Part, From = g.Part.Position, T = 0, Gem = g })
	else
		self:ReleaseGem(g)
	end
	self.C.SoundController:Play("XP", 1 + math.min(0.6, #self.Flying * 0.02))
end

---------------------------------------------------------------------------
-- items
---------------------------------------------------------------------------
function PickupRenderer:AddItem(id: number, kind: string, x: number, z: number)
	local free = self.ItemFree[kind]
	local entry = free and table.remove(free)
	if not entry then
		local model = Instance.new("Model")
		model.Name = kind
		local builder = ITEM_BUILDERS[kind] or ITEM_BUILDERS.Coin
		local root = builder(model)
		model.PrimaryPart = root
		model.Parent = self.Folder
		entry = { Model = model, Root = root, Kind = kind }
	end
	entry.X, entry.Z = x, z
	entry.Phase = math.random() * 6
	entry.Id = id
	self.Items[id] = entry
	if kind == "Chest" then
		self.C.EffectsController:Poof(x, z, rgb(255, 215, 60), 12)
		self.C.SoundController:Play("Chest")
	end
end

function PickupRenderer:TakeItem(id: number, collected: boolean)
	local entry = self.Items[id]
	if not entry then
		return
	end
	self.Items[id] = nil
	entry.Root.CFrame = PARK
	self.ItemFree[entry.Kind] = self.ItemFree[entry.Kind] or {}
	table.insert(self.ItemFree[entry.Kind], entry)
	if collected then
		self.C.EffectsController:ItemCollected(entry.Kind, entry.X, entry.Z)
	end
end

---------------------------------------------------------------------------
-- allies (GOOBER ARMY)
---------------------------------------------------------------------------
function PickupRenderer:Ally(i: number, x: number, z: number, t: number)
	local a = self.Allies[i]
	if not a then
		local model, root, info = EnemyModels.Build({ Key = "Ally", Scale = 0.6, Model = "Blob", Color = rgb(90, 200, 255), Accent = rgb(30, 90, 200) }, false, false)
		model.Parent = self.Folder
		a = { Model = model, Root = root, Info = info, X0 = x, Z0 = z, T0 = t, X1 = x, Z1 = z, T1 = t, Yaw = 0, RX = x, RZ = z }
		self.Allies[i] = a
		self.C.EffectsController:Poof(x, z, rgb(90, 200, 255), 8)
	end
	a.X0, a.Z0 = a.X1, a.Z1
	a.T0 = math.max(a.T1, t - SNAP)
	a.X1, a.Z1, a.T1 = x, z, t
end

function PickupRenderer:Clear()
	for id, g in self.Gems do
		self:ReleaseGem(g)
		self.Gems[id] = nil
	end
	for _, f in self.Flying do
		self:ReleaseGem(f.Gem)
	end
	table.clear(self.Flying)
	for id in self.Items do
		self:TakeItem(id, false)
	end
	for _, a in self.Allies do
		a.Model:Destroy()
	end
	table.clear(self.Allies)
end

function PickupRenderer:Update(dt: number)
	local run = self.C.RunClient
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local now = os.clock()

	-- collected gems fly into the player
	local flying = self.Flying
	local i = 1
	while i <= #flying do
		local f = flying[i]
		f.T += dt / 0.22
		if f.T >= 1 or not root then
			self:ReleaseGem(f.Gem)
			flying[i] = flying[#flying]
			flying[#flying] = nil
		else
			local target = (root :: BasePart).Position
			local t = f.T * f.T
			f.Part.CFrame = CFrame.new(f.From:Lerp(target, t) + Vector3.new(0, math.sin(f.T * math.pi) * 3, 0)) * GEM_ROT
			i += 1
		end
	end

	-- items bob and spin
	for _, entry in self.Items do
		local bob = math.sin(now * 3 + entry.Phase) * 0.35
		local spin = now * 2 + entry.Phase
		entry.Root.CFrame = CFrame.new(run:World(entry.X, entry.Z, 2 + bob)) * CFrame.Angles(0, spin, 0)
	end

	-- allies
	local rt = run:RenderTime()
	for _, a in self.Allies do
		local x, z = run:EnemyPos(a, rt)
		local dx, dz = x - a.RX, z - a.RZ
		a.RX, a.RZ = x, z
		if dx * dx + dz * dz > 0.0004 then
			a.Yaw = math.atan2(-dx, -dz)
		end
		local hop = math.abs(math.sin(now * 12 + x)) * 0.4
		a.Root.CFrame = CFrame.new(run:World(x, z, a.Info.Height + hop)) * CFrame.Angles(0, a.Yaw, 0)
	end
end

function PickupRenderer:Start()
	RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

return PickupRenderer
