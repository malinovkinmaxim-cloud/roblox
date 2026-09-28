--!nocheck
--[[
	Visual check, part 1: runs the REAL server + client scripts in the offline engine, walks
	through the screens a player sees (hub, menus, a run with a boss, level up, results,
	phone) and writes each PlayerGui as a JSON tree to build/ui/<scene>.json.
	tools/render_gui.py lays those trees out at any resolution and draws PNGs.

	Run from 67Survival/:   lune run tools/export_gui.luau
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Engine = require("../tests/engine")
local Bot = require("../tests/bot")

local Vector3 = roblox.Vector3
local OUT = "build/ui"
local ARENA_Y = 3

local function real(v)
	return if type(v) == "table" and rawget(v, "__real") then rawget(v, "__real") else v
end

local function finite(n: number): number
	if n ~= n then
		return 0
	end
	return math.clamp(n, -1e9, 1e9)
end

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end
local function udim(u)
	return { u.Scale, u.Offset }
end
local function color(c)
	return { c.R, c.G, c.B }
end
local function vec2(v)
	return { finite(v.X), finite(v.Y) }
end
local function enum(e)
	return if e then e.Name else nil
end

local GUI = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	ViewportFrame = true,
	CanvasGroup = true,
}

local function shapeOf(d): string
	if d:IsA("Part") then
		return d.Shape.Name
	elseif d:IsA("WedgePart") then
		return "Wedge"
	elseif d:IsA("CornerWedgePart") then
		return "CornerWedge"
	end
	return "Block"
end

-- one part for tools/render3d.py (cf: the CFrame to draw it at)
local function partInfo(d, cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local info = {
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
		info.mesh = {
			type = mesh.MeshType.Name,
			scale = { mesh.Scale.X, mesh.Scale.Y, mesh.Scale.Z },
			offset = { mesh.Offset.X, mesh.Offset.Y, mesh.Offset.Z },
		}
	end
	return info
end

local function parts(vf)
	local out = {}
	for _, d in vf:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, partInfo(d, d.CFrame))
		end
	end
	return out
end

-- properties are read through the engine proxy (it also knows properties Lune cannot store,
-- e.g. Font); unknown ones fall back to nil
local WORLD = nil
local function serialize(realInst)
	local proxy = Engine.Wrap(realInst, WORLD)
	local inst = setmetatable({}, {
		__index = function(_, key)
			local ok, value = pcall(function()
				return proxy[key]
			end)
			if ok then
				if type(value) == "table" and rawget(value, "__real") then
					return rawget(value, "__real")
				end
				return value
			end
			return nil
		end,
	})
	local class = realInst.ClassName
	local node = { c = class, n = inst.Name }
	if GUI[class] then
		node.vis = inst.Visible
		node.size = udim2(inst.Size)
		node.pos = udim2(inst.Position)
		node.anchor = vec2(inst.AnchorPoint)
		node.bg = color(inst.BackgroundColor3)
		node.bgt = inst.BackgroundTransparency
		node.z = inst.ZIndex
		node.order = inst.LayoutOrder
		node.auto = enum(inst.AutomaticSize)
		node.clip = inst.ClipsDescendants
		node.rot = inst.Rotation
		if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
			node.text = inst.Text
			node.tc = color(inst.TextColor3)
			node.tt = inst.TextTransparency
			node.font = enum(inst.Font)
			node.ts = inst.TextSize
			node.scaled = inst.TextScaled
			node.wrap = inst.TextWrapped
			node.xa = enum(inst.TextXAlignment)
			node.ya = enum(inst.TextYAlignment)
			if class == "TextBox" then
				node.ph = inst.PlaceholderText
				node.phc = color(inst.PlaceholderColor3)
			end
		elseif class == "ImageLabel" or class == "ImageButton" then
			node.img = inst.Image
			node.ic = color(inst.ImageColor3)
		elseif class == "ScrollingFrame" then
			node.canvas = udim2(inst.CanvasSize)
			node.autocanvas = enum(inst.AutomaticCanvasSize)
			node.bar = inst.ScrollBarThickness
		elseif class == "ViewportFrame" then
			node.ic = color(inst.ImageColor3)
			node.amb = color(realInst.Ambient)
			node.lc = color(realInst.LightColor)
			node.ld = { realInst.LightDirection.X, realInst.LightDirection.Y, realInst.LightDirection.Z }
			local camera = realInst:FindFirstChildOfClass("Camera")
			if camera then
				local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = camera.CFrame:GetComponents()
				node.cam = { p = { x, y, z }, r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, fov = camera.FieldOfView }
			end
			node.parts = parts(realInst)
		end
	elseif class == "ScreenGui" then
		node.enabled = inst.Enabled
		node.order = inst.DisplayOrder
	elseif class == "UICorner" then
		node.radius = udim(inst.CornerRadius)
	elseif class == "UIStroke" then
		node.th = inst.Thickness
		node.col = color(inst.Color)
		node.tr = inst.Transparency
		node.mode = enum(inst.ApplyStrokeMode)
		node.on = inst.Enabled
	elseif class == "UIGradient" then
		local cs, ts = {}, {}
		for _, k in inst.Color.Keypoints do
			table.insert(cs, { k.Time, k.Value.R, k.Value.G, k.Value.B })
		end
		for _, k in inst.Transparency.Keypoints do
			table.insert(ts, { k.Time, k.Value })
		end
		node.cs, node.trs, node.rot, node.on = cs, ts, inst.Rotation, inst.Enabled
	elseif class == "UIPadding" then
		node.pad = { udim(inst.PaddingLeft), udim(inst.PaddingRight), udim(inst.PaddingTop), udim(inst.PaddingBottom) }
	elseif class == "UIListLayout" then
		node.dir = enum(inst.FillDirection)
		node.ha = enum(inst.HorizontalAlignment)
		node.va = enum(inst.VerticalAlignment)
		node.padding = udim(inst.Padding)
		node.sort = enum(inst.SortOrder)
	elseif class == "UIGridLayout" then
		node.cell = udim2(inst.CellSize)
		node.cellpad = udim2(inst.CellPadding)
		node.dir = enum(inst.FillDirection)
		node.ha = enum(inst.HorizontalAlignment)
		node.va = enum(inst.VerticalAlignment)
		node.sort = enum(inst.SortOrder)
	elseif class == "UIScale" then
		node.scale = inst.Scale
	elseif class == "UISizeConstraint" then
		node.min = vec2(inst.MinSize)
		node.max = vec2(inst.MaxSize)
	elseif class == "UITextSizeConstraint" then
		node.maxts = inst.MaxTextSize
		node.mints = inst.MinTextSize
	else
		return nil
	end
	if class ~= "ViewportFrame" then
		local children = {}
		for _, child in realInst:GetChildren() do
			local s = serialize(child)
			if s then
				table.insert(children, s)
			end
		end
		node.kids = children
	end
	return node
end

local function blurSize(world)
	local lighting = real(world.Game:GetService("Lighting"))
	local size = 0
	for _, child in lighting:GetChildren() do
		if child:IsA("BlurEffect") and child.Enabled then
			size = math.max(size, child.Size)
		end
	end
	return size
end

local WORLD_RADIUS = 280

local function isCharacterPart(d): boolean
	local model = d:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- the 3D world a player sees behind the UI: the client's camera, map, local effects and
-- enemy models, plus the hero models (built on the server; the offline engine does not
-- move welded parts, so they are re-posed onto the character's current root)
local function worldOf(client)
	local ws = real(client.Game:GetService("Workspace"))
	local camera = client.Camera -- the engine's camera (a plain table set by the client scripts)
	if not camera then
		return nil
	end
	local camCF = camera.CFrame
	local camPos = camCF.Position
	if camPos.Magnitude < 1 then
		return nil -- the default camera script does not run offline: no scripted camera yet
	end
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = camCF:GetComponents()
	local out = {
		cam = { p = { x, y, z }, r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, fov = camera.FieldOfView },
		parts = {},
		lights = {},
		shadows = {},
	}
	local function near(p): boolean
		return (p - camPos).Magnitude < WORLD_RADIUS
	end
	for _, d in ws:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Transparency < 0.98 and near(d.CFrame.Position) and not isCharacterPart(d) then
				table.insert(out.parts, partInfo(d, d.CFrame))
			end
		elseif d:IsA("PointLight") and d.Enabled and d.Parent:IsA("BasePart") and near(d.Parent.CFrame.Position) then
			local lp = d.Parent.CFrame.Position
			table.insert(out.lights, { p = { lp.X, lp.Y, lp.Z }, range = d.Range, brightness = d.Brightness, c = color(d.Color) })
		end
	end
	local server = real(Engine.Server.Game:GetService("Workspace"))
	for _, character in server:GetChildren() do
		local root = character:IsA("Model") and character:FindFirstChild("HumanoidRootPart")
		local hero = character:IsA("Model") and character:FindFirstChild("HeroModel")
		local heroRoot = hero and hero:FindFirstChild("HeroRoot")
		if root and heroRoot and near(root.CFrame.Position) then
			-- the client's copy of the root has the up-to-date position
			local clientChar = ws:FindFirstChild(character.Name)
			local clientRoot = clientChar and clientChar:FindFirstChild("HumanoidRootPart")
			local rootCF = if clientRoot then clientRoot.CFrame else root.CFrame
			local delta = rootCF * heroRoot.CFrame:Inverse()
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.98 and (d:IsDescendantOf(hero) or d.Name == "LobbyDecor") then
					table.insert(out.parts, partInfo(d, delta * d.CFrame))
				end
			end
			local feet = rootCF.Position - Vector3.new(0, 2.95, 0)
			table.insert(out.shadows, { { feet.X, feet.Y, feet.Z }, 1.9 })
		end
	end
	-- lighting: the server's (MapBuilder: time of day, haze; the offline engine does not
	-- replicate Lighting) + the client's local effects (hub depth of field, difficulty mood)
	local serverLighting = real(Engine.Server.Game:GetService("Lighting"))
	local lighting = real(client.Game:GetService("Lighting"))
	local clock = serverLighting.ClockTime
	local a = (clock - 6) / 12 * math.pi
	local sun = Vector3.new(-math.cos(a) * 0.6, math.sin(a), 0.45).Unit
	local amb = serverLighting.OutdoorAmbient
	out.light = {
		sun = { -sun.X, -sun.Y, -sun.Z },
		ambient = { 0.45 + amb.R * 0.35, 0.45 + amb.G * 0.35, 0.5 + amb.B * 0.35 },
	}
	local effects = {}
	for _, child in serverLighting:GetChildren() do
		table.insert(effects, child)
	end
	for _, child in lighting:GetChildren() do
		table.insert(effects, child)
	end
	for _, child in effects do
		if child:IsA("Atmosphere") then
			out.light.fogDensity = child.Density * 0.012
			out.light.fogColor = color(child.Color)
		elseif child:IsA("DepthOfFieldEffect") and child.Enabled then
			out.dof = { focus = child.FocusDistance, radius = child.InFocusRadius, blur = child.FarIntensity * 6 }
		elseif child:IsA("ColorCorrectionEffect") and child.Enabled then
			local t = child.TintColor
			if t.R < 0.99 or t.G < 0.99 or t.B < 0.99 then
				out.tint = { t.R, t.G, t.B, 0.12 }
			end
		end
	end
	return out
end

local function export(world, name: string, note: string?)
	WORLD = world
	local gui = real(world.LocalPlayer:FindFirstChild("PlayerGui"))
	local guis = {}
	for _, child in gui:GetChildren() do
		if child:IsA("ScreenGui") then
			table.insert(guis, serialize(child))
		end
	end
	fs.writeFile(OUT .. "/" .. name .. ".json", serde.encode("json", {
		scene = name,
		note = note or "",
		touch = world.Touch == true,
		blur = blurSize(world),
		guis = guis,
		world = worldOf(world),
	}))
	print("exported " .. name)
end

---------------------------------------------------------------------------
if not fs.isDir("build") then
	fs.writeDir("build")
end
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
local server = Engine.StartServer()
local PM = Engine.Module(server, "ServerScriptService.Server.Services.PlayerManager")
local GM = Engine.Module(server, "ServerScriptService.Server.Services.GameManager")

local alice, alicePlayer = Engine.AddPlayer("Alice")
Engine.Step(1)
local session = PM:Get(alicePlayer)
-- a player a few runs in: some coins and fragments, a few unlocks, a camp, a live event
session.Data.Coins = 1250
session.Data.Fragments = 23
session.Data.Stats.Runs = 4
session.Data.Stats.Kills = 1840
session.Data.Stats.BestTime = 412
session.Data.Stats.BestLevel = 21
session.Data.Heroes.Hunter = true
session.Data.Weapons.Meteor = true
session.Data.Seen.Weapons.BasicBlaster = true
session.Data.Seen.Weapons.Meteor = true
session.Data.Seen.Events.Percent67 = true
session.Data.Collection.Goober = 400
session.Data.Collection.Skitter = 120
session.Data.Collection.TheGiant = 1
session.Data.Cosmetics.Owned["Hat.Cone"] = true
session.Data.Cosmetics.New["Hat.Cone"] = true
session.Data.Afk.Slots[1] = "Tank"
session.Data.Afk.Since = os.time() - 50 * 60
-- difficulty: CALM and HUNT done, HORDE selected
session.Data.Difficulty.Best[1] = { Time = 740, Bosses = 3, Wins = 1 }
session.Data.Difficulty.Best[2] = { Time = 655, Bosses = 2, Wins = 0 }
session.Data.Difficulty.Cleared[1] = true
session.Data.Difficulty.Selected = 3
local cd = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
local lobby = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController")
cd:Fire("BuyMeta", "Might")
Engine.Step(1)
PM:Sync(alicePlayer)
Engine.Step(1)

export(alice, "hub", "lobby hub")
for _, scene in {
	{ "More" },
	{ "Heroes" },
	{ "Abilities" },
	{ "Shop" },
	{ "Shop", "Cosmetics" },
	{ "Shop", "Passes" },
	{ "Achievements" },
	{ "Collection" },
	{ "Challenges" },
	{ "AfkCamp" },
	{ "Party" },
	{ "Daily" },
	{ "Profile" },
	{ "Settings" },
	{ "Codes" },
	{ "Statistics" },
	{ "Leaderboard" },
	{ "Difficulty" },
	{ "HowToPlay" },
} do
	lobby:OpenPanel(scene[1], false, scene[2])
	Engine.Step(1)
	export(alice, "panel_" .. string.lower(scene[1] .. (if scene[2] then "_" .. scene[2] else "")))
end
lobby:ClosePanel()
Engine.Step(0.5)

-- a run: play ~40 s, then jump to the first boss
local runClient = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.RunClient")
local levelUp = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LevelUpController")
cd:Fire("SelectDifficulty", 2) -- the classic tier: the scripted run below is tuned for it
Engine.Step(0.5)
cd:Fire("StartRun")
Engine.Step(0.5)
local run = GM.Entries[alicePlayer].Run
local shotLevelUp = false
local function play(seconds: number)
	for _ = 1, math.floor(seconds / 0.1) do
		if run.Ended then
			break
		end
		if levelUp:IsOpen() and not levelUp.Busy then
			if not shotLevelUp and run.Level >= 3 then
				shotLevelUp = true
				Engine.Step(0.6)
				export(alice, "levelup", "level-up offer")
			end
			levelUp:Pick(Bot.Pick(run))
		end
		if not run:IsPaused() then
			local dx, dz = Bot.Direction(run, 1)
			local speed = run.Stats.WalkSpeed * 0.1
			Engine.MoveCharacter("Alice", Vector3.new(run.PX + dx * speed, ARENA_Y, run.PZ + dz * speed))
		end
		Engine.Step(0.1, 0.05)
	end
end
play(45)
Engine.Step(0.5)
export(alice, "hud", "in-run HUD")
cd:Fire("Admin", "time", "177")
Engine.Step(0.2)
play(8)
Engine.Step(0.5)
export(alice, "hud_boss", "in-run HUD with a boss")
cd:Fire("Admin", "killall", "")
play(4)
cd:Fire("Admin", "event", "Luck67")
Engine.Step(3.2)
export(alice, "event67", "a 67 event banner")
play(3)
cd:Fire("Admin", "evolve", "")
Engine.Step(0.8)
export(alice, "levelup_evolution", "an evolution card")
play(2)
cd:Fire("Pause", true)
local hud = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
hud:TogglePause(true)
Engine.Step(0.5)
export(alice, "pause", "pause menu")
hud:TogglePause(false)
Engine.Step(0.3)
cd:Fire("Admin", "die", "")
Engine.Step(0.6)
export(alice, "death", "death screen")
cd:Fire("GiveUp")
Engine.Step(1.5)
export(alice, "results", "results")
print("run level " .. tostring(run.Level) .. " time " .. tostring(math.floor(run.Time)))

-- phone
local bob = Engine.AddPlayer("Bob", { Touch = true })
Engine.Step(1)
export(bob, "phone_hub", "hub on a phone")
local bobCd = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
bobCd:Fire("StartRun")
Engine.Step(8)
export(bob, "phone_hud", "HUD on a phone")
print("errors: " .. #Engine.Errors)
for i, e in Engine.Errors do
	if i <= 5 then
		print(e)
	end
end
