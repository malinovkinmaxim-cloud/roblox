--[[
	LevelBuilder
	Builds one private copy of a level (a "level instance") for one run.
	Every player gets their own instance so doors / buttons / doppelgängers never conflict.
]]

local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Elements = require(script.Parent.Elements)

local LevelBuilder = {}

local function getActiveLevelsFolder(): Folder
	local folder = Workspace:FindFirstChild("ActiveLevels")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ActiveLevels"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function shuffle(list, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Decide which platforms of every fake group are fake this run.
local function selectFakes(def, rng: Random): { [string]: boolean }
	local selection = {}
	if not def.FakeGroups then
		return selection
	end
	local groups: { [string]: { string } } = {}
	for _, spec in def.Elements do
		if spec.Type == "Fake" and spec.Group then
			groups[spec.Group] = groups[spec.Group] or {}
			table.insert(groups[spec.Group], spec.Id)
		end
	end
	for group, ids in groups do
		local groupDef = def.FakeGroups[group] or { Fake = 1 }
		local fakeCount = math.clamp(groupDef.Fake or 1, 0, #ids - 1)
		shuffle(ids, rng)
		for i = 1, fakeCount do
			selection[ids[i]] = true
		end
	end
	return selection
end

-- Buttons sharing a Shuffle group swap their targets randomly (e.g. "which button is the trap?").
local function shuffleButtonTargets(inst)
	local groups = {}
	for _, source in inst.Sources do
		local group = source.Spec.Shuffle
		if group then
			groups[group] = groups[group] or {}
			table.insert(groups[group], source)
		end
	end
	for _, sources in groups do
		local targetSets = {}
		local badFlags = {}
		for i, source in sources do
			targetSets[i] = source.Targets
			badFlags[i] = source.Bad
		end
		local order = {}
		for i = 1, #sources do
			order[i] = i
		end
		shuffle(order, inst.Rng)
		for i, source in sources do
			source.Targets = targetSets[order[i]]
			source.Bad = badFlags[order[i]]
		end
	end
end

local function buildLinks(inst)
	for _, source in inst.Sources do
		for _, targetId in source.Targets do
			local target = inst.ById[targetId]
			if target then
				inst.Links[targetId] = inst.Links[targetId] or {}
				table.insert(inst.Links[targetId], source)
				-- visual language: a door takes the colour of what opens it
				if target.Type == "Door" and not target.IsBridge then
					target.Part.Color = source.BaseColor:Lerp(Color3.fromRGB(45, 50, 70), 0.5)
				end
			else
				warn(string.format("[LevelBuilder] level %s: button %s targets unknown %s", tostring(inst.Def.Id), tostring(source.Id), tostring(targetId)))
			end
		end
	end
end

local function buildRoute(inst)
	local def = inst.Def
	local route = {
		Nodes = {},
		Order = {},
		ByCheckpoint = {},
	}
	inst.Route = route
	if type(def.Route) ~= "table" then
		return
	end
	for index, nodeSpec in def.Route do
		local node = {
			Id = nodeSpec.Id,
			Spec = nodeSpec,
			Index = index,
			WorldPos = inst.OriginPos + nodeSpec.Pos,
			Next = nodeSpec.Next,
			Weights = nodeSpec.Weights,
			Checkpoint = nodeSpec.Checkpoint,
			Safe = nodeSpec.Safe == true or nodeSpec.Checkpoint ~= nil,
			Gate = nodeSpec.Gate,
			Timeout = nodeSpec.Timeout or Config.RIVAL_BLOCKED_TIMEOUT,
			Fallback = nodeSpec.Fallback,
			AvoidVisited = nodeSpec.AvoidVisited == true,
			Hazard = nodeSpec.Hazard == true,
			Jump = nodeSpec.Jump,
			Finish = nodeSpec.Finish == true,
			Pause = nodeSpec.Pause,
			Attach = nil,
			AttachOffset = nil,
		}
		if nodeSpec.On then
			local element = inst.ById[nodeSpec.On]
			node.Attach = element
			if element and element.Type == "MovingPlatform" then
				node.AttachOffset = element.BaseCFrame:PointToObjectSpace(node.WorldPos)
			end
		end
		route.Nodes[node.Id] = node
		table.insert(route.Order, node.Id)
		if node.Checkpoint ~= nil then
			route.ByCheckpoint[node.Checkpoint] = node.Id
		end
	end
	-- default Next = following node in the list
	for index, id in route.Order do
		local node = route.Nodes[id]
		if node.Next == nil and not node.Finish and route.Order[index + 1] then
			node.Next = { route.Order[index + 1] }
		end
	end
end

--[[
	Build(def, slotIndex, ownerName, seed?) -> LevelInstance
]]
function LevelBuilder.Build(def, slotIndex: number, ownerName: string, seed: number?)
	local originPos = Config.LEVEL_ORIGIN + Vector3.new(0, 0, slotIndex * Config.LEVEL_SLOT_SPACING)
	local model = Instance.new("Model")
	model.Name = string.format("Level%02d_%s", def.Id, ownerName)

	local inst = {
		Def = def,
		Slot = slotIndex,
		OriginPos = originPos,
		KillY = originPos.Y + (def.KillY or Config.KILL_Y_OFFSET),
		Model = model,
		Geometry = newFolder("Geometry", model),
		Interactive = newFolder("Interactive", model),
		Blockers = newFolder("Blockers", model),
		Decor = newFolder("Decor", model),
		Actors = newFolder("Actors", model),
		Elements = {},
		ById = {},
		PartToElement = {},
		Checkpoints = {},
		CheckpointCount = 0,
		Sources = {},
		Links = {},
		Doors = {},
		Lasers = {},
		Beams = {},
		Movers = {},
		Cyclic = {},
		AllyTargets = {},
		StartCFrame = CFrame.new(originPos + Vector3.new(0, 3.2, 0)),
		DoppelStartCFrame = CFrame.new(originPos + Vector3.new(0, 3.2, -4)),
		FinishPart = nil,
		FinishElement = nil,
		Rng = Random.new(seed or math.floor(os.clock() * 1000) % 2 ^ 31),
		StartClock = os.clock(),
		StartServerTime = Workspace:GetServerTimeNow(),
		Destroyed = false,
	}
	inst.FakeSelection = selectFakes(def, inst.Rng)

	for index, spec in def.Elements do
		local builder = Elements.Builders[spec.Type]
		if not builder then
			warn(string.format("[LevelBuilder] level %s: unknown element type %s (#%d)", tostring(def.Id), tostring(spec.Type), index))
			continue
		end
		local ok, element = pcall(builder, inst, spec)
		if not ok then
			warn(string.format("[LevelBuilder] level %s: element #%d (%s) failed: %s", tostring(def.Id), index, spec.Type, tostring(element)))
			continue
		end
		if element then
			table.insert(inst.Elements, element)
			if element.Id then
				inst.ById[element.Id] = element
			end
			if element.Kind and element.Part then
				inst.PartToElement[element.Part] = element
			end
			if spec.Type == "Checkpoint" then
				inst.CheckpointCount = math.max(inst.CheckpointCount, spec.Index)
			end
		end
	end

	shuffleButtonTargets(inst)
	buildLinks(inst)
	buildRoute(inst)

	for _, beam in inst.Beams do
		beam.Part:SetAttribute("SpinStart", inst.StartServerTime)
	end

	-- spatial query params (one set per instance, reused every tick)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { inst.Interactive }
	overlap.RespectCanCollide = false
	overlap.MaxParts = 24
	inst.OverlapParams = overlap

	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Include
	ground.FilterDescendantsInstances = { inst.Geometry, inst.Interactive, inst.Blockers }
	ground.RespectCanCollide = true
	inst.GroundParams = ground

	local blockers = RaycastParams.new()
	blockers.FilterType = Enum.RaycastFilterType.Include
	blockers.FilterDescendantsInstances = { inst.Blockers }
	blockers.RespectCanCollide = true
	inst.BlockerParams = blockers

	model.Parent = getActiveLevelsFolder()

	-- physics-driven parts must be owned by the server so every player sees the same thing
	for _, mover in inst.Movers do
		pcall(function()
			(mover.Part :: BasePart):SetNetworkOwner(nil)
		end)
	end

	return inst
end

function LevelBuilder.Destroy(inst)
	if inst.Destroyed then
		return
	end
	inst.Destroyed = true
	if inst.Model then
		inst.Model:Destroy()
	end
end

return LevelBuilder
