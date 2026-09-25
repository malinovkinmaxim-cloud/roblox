--[[
	LobbyService
	Builds a small, clean lobby if Workspace.Lobby does not exist yet.
	(If you build your own lobby in Studio, name it "Lobby" and put a part named "LobbySpawn" in it -
	 this service will leave it alone.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local LobbyService = {}

local WHITE = Color3.fromRGB(240, 243, 248)
local GREY = Color3.fromRGB(210, 216, 228)
local DARK = Color3.fromRGB(40, 44, 60)
local CYAN = Color3.fromRGB(60, 225, 255)
local ORANGE = Color3.fromRGB(255, 150, 50)
local YELLOW = Color3.fromRGB(255, 215, 60)
local PURPLE = Color3.fromRGB(170, 120, 255)

function LobbyService:Init(services)
	self.Services = services
	if not Workspace:FindFirstChild("Lobby") then
		self:Build()
	end
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function label(adornee: BasePart, text: string, size: Vector2, offset: number, color: Color3, font: Enum.Font?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(size.X, 0, size.Y, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Adornee = adornee
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Font = font or Enum.Font.GothamBlack
	text_.TextScaled = true
	text_.TextColor3 = color
	text_.TextStrokeTransparency = 0.2
	text_.TextStrokeColor3 = Color3.fromRGB(20, 22, 30)
	text_.Text = text
	text_.Parent = gui
	gui.Parent = adornee
	return gui
end

function LobbyService:Build()
	local base = Config.LOBBY_POSITION
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"

	-- floor + trim
	part(lobby, "Floor", Vector3.new(120, 2, 120), CFrame.new(base + Vector3.new(0, -1, 0)), WHITE)
	for _, side in { -1, 1 } do
		part(lobby, "Trim", Vector3.new(122, 2.4, 2), CFrame.new(base + Vector3.new(0, -0.8, side * 61)), CYAN, { Material = Enum.Material.Neon })
		part(lobby, "Trim", Vector3.new(2, 2.4, 122), CFrame.new(base + Vector3.new(side * 61, -0.8, 0)), CYAN, { Material = Enum.Material.Neon })
	end

	-- spawn (the "mirror" pad)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0))
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = lobby

	-- title
	local titleAnchor = part(lobby, "TitleAnchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(base + Vector3.new(0, 24, 40)), WHITE, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	label(titleAnchor, "THE DOPPELGÄNGER OBBY", Vector2.new(70, 10), 0, Color3.new(1, 1, 1))
	label(titleAnchor, "Every level, your double gets a new role.", Vector2.new(60, 4), -8, CYAN, Enum.Font.GothamBold)

	-- a big mirror frame: stand in front of it, your doppelgänger is right behind you
	part(lobby, "MirrorFrame", Vector3.new(30, 18, 1), CFrame.new(base + Vector3.new(0, 9, 46)), DARK)
	part(lobby, "Mirror", Vector3.new(27, 15, 0.4), CFrame.new(base + Vector3.new(0, 9, 45.4)), Color3.fromRGB(200, 230, 255), {
		Material = Enum.Material.Glass,
		Reflectance = 0.4,
		Transparency = 0.1,
	})

	-- how-to-play pillars
	local tips = {
		{ Text = "Your DOPPELGÄNGER copies you", Color = CYAN, Pos = Vector3.new(-30, 0, 20) },
		{ Text = "CYAN buttons = only your double can press them", Color = CYAN, Pos = Vector3.new(-30, 0, -10) },
		{ Text = "ORANGE buttons = only YOU", Color = ORANGE, Pos = Vector3.new(30, 0, -10) },
		{ Text = "Each level gives it a ROLE: Rival, Shadow, Ally... or Troll", Color = PURPLE, Pos = Vector3.new(30, 0, 20) },
	}
	for index, tip in tips do
		local pillar = part(lobby, "Tip" .. index, Vector3.new(3, 8, 3), CFrame.new(base + tip.Pos + Vector3.new(0, 4, 0)), GREY)
		part(lobby, "TipCap", Vector3.new(3.4, 0.6, 3.4), CFrame.new(base + tip.Pos + Vector3.new(0, 8.3, 0)), tip.Color, { Material = Enum.Material.Neon })
		label(pillar, tip.Text, Vector2.new(18, 4), 7.5, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	end

	-- play pads (walk on one to open the level list)
	local playPad = part(lobby, "PlayPad", Vector3.new(12, 0.6, 12), CFrame.new(base + Vector3.new(0, 0.3, -30)), YELLOW, {
		Material = Enum.Material.Neon,
	})
	playPad:SetAttribute("LobbyAction", "Play")
	label(playPad, "PLAY", Vector2.new(10, 3), 4, YELLOW)
	local duoPad = part(lobby, "DuoPad", Vector3.new(10, 0.6, 10), CFrame.new(base + Vector3.new(-22, 0.3, -38)), ORANGE, {
		Material = Enum.Material.Neon,
	})
	duoPad:SetAttribute("LobbyAction", "Duo")
	label(duoPad, "DUO", Vector2.new(8, 2.6), 4, ORANGE)
	local shopPad = part(lobby, "ShopPad", Vector3.new(10, 0.6, 10), CFrame.new(base + Vector3.new(22, 0.3, -38)), PURPLE, {
		Material = Enum.Material.Neon,
	})
	shopPad:SetAttribute("LobbyAction", "Shop")
	label(shopPad, "SKINS", Vector2.new(8, 2.6), 4, PURPLE)

	-- a tiny warm-up parkour around the edge
	local steps = {
		Vector3.new(-45, 2, -45),
		Vector3.new(-45, 4, -35),
		Vector3.new(-45, 6, -25),
		Vector3.new(-38, 8, -18),
		Vector3.new(-45, 10, -10),
		Vector3.new(-45, 12, 0),
	}
	for index, position in steps do
		part(lobby, "Warmup" .. index, Vector3.new(5, 1, 5), CFrame.new(base + position), if index % 2 == 0 then CYAN else GREY)
	end
	part(lobby, "WarmupTop", Vector3.new(10, 1, 10), CFrame.new(base + Vector3.new(-45, 14, 12)), YELLOW, { Material = Enum.Material.Neon })

	lobby.Parent = Workspace
end

return LobbyService
