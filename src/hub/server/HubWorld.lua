local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Parties = require(ReplicatedStorage.Shared.Parties)
local PixelArt = require(ReplicatedStorage.Shared.PixelArt)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

local PALETTE = Config.PALETTE
local C = UiStyle.colors

local HubWorld = {}

local SPAWN = Vector3.new(0, 0, 42)
local ARC_CENTER = Vector3.new(0, 0, 30)
local ARC_RADIUS = 52
local PIXEL = 0.6

local BONUS_TEXT = {
	solo = "x1 REWARDS",
	duo = "x1.5 REWARDS",
	squad = "x2 REWARDS",
	party = "x2.5 REWARDS",
}

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

local function surface(partInstance, face)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = partInstance
	return gui
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

-- A sign standing at `position`, facing the spawn, with a pixel sprite, a title and a subtitle.
-- Local +Z of `facing` points at the spawn, so the sprite sits in front of the board there.
local function pixelSign(position, layers, title, subtitle, color, parent)
	local away = Vector3.new(position.X - SPAWN.X, 0, position.Z - SPAWN.Z).Unit
	local facing = CFrame.lookAt(position, position + away)
	local sprite, size = PixelArt.build(layers, PIXEL, facing * CFrame.new(0, 2.2, 0.5), parent)
	sprite.Name = "KioskSprite"

	local boardSize = Vector3.new(math.max(size.X + 2, 11), size.Y + 7, 0.6)
	local board = part("KioskBoard", boardSize, facing * CFrame.new(0, 0.2, 0), C.paper, parent)
	part("KioskFrame", boardSize + Vector3.new(0.8, 0.8, -0.2), facing * CFrame.new(0, 0.2, -0.3), color, parent)
	for _, side in { -1, 1 } do
		local post = part("KioskPost", Vector3.new(0.8, position.Y, 0.8), CFrame.new(position.X, position.Y / 2, position.Z) * facing.Rotation * CFrame.new(side * (boardSize.X / 2 - 0.6), 0, -0.6), color, parent)
		post.CanCollide = false
	end
	local gui = surface(board, Enum.NormalId.Back)
	textLabel(gui, title, UDim2.new(0.94, 0, 0, 44), UDim2.new(0.03, 0, 1, -94), C.ink)
	textLabel(gui, subtitle, UDim2.new(0.94, 0, 0, 34), UDim2.new(0.03, 0, 1, -48), color)
	return board
end

local function partyLayers(partyId)
	local colors = Config.PLAYER_COLORS
	local function bunny(index, x, y, small)
		local color = colors[index]
		return {
			rows = if small then PixelArt.BUNNY_SMALL else PixelArt.BUNNY,
			colors = { A = color, F = color:Lerp(PixelArt.INK, 0.4) },
			x = x,
			y = y,
		}
	end
	if partyId == "solo" then
		return { bunny(1, 0, 0) }
	elseif partyId == "duo" then
		return { bunny(1, 0, 0), bunny(2, 10, 0) }
	elseif partyId == "squad" then
		return { bunny(3, 0, 2, true), bunny(4, 6, 1, true), bunny(5, 12, 2, true) }
	end
	return {
		{ rows = { "Y.R...Y...R.Y..R...Y." }, x = 0, y = 0 },
		bunny(1, 0, 3, true),
		bunny(6, 5, 2, true),
		bunny(7, 11, 3, true),
		bunny(8, 16, 2, true),
	}
end

-- Pixel arch between the spawn and the kiosks
local function buildArch(parent)
	local z = 22
	local colors = { Config.PLAYER_COLORS[1], Config.PLAYER_COLORS[3] }
	for _, x in { -15, 15 } do
		for level = 0, 6 do
			part("ArchBlock", Vector3.new(2, 2, 2), CFrame.new(x, 1 + level * 2, z), colors[level % 2 + 1], parent)
		end
	end
	local beam = part("ArchBeam", Vector3.new(34, 4, 2), CFrame.new(0, 16, z), Config.PLAYER_COLORS[2], parent)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local label = textLabel(surface(beam, face), "PICK YOUR SQUAD", UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1), C.white)
		UiStyle.stroke(label, 3, C.ink, Enum.ApplyStrokeMode.Contextual)
	end
end

