--!nocheck
--[[
	67 LAND review, part 1: runs the REAL server and one client in the offline engine (the
	client styles the gates, the beacon and the NPC bubbles exactly like in the game), then
	writes the lobby as the client sees it to build/map/lobby.json: every part, the texts of
	its signs (SurfaceGuis) and floating labels (BillboardGuis), the point lights, the
	lighting, and a hero model (for scale). tools/map_sheet.py draws the views.

	lune run tools/map_sheet.luau -- [--unlocked N] [--selected N] [--talk]
	  --unlocked  how many tiers the player has opened (default 3: I-III open, IV next)
	  --selected  the selected tier (default 2)
	  --talk      stand next to the tour guide so a speech bubble shows
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("../tests/engine")

local OUT = "build/map"
local unlocked, selected, talk = 3, 2, false
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--unlocked" then
		unlocked = tonumber(process.args[i + 1]) or unlocked
		i += 1
	elseif a == "--selected" then
		selected = tonumber(process.args[i + 1]) or selected
		i += 1
	elseif a == "--talk" then
		talk = true
	end
	i += 1
end

local function real(v)
	return if type(v) == "table" and rawget(v, "__real") then rawget(v, "__real") else v
end
local function color(c)
	return { c.R, c.G, c.B }
end
local function shapeOf(d): string
	if d:IsA("Part") then
		return d.Shape.Name
	end
	return "Block"
end

local function partInfo(d, cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local info = {
		name = d.Name,
		p = { x, y, z },
		r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		s = { d.Size.X, d.Size.Y, d.Size.Z },
		c = color(d.Color),
		t = d.Transparency,
		shape = shapeOf(d),
		mat = d.Material.Name,
		neon = d.Material.Name == "Neon",
	}
	local mesh = d:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		info.mesh = { type = mesh.MeshType.Name, scale = { mesh.Scale.X, mesh.Scale.Y, mesh.Scale.Z }, offset = { mesh.Offset.X, mesh.Offset.Y, mesh.Offset.Z } }
	end
	return info
end

-- the text labels of a GUI (scale positions only: the map's signs are laid out in scale)
local function labels(gui)
	local out = {}
	for _, d in gui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("Frame")) and d.Visible then
			local pos, size, anchor = d.Position, d.Size, d.AnchorPoint
			local entry = {
				x = pos.X.Scale - anchor.X * size.X.Scale,
				y = pos.Y.Scale - anchor.Y * size.Y.Scale,
				w = size.X.Scale,
				h = size.Y.Scale,
			}
			if d:IsA("TextLabel") then
				entry.text = d.Text
				entry.c = color(d.TextColor3)
				entry.font = d.Font.Name
			elseif d.BackgroundTransparency < 0.9 then
				entry.bg = color(d.BackgroundColor3)
			end
			if entry.text or entry.bg then
				table.insert(out, entry)
			end
		end
	end
	return out
end

local server = Engine.StartServer()
local PM = Engine.Module(server, "ServerScriptService.Server.Services.PlayerManager")
local client, player = Engine.AddPlayer("Alice")
Engine.Step(1)
local session = PM:Get(player)
local d = session.Data.Difficulty
for t = 1, math.clamp(unlocked, 1, 7) - 1 do
	d.Best[t] = { Time = 720, Bosses = 4, Wins = 1 }
end
d.Selected = math.clamp(selected, 1, math.clamp(unlocked, 1, 7))
PM:Sync(player)
Engine.Step(1.5)

-- the client's copy of the world (styled by its EventMapController)
local ws = real(client.Game:GetService("Workspace"))
local map = ws:FindFirstChild("Map")
local lobby = map:FindFirstChild("Lobby")
local origin = lobby:FindFirstChild("HubStage"):FindFirstChild("Pedestal").CFrame.Position

if talk then
	-- stand next to the tour guide for a moment (the controller opens its bubble)
	for _, m in lobby:GetDescendants() do
		if m:IsA("BasePart") and m:GetAttribute("NpcKey") == "Guide" then
			local ch = player.Character
			if ch then
				ch:PivotTo(roblox.CFrame.new(m.CFrame.Position + roblox.Vector3.new(4, -4, -4)))
			end
		end
	end
	Engine.Step(1)
end

local out = { parts = {}, lights = {}, texts = {}, billboards = {}, origin = { origin.X, origin.Y, origin.Z } }
for _, part in lobby:GetDescendants() do
	if part:IsA("BasePart") then
		if part.Transparency < 0.98 then
			table.insert(out.parts, partInfo(part, part.CFrame))
		end
		for _, g in part:GetChildren() do
			if g:IsA("SurfaceGui") and g.Enabled then
				local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
				table.insert(out.texts, {
					p = { x, y, z },
					r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
					s = { part.Size.X, part.Size.Y, part.Size.Z },
					face = g.Face.Name,
					glow = g.LightInfluence < 0.5,
					labels = labels(g),
				})
			elseif g:IsA("BillboardGui") and g.Enabled then
				local pos = part.CFrame.Position + g.StudsOffset
				table.insert(out.billboards, {
					p = { pos.X, pos.Y, pos.Z },
					w = g.Size.X.Scale,
					h = g.Size.Y.Scale,
					far = g.MaxDistance,
					labels = labels(g),
				})
			elseif g:IsA("PointLight") and g.Enabled then
				local lp = part.CFrame.Position
				table.insert(out.lights, { p = { lp.X, lp.Y, lp.Z }, range = g.Range, brightness = g.Brightness, c = color(g.Color) })
			end
		end
	end
end

-- a hero for scale (root at the origin, facing -Z like on the stage)
local HeroModels = Engine.Module(server, "ReplicatedStorage.Modules.HeroModels")
local folder = Engine.Wrap(roblox.Instance.new("Folder"), server)
out.hero = {}
for _, p in HeroModels.Build("Rookie", roblox.CFrame.new(), folder, { Ring = true }) do
	local r = rawget(p, "__real") or p
	table.insert(out.hero, partInfo(r, r.CFrame))
end

-- lighting: the server's (MapBuilder)
local lighting = real(server.Game:GetService("Lighting"))
local clock = lighting.ClockTime
local a = (clock - 6) / 12 * math.pi
local sun = roblox.Vector3.new(-math.cos(a) * 0.6, math.sin(a), 0.45).Unit
local amb = lighting.OutdoorAmbient
out.light = { sun = { -sun.X, -sun.Y, -sun.Z }, ambient = { 0.45 + amb.R * 0.35, 0.45 + amb.G * 0.35, 0.5 + amb.B * 0.35 } }
local atmosphere = lighting:FindFirstChild("S67Atmosphere")
if atmosphere then
	out.light.fogDensity = atmosphere.Density * 0.012
	out.light.fogColor = color(atmosphere.Color)
end

if not fs.isDir("build") then
	fs.writeDir("build")
end
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
fs.writeFile(OUT .. "/lobby.json", serde.encode("json", out))
print(string.format("lobby: %d parts, %d signs, %d labels, %d lights (unlocked %d, selected %d)", #out.parts, #out.texts, #out.billboards, #out.lights, unlocked, d.Selected))
