--!nocheck
--[[
	67 TOWN review, part 1: runs the REAL server and one client in the offline engine, starts a
	run, calls every mini-boss to its lair (and drops a few relics), then writes the battle map
	as the client sees it to build/town/town.json: the arena's parts, the enemies' and relics'
	models, sign texts, floating labels, lights and the lighting. tools/town_sheet.py draws the
	views from the run camera.

	lune run tools/town_sheet.luau -- [--open] [--quiet]
	  --open   the rift is open (4:30 passed)
	  --quiet  no mini-bosses, no relics (just the map)
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("../tests/engine")

local OUT = "build/town"
local open, quiet = false, false
for _, a in process.args do
	if a == "--open" then
		open = true
	elseif a == "--quiet" then
		quiet = true
	end
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

local function labels(gui, offsets: boolean?)
	local out = {}
	for _, d in gui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("Frame")) and d.Visible then
			local pos, size, anchor = d.Position, d.Size, d.AnchorPoint
			local entry
			if offsets then
				-- offset-sized plates (mini-boss name plates): convert to fractions of the gui
				local gw, gh = gui.Size.X.Offset, gui.Size.Y.Offset
				local w = size.X.Scale + size.X.Offset / math.max(1, gw)
				local h = size.Y.Scale + size.Y.Offset / math.max(1, gh)
				local px = pos.X.Scale + pos.X.Offset / math.max(1, gw)
				local py = pos.Y.Scale + pos.Y.Offset / math.max(1, gh)
				entry = { x = px - anchor.X * w, y = py - anchor.Y * h, w = w, h = h }
			else
				entry = {
					x = pos.X.Scale - anchor.X * size.X.Scale,
					y = pos.Y.Scale - anchor.Y * size.Y.Scale,
					w = size.X.Scale,
					h = size.Y.Scale,
				}
			end
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
local GM = Engine.Module(server, "ServerScriptService.Server.Services.GameManager")
local client, player = Engine.AddPlayer("Alice")
Engine.Step(1)
local cd = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
cd:Fire("StartRun")
Engine.Step(1)
local run = GM.Entries[player].Run
cd:Fire("Admin", "god", "")
if open then
	cd:Fire("Admin", "time", "271")
	Engine.Step(1)
end
if not quiet then
	for _, key in { "BigQuack", "Cartzilla", "JackpotJimmy", "Twins", "TickTock" } do
		cd:Fire("Admin", "miniboss", key)
		Engine.Step(0.2)
	end
	Engine.Step(3.6)
	-- relics around the fountain (one of each tier)
	local Relics = Engine.Module(server, "ServerScriptService.Server.Sim.Relics")
	for i, key in { "Sneakers", "ThirdArm", "RocketSkates", "Crown67" } do
		Relics.Drop(run, key, -20 + i * 8, 44)
	end
	Engine.Step(1)
end
-- the enemies of the horde would cover the map: only the mini-bosses stay
for _, e in table.clone(run.Enemies) do
	if not e.Def.Champion then
		local EM = Engine.Module(server, "ServerScriptService.Server.Sim.EnemyManager")
		EM.Despawn(run, e)
	end
end
Engine.Step(0.5)

local ws = real(client.Game:GetService("Workspace"))
local map = ws:FindFirstChild("Map")
local arena = map:FindFirstChild("Arena")
local out = { parts = {}, lights = {}, texts = {}, billboards = {}, origin = { 0, 0, 0 } }
local function export(root)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Transparency < 0.98 and part.CFrame.Position.Y > -100 then
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
				elseif g:IsA("BillboardGui") and g.Enabled and part.CFrame.Position.Y > -100 then
					local pos = part.CFrame.Position + g.StudsOffset
					local offsets = g.Size.X.Offset > 0
					table.insert(out.billboards, {
						p = { pos.X, pos.Y, pos.Z },
						w = if offsets then g.Size.X.Offset / 30 else g.Size.X.Scale,
						h = if offsets then g.Size.Y.Offset / 30 else g.Size.Y.Scale,
						far = g.MaxDistance,
						labels = labels(g, offsets),
					})
				elseif g:IsA("PointLight") and g.Enabled then
					local lp = part.CFrame.Position
					table.insert(out.lights, { p = { lp.X, lp.Y, lp.Z }, range = g.Range, brightness = g.Brightness, c = color(g.Color) })
				end
			end
		end
	end
end
export(arena)
local loot = ws:FindFirstChild("RunLoot")
if loot then
	export(loot)
end
-- enemy models: the renderer moves only their root (welds do the rest in Roblox; the offline
-- engine has no physics), so the other parts are placed from where they were built (PARK)
local PARK = roblox.CFrame.new(0, -400, 0)
local enemies = ws:FindFirstChild("RunEnemies")
if enemies then
	for _, model in enemies:GetChildren() do
		local root = model:IsA("Model") and model.PrimaryPart
		if root and root.CFrame.Position.Y > -100 then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					local cf = if part == root then root.CFrame else root.CFrame * PARK:Inverse() * part.CFrame
					if part.Transparency < 0.98 then
						table.insert(out.parts, partInfo(part, cf))
					end
				end
			end
		end
	end
end

-- a hero for scale
local HeroModels = Engine.Module(server, "ReplicatedStorage.Modules.HeroModels")
local folder = Engine.Wrap(roblox.Instance.new("Folder"), server)
out.hero = {}
for _, p in HeroModels.Build("Rookie", roblox.CFrame.new(), folder, { Ring = true }) do
	local r = rawget(p, "__real") or p
	table.insert(out.hero, partInfo(r, r.CFrame))
end

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
local minis = {}
out.minis = {} -- where each mini-boss really stands (the roaming one picks a 67 SPOT)
for _, enc in run.Map.Encounters do
	for _, e in enc.Bodies do
		table.insert(minis, e.Key .. string.format(" %.0f,%.0f", e.X, e.Z))
		out.minis[e.Key] = { e.X, e.Z }
	end
end

if not fs.isDir("build") then
	fs.writeDir("build")
end
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
fs.writeFile(OUT .. "/town.json", serde.encode("json", out))
print(string.format("67 town: %d parts, %d signs, %d labels, %d lights | minis: %s | errors %d", #out.parts, #out.texts, #out.billboards, #out.lights, table.concat(minis, "; "), #Engine.Errors))
for _, err in Engine.Errors do
	print("  ERROR " .. tostring(err))
end
