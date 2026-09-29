--!nocheck
--[[
	Enemy model export: builds enemies with the REAL client Render/EnemyModels.lua (offline
	engine), standing on the ground (y = 0) and facing -Z, and writes build/enemies/<Key>.json
	for tools/enemy_sheet.py.

	lune run tools/enemy_sheet.luau -- [Key ...]   (default: the mini-bosses of 67 TOWN + minions)
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("../tests/engine")

local OUT = "build/enemies"
local keys = {}
for _, a in process.args do
	table.insert(keys, a)
end
if #keys == 0 then
	keys = { "BigQuack", "Duckling", "Cartzilla", "JackpotJimmy", "CoinStack", "Six", "Seven", "TickTock" }
end

local function shapeOf(d): string
	if d:IsA("Part") then
		return d.Shape.Name
	end
	return "Block"
end

local server = Engine.StartServer()
local client = Engine.AddPlayer("Alice")
Engine.Step(0.5)
local EnemyModels = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Render.EnemyModels")
local EnemyData = Engine.Module(client, "ReplicatedStorage.Modules.EnemyData")
if not fs.isDir("build") then
	fs.writeDir("build")
end
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
for _, key in keys do
	local def = EnemyData.ByKey[key]
	local model, root, info = EnemyModels.Build(def, "")
	-- the root was built at y = -400: lift everything so the model stands on y = 0
	local lift = roblox.CFrame.new(0, 400 + info.Height, 0)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local r = rawget(d, "__real") or d
			local cf = lift * r.CFrame
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			table.insert(out, {
				name = r.Name,
				p = { x, y, z },
				r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
				s = { r.Size.X, r.Size.Y, r.Size.Z },
				c = { r.Color.R, r.Color.G, r.Color.B },
				t = r.Transparency,
				shape = shapeOf(r),
				mat = r.Material.Name,
				neon = r.Material.Name == "Neon",
			})
		end
	end
	fs.writeFile(OUT .. "/" .. key .. ".json", serde.encode("json", { key = key, height = info.Height, top = info.Top + info.Height, count = #out, parts = out }))
	print(string.format("%-14s %2d parts, height %.1f, top %.1f", key, #out, info.Height, info.Top + info.Height))
end
