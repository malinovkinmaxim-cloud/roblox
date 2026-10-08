--[[
	EnemyBuilder - rebuilds the bestiary's enemy models as real Models in
	ReplicatedStorage/Enemies/<difficulty>/<Key>, to open and tweak by hand.

	It never runs on its own (a ModuleScript in ServerStorage/_Tools). In Studio, in Edit mode,
	paste into the Command Bar:

		require(game.ServerStorage._Tools.EnemyBuilder).Build()

	It builds every model of shared/EnemyData.lua with Role (the bestiary) through the game's own
	model code (StarterPlayerScripts/Client/Render/EnemyModels.lua + BestiaryModels.lua), stands
	each one on the ground, lays them out in rows (one row per difficulty, in front of the
	origin) and replaces the folder's old models. Your own changes in the folder are LOST when you
	run it again: rebuild first, tweak after.
	The game builds enemies in code; set the attribute UseInGame = true on
	ReplicatedStorage/Enemies to make it use the Models in there (Render/EnemyModels.FromStudio).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local EnemyBuilder = {}

local FOLDERS = { "1 CALM - Meadow", "2 HUNT - Graveyard", "3 HORDE - Desert", "4 NIGHTMARE - Frostbite", "5 INFERNO - Volcano", "6 OBLIVION - Cyber Glitch", "7 THE 67 - Void" }

-- the folder of a model: its difficulty (a minion goes with its boss's difficulty)
local function difficultyOf(def): number
	if def.MinTier then
		return def.MinTier
	end
	local THEMES = { Meadow = 1, Graveyard = 2, Desert = 3, Frostbite = 4, Volcano = 5, Cyber = 6, Void = 7 }
	return THEMES[def.Theme or ""] or 7
end

function EnemyBuilder.Build(): number
	local EnemyData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyData")) :: any
	local EnemyModels = require(StarterPlayer.StarterPlayerScripts:WaitForChild("Client"):WaitForChild("Render"):WaitForChild("EnemyModels")) :: any
	local root = ReplicatedStorage:FindFirstChild("Enemies")
	local useInGame = root and root:GetAttribute("UseInGame")
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "Enemies"
	if useInGame ~= nil then
		root:SetAttribute("UseInGame", useInGame)
	else
		root:SetAttribute("UseInGame", false)
	end
	local folders = {}
	for i, name in FOLDERS do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		folders[i] = f
	end
	local count = 0
	local column = {}
	for _, def in EnemyData.List do
		if def.Role then
			local tier = difficultyOf(def)
			local model = EnemyModels.Export(def)
			-- lay them out: a row per difficulty, side by side
			local n = column[tier] or 0
			column[tier] = n + 1
			model:PivotTo(CFrame.new(n * 30, 0, -tier * 40) * model:GetPivot())
			model.Parent = folders[tier]
			count += 1
		end
	end
	root.Parent = ReplicatedStorage
	print(string.format("EnemyBuilder: %d models in ReplicatedStorage/Enemies", count))
	return count
end

return EnemyBuilder
