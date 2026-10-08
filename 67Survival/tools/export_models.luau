--!nocheck
--[[
	Writes the bestiary's models as real Models for the Rojo build: models/Enemies/<difficulty>/
	<Key>.rbxm -> ReplicatedStorage/Enemies/<difficulty>/<Key> (to open and tweak in Studio).
	They are built by the game's own model code (Render/EnemyModels.Export, the same as
	ServerStorage/_Tools/EnemyBuilder does in Studio), laid out in a row per difficulty.

	lune run tools/export_models.luau        (tools/verify.sh runs it before the build)
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Engine = require("../tests/engine")

local OUT = "models/Enemies"
local FOLDERS = { "1 CALM - Meadow", "2 HUNT - Graveyard", "3 HORDE - Desert", "4 NIGHTMARE - Frostbite", "5 INFERNO - Volcano", "6 OBLIVION - Cyber Glitch", "7 THE 67 - Void" }
local THEMES = { Meadow = 1, Graveyard = 2, Desert = 3, Frostbite = 4, Volcano = 5, Cyber = 6, Void = 7 }

Engine.StartServer()
local client = Engine.AddPlayer("Alice")
Engine.Step(0.5)
local EnemyModels = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Render.EnemyModels")
local EnemyData = Engine.Module(client, "ReplicatedStorage.Modules.EnemyData")

if fs.isDir(OUT) then
	fs.removeDir(OUT)
end
fs.writeDir(OUT)
fs.writeFile(OUT .. "/init.meta.json", '{\n  "attributes": {\n    "UseInGame": false\n  }\n}\n')
for _, name in FOLDERS do
	fs.writeDir(OUT .. "/" .. name)
end
local column, count = {}, 0
for _, def in EnemyData.List do
	if def.Role then
		local tier = def.MinTier or THEMES[def.Theme or ""] or 7
		local model = EnemyModels.Export(def)
		local real = rawget(model, "__real") or model
		local n = column[tier] or 0
		column[tier] = n + 1
		local shift = roblox.CFrame.new(n * 30, 0, -tier * 40)
		for _, d in real:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = shift * d.CFrame
			end
		end
		fs.writeFile(OUT .. "/" .. FOLDERS[tier] .. "/" .. def.Key .. ".rbxm", roblox.serializeModel({ real }))
		count += 1
	end
end
print(string.format("%d models -> %s", count, OUT))
