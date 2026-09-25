--[[
	LevelValidator
	Static checks for level data modules. Runs on server start (warns) and in tests (fails).
	Pure Luau: no Instances are touched, so it can run outside Roblox (Lune tests).
]]

local LevelValidator = {}

local KNOWN_TYPES = {
	Platform = true,
	Decor = true,
	Start = true,
	Checkpoint = true,
	Finish = true,
	Sign = true,
	Kill = true,
	Laser = true,
	RotatingBeam = true,
	MovingPlatform = true,
	Disappearing = true,
	Falling = true,
	Fake = true,
	LaunchPad = true,
	TeleportPad = true,
	Button = true,
	Door = true,
}

local TARGET_TYPES = {
	Door = true,
	Laser = true,
	MovingPlatform = true,
}

local KNOWN_ROLES = {
	Follower = true,
	Rival = true,
	Shadow = true,
	Ally = true,
	Troll = true,
}

local ACTIVATORS = { Any = true, Player = true, Doppel = true }
local MODES = { Toggle = true, Timed = true, Once = true, Hold = true }

local function roleNames(role): { string }
	if type(role) == "string" then
		return { role }
	elseif type(role) == "table" and type(role.Pool) == "table" then
		return role.Pool
	end
	return {}
end

function LevelValidator.Validate(def): { string }
	local errors = {}
	local function err(message: string)
		table.insert(errors, string.format("Level %s: %s", tostring(def and def.Id), message))
	end

	if type(def) ~= "table" then
		return { "level module must return a table" }
	end
	if type(def.Id) ~= "number" then
		err("Id must be a number")
	end
	if type(def.Name) ~= "string" then
		err("Name must be a string")
	end
	if type(def.ParTime) ~= "number" then
		err("ParTime must be a number")
	end
	if type(def.Elements) ~= "table" then
		err("Elements must be a table")
		return errors
	end

	local roles = roleNames(def.Role)
	if #roles == 0 then
		err("Role must be a role name or { Pool = {...} }")
	end
	local needsRoute = false
	for _, name in roles do
		if not KNOWN_ROLES[name] then
			err("unknown role " .. tostring(name))
		end
		if name == "Rival" then
			needsRoute = true
		end
	end

	local ids = {}
	local starts, finishes = 0, 0
	local checkpoints = {}
	local fakeGroups = {}
	for index, spec in def.Elements do
		if type(spec) ~= "table" then
			err("element #" .. index .. " is not a table")
			continue
		end
		if not KNOWN_TYPES[spec.Type] then
			err("element #" .. index .. " has unknown Type " .. tostring(spec.Type))
			continue
		end
		if spec.Id ~= nil then
			if ids[spec.Id] then
				err("duplicate element id " .. tostring(spec.Id))
			end
			ids[spec.Id] = spec
		end
		if spec.Pos == nil then
			err("element #" .. index .. " (" .. spec.Type .. ") has no Pos")
		end
		if spec.Type == "Start" then
			starts += 1
		elseif spec.Type == "Finish" then
			finishes += 1
		elseif spec.Type == "Checkpoint" then
			if type(spec.Index) ~= "number" then
				err("checkpoint without Index")
			elseif checkpoints[spec.Index] then
				err("duplicate checkpoint index " .. spec.Index)
			else
				checkpoints[spec.Index] = spec
			end
			if spec.SetRole ~= nil and not KNOWN_ROLES[spec.SetRole] then
				err("checkpoint " .. tostring(spec.Index) .. " SetRole unknown: " .. tostring(spec.SetRole))
			end
			if spec.SetRole == "Rival" then
				needsRoute = true
			end
		elseif spec.Type == "Button" then
			if not ACTIVATORS[spec.Activator] then
				err("button " .. tostring(spec.Id) .. " bad Activator " .. tostring(spec.Activator))
			end
			if not MODES[spec.Mode] then
				err("button " .. tostring(spec.Id) .. " bad Mode " .. tostring(spec.Mode))
			end
			if type(spec.Targets) ~= "table" or #spec.Targets == 0 then
				err("button " .. tostring(spec.Id) .. " has no Targets")
			end
		elseif spec.Type == "Fake" then
			if spec.Group then
				fakeGroups[spec.Group] = (fakeGroups[spec.Group] or 0) + 1
			end
		elseif spec.Type == "MovingPlatform" then
			if spec.Powered and not spec.Id then
				err("powered moving platform needs an Id")
			end
		end
	end

	if starts ~= 1 then
		err("needs exactly one Start (has " .. starts .. ")")
	end
	if finishes ~= 1 then
		err("needs exactly one Finish (has " .. finishes .. ")")
	end
	local count = 0
	for _ in checkpoints do
		count += 1
	end
	for i = 1, count do
		if not checkpoints[i] then
			err("checkpoint indices must be 1.." .. count .. " without gaps (missing " .. i .. ")")
		end
	end

	-- button targets must exist and be targetable
	for _, spec in def.Elements do
		if type(spec) == "table" and spec.Type == "Button" and type(spec.Targets) == "table" then
			for _, targetId in spec.Targets do
				local target = ids[targetId]
				if not target then
					err("button " .. tostring(spec.Id) .. " targets missing id " .. tostring(targetId))
				elseif not TARGET_TYPES[target.Type] then
					err("button " .. tostring(spec.Id) .. " targets non-targetable " .. target.Type)
				end
			end
		end
	end

	-- fake groups
	if def.FakeGroups then
		for group, groupDef in def.FakeGroups do
			local size = fakeGroups[group] or 0
			if size == 0 then
				err("FakeGroups." .. group .. " has no Fake elements")
			elseif (groupDef.Fake or 1) >= size then
				err("FakeGroups." .. group .. " would make every platform fake")
			end
		end
	end
	for group in fakeGroups do
		if not (def.FakeGroups and def.FakeGroups[group]) then
			err("Fake group " .. group .. " missing from FakeGroups")
		end
	end

	-- route
	if needsRoute and (type(def.Route) ~= "table" or #def.Route < 2) then
		err("Rival levels need a Route with at least 2 nodes")
	end
	if type(def.Route) == "table" then
		local nodeIds = {}
		local hasFinish = false
		for index, node in def.Route do
			if type(node.Id) ~= "string" then
				err("route node #" .. index .. " needs a string Id")
			elseif nodeIds[node.Id] then
				err("duplicate route node " .. node.Id)
			else
				nodeIds[node.Id] = node
			end
			if node.Finish then
				hasFinish = true
			end
		end
		for _, node in def.Route do
			for _, key in { "Next", "Fallback" } do
				local list = node[key]
				if list ~= nil then
					for _, nextId in list do
						if not nodeIds[nextId] then
							err("route node " .. tostring(node.Id) .. " " .. key .. " -> missing node " .. tostring(nextId))
						end
					end
				end
			end
			if node.On ~= nil and not ids[node.On] then
				err("route node " .. tostring(node.Id) .. " On -> missing element " .. tostring(node.On))
			end
			if node.Gate ~= nil and not ids[node.Gate] then
				err("route node " .. tostring(node.Id) .. " Gate -> missing element " .. tostring(node.Gate))
			end
		end
		if needsRoute and not hasFinish then
			err("Rival route needs a node with Finish = true")
		end
		-- every checkpoint that can respawn a rival needs a node
		if needsRoute then
			local mapped = {}
			for _, node in def.Route do
				if node.Checkpoint ~= nil then
					mapped[node.Checkpoint] = true
				end
			end
			if not mapped[def.RivalStartCheckpoint or 0] then
				err("Rival route needs a node with Checkpoint = " .. tostring(def.RivalStartCheckpoint or 0))
			end
		end
	end

	return errors
end

return LevelValidator