local function buildTitle(parent)
	local board = part("TitleBoard", Vector3.new(60, 18, 1), CFrame.new(0, 20, -40), Color3.new(1, 1, 1), parent)
	for _, x in { -24, 24 } do
		part("Pole", Vector3.new(1.5, 11, 1.5), CFrame.new(x, 5.5, -40), PALETTE.ground, parent)
	end
	local gui = surface(board, Enum.NormalId.Back) -- faces the spawn (+Z)
	local logo = textLabel(gui, Config.GAME_TITLE, UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0.05), PALETTE.lift, UiStyle.fonts.logo)
	UiStyle.stroke(logo, 6, C.ink, Enum.ApplyStrokeMode.Contextual)
	textLabel(
		gui,
		"Step on a kiosk with your friends.\nMore pals at the finish = bigger rewards!",
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
	buildArch(folder)
	for _, pos in { { -75, -60 }, { 75, -60 }, { -80, 10 }, { 80, 10 }, { -60, 65 }, { 60, 65 } } do
		tree(pos[1], pos[2], folder)
	end

	-- Party kiosks: a pad to stand on plus a pixel sign behind it
	local rooms = {}
	local count = #Config.ROOMS
	local spread = math.rad(125)
	for i, partyId in Config.ROOMS do
		local partyInfo = Parties.get(partyId)
		local angle = if count > 1 then -spread / 2 + spread * (i - 1) / (count - 1) else 0
		local center = ARC_CENTER + Vector3.new(math.sin(angle) * ARC_RADIUS, 0, -math.cos(angle) * ARC_RADIUS)
		local color = partyInfo.color

		disc("PadRim", padRadius * 2 + 2, 0.6, center.X, center.Z, 0, Color3.new(1, 1, 1), folder)
		local pad = disc("Pad", padRadius * 2, 1, center.X, center.Z, 0, color, folder)

		local away = Vector3.new(center.X - SPAWN.X, 0, center.Z - SPAWN.Z).Unit
		pixelSign(center + away * (padRadius + 2) + Vector3.new(0, 14, 0), partyLayers(partyId), partyInfo.name, BONUS_TEXT[partyId], color, folder)

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(12, 2.4)
		gui.StudsOffset = Vector3.new(0, 4.5, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = 150
		gui.Parent = pad
		local statusPill = Instance.new("Frame")
		statusPill.BackgroundColor3 = C.paper
		statusPill.Size = UDim2.fromScale(1, 1)
		UiStyle.corner(statusPill, UDim.new(0.5, 0))
		UiStyle.stroke(statusPill, 2.5)
		statusPill.Parent = gui
		local status = textLabel(statusPill, "", UDim2.fromScale(0.86, 0.7), UDim2.fromScale(0.07, 0.15), C.ink)

		table.insert(rooms, {
			party = partyInfo,
			capacity = partyInfo.max,
			minPlayers = partyInfo.min,
			center = Vector3.new(center.X, 1, center.Z),
			entrance = Vector3.new(SPAWN.X, 1, SPAWN.Z),
			pad = pad,
			statusLabel = status,
		})
	end

	-- Invite kiosk
	local invitePosition = Vector3.new(-34, 0, 34)
	disc("InvitePadRim", 10, 0.6, invitePosition.X, invitePosition.Z, 0, Color3.new(1, 1, 1), folder)
	disc("InvitePad", 8, 1, invitePosition.X, invitePosition.Z, 0, C.danger, folder)
	pixelSign(invitePosition + Vector3.new(0, 11, -6), { { rows = PixelArt.ENVELOPE } }, "INVITE FRIENDS", "step on the pad", C.danger, folder)

	-- Leaderboard
	local boardPosition = Vector3.new(34, 0, 34)
	local leaderboardBase = pixelSign(boardPosition + Vector3.new(0, 9, -2), { { rows = PixelArt.TROPHY } }, "TOP STARS", "best pals online", C.gold, folder)
	local boardGui = Instance.new("BillboardGui")
	boardGui.Size = UDim2.fromScale(14, 9)
	boardGui.StudsOffset = Vector3.new(0, 12, 0)
	boardGui.LightInfluence = 0
	boardGui.MaxDistance = 150
	boardGui.Parent = leaderboardBase
	local boardCard = Instance.new("Frame")
	boardCard.BackgroundColor3 = C.paper
	boardCard.Size = UDim2.fromScale(1, 1)
	UiStyle.corner(boardCard, UDim.new(0.08, 0))
	UiStyle.stroke(boardCard, 3)
	boardCard.Parent = boardGui
	local boardText = UiStyle.text(boardCard, {
		Position = UDim2.fromScale(0.06, 0.05),
		Size = UDim2.fromScale(0.88, 0.9),
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "TOP STARS",
	})

	return rooms, {
		invite = { center = Vector3.new(invitePosition.X, 1, invitePosition.Z), radius = 4 },
		leaderboardLabel = boardText,
	}
end

return HubWorld
