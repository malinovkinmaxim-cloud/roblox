--[[
	LootRenderer - RELICS lying on the ground (shared/RelicData.lua, Sim/Relics.lua).

	A relic is loot you walk to: a spinning crystal in the colour of its rarity floating over a
	glowing ring, a column of light you can see from across the map (taller and brighter for
	better relics), and its name when you come close. Walk over it to take it (the server
	decides; the HUD shows the card).
	Only a handful exist at once, so every relic is its own small model (no pool needed).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local RelicData = require(Shared.RelicData)
local Rarity = require(Shared.Rarity)

local Theme = require(script.Parent.Parent.UI.Theme)

local LootRenderer = {}

local rgb = Color3.fromRGB
local FLAT = CFrame.Angles(0, 0, math.rad(90))
-- the column of light: height and glow by rarity
local BEAM = { Common = 12, Rare = 16, Epic = 21, Legendary = 26, Secret = 26 }

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	return p
end

function LootRenderer:Init(controllers)
	self.C = controllers
	local folder = Instance.new("Folder")
	folder.Name = "RunLoot"
	folder.Parent = Workspace
	self.Folder = folder
	self.Items = {} :: { [number]: any }
end

function LootRenderer:Add(id: number, relicId: number, x: number, z: number)
	self:Take(id, false)
	local def = RelicData.ById[relicId]
	if not def then
		return
	end
	local run = self.C.RunClient
	local color = Rarity.Colors[def.Rarity] or rgb(255, 255, 255)
	local model = Instance.new("Model")
	model.Name = "Relic_" .. def.Key
	local base = run:World(x, z, 0)
	local ring = part("Ring", Vector3.new(0.15, 6, 6), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.45
	ring.CFrame = CFrame.new(base + Vector3.new(0, 0.25, 0)) * FLAT
	ring.Parent = model
	local height = BEAM[def.Rarity] or 20
	local beam = part("Beam", Vector3.new(height, 0.55, 0.55), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	beam.Transparency = 0.6
	beam.CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * FLAT
	beam.Parent = model
	local gem = part("Gem", Vector3.new(1.8, 1.8, 1.8), color, Enum.Material.Neon)
	gem.Parent = model
	local core = part("Core", Vector3.new(0.9, 0.9, 0.9), rgb(255, 255, 255), Enum.Material.Neon, Enum.PartType.Ball)
	core.Parent = model
	if def.Rarity == "Epic" or def.Rarity == "Legendary" or def.Rarity == "Secret" then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 14
		light.Brightness = 2
		light.Parent = gem
	end
	-- the name when you are close
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 55
	gui.AlwaysOnTop = true
	gui.Adornee = gem
	for i, line in { { string.upper(def.Rarity) .. " RELIC", 14, color }, { def.Name, 20, Theme.Colors.Text } } do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, line[2] :: number)
		label.Position = UDim2.fromOffset(0, if i == 1 then 0 else 15)
		label.Font = if i == 1 then Theme.Fonts.Bold else Theme.Fonts.Title
		label.TextScaled = true
		label.Text = line[1] :: string
		label.TextColor3 = line[3] :: Color3
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = Theme.Colors.SurfaceDark
		stroke.Parent = label
	end
	gui.Parent = gem
	model.Parent = self.Folder
	self.Items[id] = { Id = id, Def = def, X = x, Z = z, Model = model, Gem = gem, Core = core, Ring = ring, Beam = beam, Base = base, Phase = math.random() * 6, Born = os.clock() }
	self.C.EffectsController:Poof(x, z, color, 12)
	self.C.SoundController:Play("Chest", 1.2, 0.6)
end

function LootRenderer:Take(id: number, _collected: boolean)
	local item = self.Items[id]
	if not item then
		return
	end
	self.Items[id] = nil
	item.Model:Destroy()
end

function LootRenderer:Clear()
	for id in self.Items do
		self:Take(id, false)
	end
end

function LootRenderer:Update()
	local now = os.clock()
	for _, item in self.Items do
		local t = now + item.Phase
		-- pops up out of the ground, then floats and spins
		local rise = math.min(1, (now - item.Born) / 0.35)
		local y = 1.2 + rise * 1.4 + math.sin(t * 2.2) * 0.35
		local cf = CFrame.new(item.Base + Vector3.new(0, y, 0))
		item.Gem.CFrame = cf * CFrame.Angles(0, t * 1.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		item.Core.CFrame = cf
		item.Beam.Transparency = 0.58 + math.sin(t * 3) * 0.08
		local pulse = 5.4 + math.sin(t * 3) * 0.6
		item.Ring.Size = Vector3.new(0.15, pulse, pulse)
	end
end

-- relics on the ground (for the minimap and the edge pointers)
function LootRenderer:List(): { any }
	local out = {}
	for _, item in self.Items do
		table.insert(out, item)
	end
	return out
end

function LootRenderer:Start()
	RunService.RenderStepped:Connect(function()
		self:Update()
	end)
end

return LootRenderer
