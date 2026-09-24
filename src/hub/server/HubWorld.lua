local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

local PALETTE = Config.PALETTE

local HubWorld = {}

local SPAWN = Vector3.new(0, 0, 42)
local ARC_CENTER = Vector3.new(0, 0, 30)
local ARC_RADIUS = 52

local function part(name, size, cframe, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function textLabel(parent, text, size, position, color, font)
	return UiStyle.text(parent, {
		FontFace = font or UiStyle.fonts.heavy,
		TextScaled = true,
		TextColor3 = color,
		Size = size,
		Position = position,
		Text = text,
	})
end

-- Vertical cylinder standing on the floor (Y = 0) with its bottom at `bottom`
local function disc(name, diameter, height, x, z, bottom, color, parent)
	local p = part(name, Vector3.new(height, diameter, diameter), CFrame.new(x, bottom + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, parent)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function tree(x, z, parent)
	local trunk = disc("Trunk", 1.6, 6, x, z, 0, Color3.fromRGB(150, 105, 75), parent)
	trunk.CanCollide = true
	local crown = part("Crown", Vector3.new(8, 8, 8), CFrame.new(x, 9, z), Color3.fromRGB(110, 200, 140), parent)
	crown.Shape = Enum.PartType.Ball
end

local function buildTitle(parent)
	local board = part("TitleBoard", Vector3.new(60, 18, 1), CFrame.new(0, 20, -40), Color3.new(1, 1, 1), parent)
	for _, x in { -24, 24 } do
		part("Pole", Vector3.new(1.5, 11, 1.5), CFrame.new(x, 5.5, -40), PALETTE.ground, parent)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- faces the spawn (+Z)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local logo = textLabel(gui, Config.GAME_TITLE, UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0.05), PALETTE.lift, UiStyle.fonts.logo)
	UiStyle.stroke(logo, 6, UiStyle.colors.ink, Enum.ApplyStrokeMode.Contextual)
	textLabel(
		gui,
		"Встаньте на платформу комнаты вместе с друзьями.\nКомната стартует, когда в ней 2 игрока или больше.",
		UDim2.fromScale(0.94, 0.32),
		UDim2.fromScale(0.03, 0.62),
		PALETTE.text
	)
end

function HubWorld.build(padRadius)
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	folder.Parent = workspace

	-- Floor: top face at Y = 0. The rim is lower than the floor top so no faces are coplanar.
	part("Floor", Vector3.new(180, 2, 160), CFrame.new(0, -1, 0), Color3.fromRGB(150, 220, 170), folder)
	part("FloorRim", Vector3.new(184, 2, 164), CFrame.new(0, -1.4, 0), PALETTE.ground, folder)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(SPAWN + Vector3.new(0, 0.2, 0))
	spawn.Color = Color3.new(1, 1, 1)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Parent = folder

	buildTitle(folder)
	for _, pos in { { -75, -60 }, { 75, -60 }, { -80, 10 }, { 80, 10 }, { -60, 65 }, { 60, 65 } } do
		tree(pos[1], pos[2], folder)
	end

	local rooms = {}
	local capacities = Config.ROOM_CAPACITIES
	local count = #capacities
	local spread = math.rad(125)
	for i, capacity in capacities do
		local angle = if count > 1 then -spread / 2 + spread * (i - 1) / (count - 1) else 0
		local center = ARC_CENTER + Vector3.new(math.sin(angle) * ARC_RADIUS, 0, -math.cos(angle) * ARC_RADIUS)
		local color = Config.PLAYER_COLORS[(i - 1) % #Config.PLAYER_COLORS + 1]

		disc("PadRim", padRadius * 2 + 2, 0.6, center.X, center.Z, 0, Color3.new(1, 1, 1), folder)
		local pad = disc("Pad", padRadius * 2, 1, center.X, center.Z, 0, color, folder)

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(14, 5.6)
		gui.StudsOffset = Vector3.new(0, 8, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = 150
		gui.Parent = pad

		local titlePill = Instance.new("Frame")
		titlePill.BackgroundColor3 = color
		titlePill.Size = UDim2.fromScale(1, 0.5)
		UiStyle.corner(titlePill, UDim.new(0.5, 0))
		UiStyle.stroke(titlePill, 3)
		titlePill.Parent = gui
		local title = textLabel(titlePill, `КОМНАТА НА {capacity}`, UDim2.fromScale(0.86, 0.7), UDim2.fromScale(0.07, 0.15), UiStyle.colors.white)
		UiStyle.stroke(title, 2.5, UiStyle.colors.ink, Enum.ApplyStrokeMode.Contextual)

		local statusPill = Instance.new("Frame")
		statusPill.BackgroundColor3 = UiStyle.colors.paper
		statusPill.Position = UDim2.fromScale(0.1, 0.58)
		statusPill.Size = UDim2.fromScale(0.8, 0.4)
		UiStyle.corner(statusPill, UDim.new(0.5, 0))
		UiStyle.stroke(statusPill, 2.5)
		statusPill.Parent = gui
		local status = textLabel(statusPill, "", UDim2.fromScale(0.86, 0.7), UDim2.fromScale(0.07, 0.15), UiStyle.colors.ink)

		table.insert(rooms, {
			capacity = capacity,
			center = Vector3.new(center.X, 1, center.Z),
			entrance = Vector3.new(SPAWN.X, 1, SPAWN.Z),
			pad = pad,
			statusLabel = status,
		})
	end

	return rooms
end

return HubWorld
