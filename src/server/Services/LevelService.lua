--[[
	LevelService
	- Discovers level data modules in ServerStorage.Levels (any ModuleScript returning a level table).
	  Adding a level = adding a module. No code changes needed.
	- Validates them.
	- Hands out level slots and builds / destroys private level instances.
]]

local ServerStorage = game:GetService("ServerStorage")

local LevelBuilder = require(script.Parent.Parent.Level.LevelBuilder)
local LevelValidator = require(script.Parent.Parent.Level.LevelValidator)
local RoleConfig = require(game:GetService("ReplicatedStorage").Shared.RoleConfig)

local LevelService = {}
LevelService.Levels = {} -- [id] = def
LevelService.Order = {} -- sorted ids
LevelService.UsedSlots = {} -- [slot] = true

function LevelService:Init(services)
	self.Services = services
	self:LoadLevels()
end

function LevelService:LoadLevels()
	local folder = ServerStorage:FindFirstChild("Levels")
	if not folder then
		warn("[LevelService] ServerStorage.Levels is missing - no levels loaded")
		return
	end
	for _, child in folder:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end
		local ok, def = pcall(require, child)
		if not ok then
			warn("[LevelService] failed to load " .. child.Name .. ": " .. tostring(def))
			continue
		end
		local errors = LevelValidator.Validate(def)
		if #errors > 0 then
			for _, message in errors do
				warn("[LevelService] " .. child.Name .. ": " .. message)
			end
			-- keep loading valid-enough levels; only skip when fundamentally broken
			if type(def) ~= "table" or type(def.Id) ~= "number" or type(def.Elements) ~= "table" then
				continue
			end
		end
		if self.Levels[def.Id] then
			warn("[LevelService] duplicate level id " .. def.Id .. " in " .. child.Name)
			continue
		end
		self.Levels[def.Id] = def
		table.insert(self.Order, def.Id)
	end
	table.sort(self.Order)
	print(string.format("[LevelService] loaded %d levels", #self.Order))
end

function LevelService:GetLevel(id: number)
	return self.Levels[id]
end

function LevelService:GetNextLevelId(id: number): number?
	local index = table.find(self.Order, id)
	if index then
		return self.Order[index + 1]
	end
	return nil
end

function LevelService:GetFirstLevelId(): number?
	return self.Order[1]
end

-- Short, client-safe description of every level (no geometry).
function LevelService:GetCatalog()
	local catalog = {}
	for _, id in self.Order do
		local def = self.Levels[id]
		local roleHint
		if type(def.Role) == "string" and not def.RoleHidden then
			local roleInfo = RoleConfig.Get(def.Role)
			roleHint = roleInfo and roleInfo.DisplayName or def.Role
		else
			roleHint = RoleConfig.HiddenName
		end
		local checkpoints = 0
		for _, spec in def.Elements do
			if spec.Type == "Checkpoint" then
				checkpoints += 1
			end
		end
		table.insert(catalog, {
			Id = id,
			Name = def.Name,
			Subtitle = def.Subtitle or "",
			ParTime = def.ParTime,
			RoleHint = roleHint,
			Checkpoints = checkpoints,
			Chapter = def.Chapter or 1,
			DuoFriendly = def.DuoFriendly ~= false,
		})
	end
	return catalog
end

function LevelService:AllocateSlot(): number
	local slot = 0
	while self.UsedSlots[slot] do
		slot += 1
	end
	self.UsedSlots[slot] = true
	return slot
end

function LevelService:FreeSlot(slot: number)
	self.UsedSlots[slot] = nil
end

function LevelService:BuildInstance(levelId: number, ownerName: string)
	local def = self.Levels[levelId]
	assert(def, "unknown level " .. tostring(levelId))
	local slot = self:AllocateSlot()
	local ok, inst = pcall(LevelBuilder.Build, def, slot, ownerName)
	if not ok then
		self:FreeSlot(slot)
		error(inst)
	end
	return inst
end

function LevelService:DestroyInstance(inst)
	if not inst or inst.Destroyed then
		return
	end
	LevelBuilder.Destroy(inst)
	self:FreeSlot(inst.Slot)
end

return LevelService
