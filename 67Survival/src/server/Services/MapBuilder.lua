--[[
	MapBuilder - builds the world from code: the LOBBY ("67 LAND", the event map: Map/EventMap)
	and the battle map "67 TOWN" (Map/BattleMap: five zones around a start square, mini-boss
	lairs, 67 vaults, secrets; its layout is shared/ArenaData.lua).

	If Workspace already has a "Map" model (made by hand in Studio), it is used as is.
	Rules for a custom map:
	  * Map.Arena: parts with attribute EnemyBlocker = true block enemies (their XZ bounding
	    boxes become colliders for the server simulation); parts with Water = true are ponds
	  * parts with attribute SecretRegion = "<key>" are secret areas (server checks positions)
	  * Workspace.SpawnPoints: "Lobby" + "Arena1".."ArenaN"

	The lobby spawn is the HUB STAGE of 67 LAND: the player's hero on a pedestal, framed by the
	hub camera (client CameraController). Also sets the base lighting (haze, soft bloom).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Shared.GameConfig)
local EventMap = require(script.Parent.Parent.Map.EventMap)
local BattleMap = require(script.Parent.Parent.Map.BattleMap)

local MapBuilder = {}

local rgb = Color3.fromRGB
local CENTER = GameConfig.Arena.Center
local LOBBY = GameConfig.Lobby.Center

-- an invisible marker part (spawn points)
local function marker(name: string, cf: CFrame, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(6, 1, 6)
	p.CFrame = cf
	p.Color = rgb(255, 255, 255)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- lobby: "67 LAND", the event map (Map/EventMap)
---------------------------------------------------------------------------
local STAGE = Vector3.new(0, 0, -6) -- lobby offset of the hero spot (= the lobby spawn)
MapBuilder.StageOffset = STAGE

-- the look of the whole place: soft daylight, a light haze, a little bloom for the neon
local function applyLighting()
	local Lighting = game:GetService("Lighting")
	if Lighting:FindFirstChild("S67Atmosphere") then
		return
	end
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = rgb(72, 66, 98)
	Lighting.OutdoorAmbient = rgb(132, 126, 156)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ShadowSoftness = 0.3
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "S67Atmosphere"
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = rgb(206, 214, 240)
	atmosphere.Decay = rgb(110, 112, 156)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "S67Bloom"
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "S67Grade"
	grade.Saturation = 0.08
	grade.Contrast = 0.06
	grade.Parent = Lighting
end

local function buildLobby(map: Model)
	return EventMap.Build(map, LOBBY, STAGE)
end

local function buildSpawns(map: Model)
	local spawns = Instance.new("Folder")
	spawns.Name = "SpawnPoints"
	spawns.Parent = Workspace
	-- the lobby spawn is the hub stage's pedestal (its top is 0.65 above the floor)
	marker("Lobby", CFrame.new(LOBBY + STAGE + Vector3.new(0, 0.7, 0)), spawns)
	-- runs start in THE 67 ARENA in the middle of 67 TOWN
	for i, offset in GameConfig.Arena.StartOffsets do
		marker("Arena" .. i, CFrame.new(CENTER + offset + Vector3.new(0, 0.5, 0)), spawns)
	end
	return map
end

---------------------------------------------------------------------------
-- colliders & regions for the server simulation
---------------------------------------------------------------------------
local COLLIDER_CELL = 32

function MapBuilder.ExtractColliders(arena: Instance)
	local cells = {}
	local count = 0
	local water = {}
	for _, d in arena:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Water") then
			-- a flat cylinder: its radius is half the size across (arena coordinates)
			local p = d.CFrame.Position - CENTER
			table.insert(water, { X = p.X, Z = p.Z, R = math.max(d.Size.Y, d.Size.Z) / 2 })
		end
		if d:IsA("BasePart") and d:GetAttribute("EnemyBlocker") then
			-- XZ bounding box of the (possibly rotated) part, in arena coordinates
			local cf, size = d.CFrame, d.Size
			local hx = math.abs(cf.RightVector.X) * size.X / 2 + math.abs(cf.UpVector.X) * size.Y / 2 + math.abs(cf.LookVector.X) * size.Z / 2
			local hz = math.abs(cf.RightVector.Z) * size.X / 2 + math.abs(cf.UpVector.Z) * size.Y / 2 + math.abs(cf.LookVector.Z) * size.Z / 2
			local p = cf.Position - CENTER
			local col = { MinX = p.X - hx, MaxX = p.X + hx, MinZ = p.Z - hz, MaxZ = p.Z + hz, Name = d.Name }
			count += 1
			-- register in every cell it (plus an enemy radius margin) overlaps
			local margin = 8
			for cx = math.floor((col.MinX - margin) / COLLIDER_CELL), math.floor((col.MaxX + margin) / COLLIDER_CELL) do
				for cz = math.floor((col.MinZ - margin) / COLLIDER_CELL), math.floor((col.MaxZ + margin) / COLLIDER_CELL) do
					local key = cx * 4096 + cz
					cells[key] = cells[key] or {}
					table.insert(cells[key], col)
				end
			end
		end
	end
	return { Cell = COLLIDER_CELL, Cells = cells, Count = count, Water = water }
end

function MapBuilder.ExtractRegions(map: Instance)
	local regions = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SecretRegion") then
			table.insert(regions, { Key = d:GetAttribute("SecretRegion"), CFrame = d.CFrame, Size = d.Size + Vector3.new(0, 8, 0) })
		end
	end
	return regions
end

function MapBuilder:Init(services)
	self.Services = services
	local map = Workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Model")
		map.Name = "Map"
		BattleMap.Build(map)
		buildLobby(map)
		map.Parent = Workspace
	end
	if not Workspace:FindFirstChild("SpawnPoints") then
		buildSpawns(map)
	end
	applyLighting()
	self.Map = map
	local arena = map:FindFirstChild("Arena") or map
	self.Colliders = MapBuilder.ExtractColliders(arena)
	self.Regions = MapBuilder.ExtractRegions(map)
end

function MapBuilder:Start() end

function MapBuilder:SpawnPoint(name: string): CFrame
	local spawns = Workspace:FindFirstChild("SpawnPoints")
	local p = spawns and spawns:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p.CFrame
	end
	if name == "Lobby" then
		return CFrame.new(LOBBY + STAGE + Vector3.new(0, 0.7, 0))
	end
	return CFrame.new(CENTER + Vector3.new(0, 0.5, 0))
end

-- key of the secret region containing a world position (or nil)
function MapBuilder:RegionAt(position: Vector3): string?
	for _, r in self.Regions do
		local lp = r.CFrame:PointToObjectSpace(position)
		local h = r.Size / 2
		if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
			return r.Key
		end
	end
	return nil
end

return MapBuilder
