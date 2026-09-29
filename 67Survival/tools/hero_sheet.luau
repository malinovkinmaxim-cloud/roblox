--!nocheck
--[[
	Hero turnaround export: builds heroes with the REAL shared/HeroModels.lua (offline engine,
	anchored like a menu preview) and writes build/heroes/<Key>.json (every part: position,
	rotation, size, colour, material, shape, mesh) for tools/hero_sheet.py.

	lune run tools/hero_sheet.luau -- [Key ...] [--skin Name] [--hat Name]      (default: every hero)
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("../tests/engine")

local OUT = "build/heroes"

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

local function partInfo(d)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
	local info = {
		name = d.Name,
		p = { x, y, z },
		r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		s = { d.Size.X, d.Size.Y, d.Size.Z },
		c = { d.Color.R, d.Color.G, d.Color.B },
		t = d.Transparency,
		shape = shapeOf(d),
		mat = d.Material.Name,
		neon = d.Material.Name == "Neon",
	}
	local gui = d:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if label then
		info.text = { value = label.Text, c = { label.TextColor3.R, label.TextColor3.G, label.TextColor3.B } }
	end
	local mesh = d:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		info.mesh = { type = mesh.MeshType.Name, scale = { mesh.Scale.X, mesh.Scale.Y, mesh.Scale.Z }, offset = { mesh.Offset.X, mesh.Offset.Y, mesh.Offset.Z } }
	end
	return info
end

local keys, skin, hat = {}, nil, nil
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--skin" then
		skin = process.args[i + 1]
		i += 1
	elseif a == "--hat" then
		hat = process.args[i + 1]
		i += 1
	else
		table.insert(keys, a)
	end
	i += 1
end

local server = Engine.StartServer()
local HeroModels = Engine.Module(server, "ReplicatedStorage.Modules.HeroModels")
local HeroData = Engine.Module(server, "ReplicatedStorage.Modules.HeroData")
if #keys == 0 then
	for _, def in HeroData.List do
		table.insert(keys, def.Key)
	end
end
if not fs.isDir("build") then
	fs.writeDir("build")
end
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end

for _, key in keys do
	local folder = Engine.Wrap(roblox.Instance.new("Folder"), server)
	local parts = HeroModels.Build(key, roblox.CFrame.new(), folder, { Skin = skin, Hat = hat, Ring = false })
	local out = {}
	for _, p in parts do
		table.insert(out, partInfo(rawget(p, "__real") or p))
	end
	local hero = HeroModels.Heroes[key]
	fs.writeFile(OUT .. "/" .. key .. ".json", serde.encode("json", { key = key, top = HeroModels.Top(key), count = #hero.Pieces, parts = out }))
	print(string.format("%-10s %2d pieces", key, #hero.Pieces))
end
