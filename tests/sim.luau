--[[
	Headless simulations of the AI roles against real level data.
	A fake actor replaces DoppelActor (no physics engine): ground = level floor surfaces,
	doors block while unpowered, fake platforms break when stood on, vanishing platforms blink,
	moving platforms move. The REAL role modules (Rival, Shadow) drive it.
]]

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local H = require("./harness")

local ObstacleService = H.Require("ServerScriptService.Server.Services.ObstacleService")

local Sim = {}

local ROOT = 3 -- root offset of the fake rig

---------------------------------------------------------------------------
-- World built from a level definition
---------------------------------------------------------------------------
local function buildWorld(def, seed)
	local rng = H.Random.new(seed)
	local world = {
		Def = def,
		Rng = rng,
		Clock = 0,
		Surfaces = {},
		Doors = {},
		Buttons = {},
		ById = {},
		Revealed = {},
	}

	-- fake selection per group (same rule as LevelBuilder)
	local fakeSelection = {}
	local groups = {}
	for _, spec in def.Elements do
		if spec.Type == "Fake" and spec.Group then
			groups[spec.Group] = groups[spec.Group] or {}
			table.insert(groups[spec.Group], spec.Id)
		end
	end
	for group, ids in groups do
		local count = math.clamp((def.FakeGroups[group] or { Fake = 1 }).Fake or 1, 0, #ids - 1)
		for i = #ids, 2, -1 do
			local j = rng:NextInteger(1, i)
			ids[i], ids[j] = ids[j], ids[i]
		end
		for i = 1, count do
			fakeSelection[ids[i]] = true
		end
	end

	for _, spec in def.Elements do
		local t = spec.Type
		local element = { Id = spec.Id, Type = t, Spec = spec }
		if spec.Id then
			world.ById[spec.Id] = element
		end
		local function surface(center, size, top, extra)
			local s = { Center = center, Size = size, Top = top, Element = element }
			if extra then
				for k, v in extra do
					s[k] = v
				end
			end
			table.insert(world.Surfaces, s)
			return s
		end
		if t == "Platform" or t == "Falling" then
			surface(spec.Pos, spec.Size, spec.Pos.Y + spec.Size.Y / 2)
		elseif t == "Start" or t == "Checkpoint" or t == "Finish" then
			surface(spec.Pos, spec.Size, spec.Pos.Y)
		elseif t == "Fake" then
			element.IsFake = fakeSelection[spec.Id] == true
			element.Revealed = false
			surface(spec.Pos, spec.Size, spec.Pos.Y + spec.Size.Y / 2, { Fake = element })
		elseif t == "Disappearing" then
			element.Cycle = spec.Cycle
			element.Visible = true
			surface(spec.Pos, spec.Size, spec.Pos.Y + spec.Size.Y / 2, { Vanish = element })
		elseif t == "MovingPlatform" then
			local base = spec.Pos
			element.BaseCFrame = CFrame.new(base)
			element.Part = { CFrame = CFrame.new(base), Parent = true }
			element.Motion = spec.Motion
			surface(base, spec.Size, base.Y + spec.Size.Y / 2, { Mover = element })
		elseif t == "Door" then
			if spec.Bridge then
				local pos = spec.Pos + spec.OpenOffset
				surface(pos, spec.Size, pos.Y + spec.Size.Y / 2)
			else
				element.Powered = false
				element.Open = false
				table.insert(world.Doors, element)
			end
		elseif t == "Button" then
			element.Targets = table.clone(spec.Targets)
			element.Shuffle = spec.Shuffle
			element.Duration = spec.Duration or 6
			element.ActiveUntil = -1
			table.insert(world.Buttons, element)
		end
	end
	-- shuffle groups
	local shuffleGroups = {}
	for _, button in world.Buttons do
		if button.Shuffle then
			shuffleGroups[button.Shuffle] = shuffleGroups[button.Shuffle] or {}
			table.insert(shuffleGroups[button.Shuffle], button)
		end
	end
	for _, list in shuffleGroups do
		if rng:NextNumber() < 0.5 and #list == 2 then
			list[1].Targets, list[2].Targets = list[2].Targets, list[1].Targets
		end
	end
	return world
end

local function surfaceTop(world, s)
	if s.Mover then
		local p = s.Mover.Part.CFrame.Position
		return p, p.Y + s.Size.Y / 2
	end
	return s.Center, s.Top
end

local function surfaceSolid(s)
	if s.Fake and s.Fake.IsFake and s.Fake.Revealed then
		return false
	end
	if s.Vanish and not s.Vanish.Visible then
		return false
	end
	return true
end

-- returns the surface under a root position (or nil)
local function groundAt(world, rootPos, extra, narrow)
	local feet = rootPos.Y - ROOT
	local marginX, marginZ = 0.8, 0.5
	if narrow then
		marginX, marginZ = 0, 0
	end
	for _, s in world.Surfaces do
		if surfaceSolid(s) then
			local center, top = surfaceTop(world, s)
			-- same footprint as DoppelActor's FOOT_BOX (1.6 x 1.0)
			if math.abs(rootPos.X - center.X) <= s.Size.X / 2 + marginX and math.abs(rootPos.Z - center.Z) <= s.Size.Z / 2 + marginZ then
				if feet - top <= (extra or 1.3) and feet - top >= -1.5 then
					return s
				end
			end
		end
	end
	return nil
end

local function stepWorld(world, dt)
	world.Clock += dt
	local t = world.Clock
	for _, s in world.Surfaces do
		if s.Mover then
			local element = s.Mover
			element.Part.CFrame = CFrame.new(ObstacleService.MotionAt(element.BaseCFrame.Position, element.Motion, t))
		elseif s.Vanish then
			local cycle = s.Vanish.Cycle
			local period = (cycle.Visible or 2) + (cycle.Hidden or 1.5)
			local p = (t + (cycle.Phase or 0)) % period
			s.Vanish.Visible = p < (cycle.Visible or 2)
		end
	end
	for _, door in world.Doors do
		local powered = false
		for _, button in world.Buttons do
			if button.ActiveUntil > t and table.find(button.Targets, door.Id) then
				powered = true
			end
		end
		powered = powered or door.ForceOpen == true
		door.Powered = powered
		door.Open = powered
	end
end

local function blockedBetween(world, from, to)
	for _, door in world.Doors do
		if not door.Powered then
			local spec = door.Spec
			local x = spec.Pos.X
			if (from.X - x) * (to.X - x) < 0 or math.abs(to.X - x) < 0.8 then
				local alpha = if to.X ~= from.X then (x - from.X) / (to.X - from.X) else 0
				local z = from.Z + (to.Z - from.Z) * math.clamp(alpha, 0, 1)
				if math.abs(z - spec.Pos.Z) <= spec.Size.Z / 2 then
					return true
				end
			end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Fake actor with the DoppelActor API used by roles
---------------------------------------------------------------------------
local function newActor(world)
	local actor = {
		Position = Vector3.zero,
		Yaw = 0,
		RootOffset = ROOT,
		State = "Driven",
		Grounded = true,
		Frozen = false,
		Ghost = false,
		Destroyed = false,
		Deaths = 0,
		DiedAt = nil,
		Emote = nil,
	}
	function actor:IsAlive()
		return self.State ~= "Dead"
	end
	function actor:IsControllable()
		return self.State == "Driven"
	end
	function actor:Teleport(cf)
		self.Position = cf.Position
		self.State = "Driven"
	end
	function actor:Respawn(cf)
		self.Position = cf.Position
		self.State = "Driven"
		self.Frozen = false
	end
	function actor:Hold() end
	function actor:Glitch() end
	function actor:SetEmote(name)
		self.Emote = name
	end
	function actor:SetFrozen(frozen)
		self.Frozen = frozen
	end
	function actor:HasGroundAt(position, extra, narrow)
		return groundAt(world, position, extra, narrow) ~= nil
	end
	function actor:StartFall()
		self.State = "Dead"
		self.Deaths += 1
		self.DiedAt = world.Clock
	end
	function actor:DriveTo(position, yaw, grounded, opts)
		if self.State ~= "Driven" then
			return "busy"
		end
		if (position - self.Position).Magnitude > 12 then
			self.Position = position
			return "teleported"
		end
		if not (opts and opts.IgnoreBlockers) and blockedBetween(world, self.Position, position) then
			return "blocked"
		end
		if grounded and not (opts and opts.NoGroundCheck) then
			local s = groundAt(world, position)
			if not s then
				self.Position = position
				self:StartFall()
				return "fell"
			end
			if s.Fake and s.Fake.IsFake and not self.Ghost then
				s.Fake.Revealed = true -- it breaks under us
			end
		end
		self.Grounded = grounded
		self.Position = position
		if yaw then
			self.Yaw = yaw
		end
		return "ok"
	end
	return actor
end

---------------------------------------------------------------------------
-- Route (same rules as LevelBuilder.buildRoute)
---------------------------------------------------------------------------
local function buildRoute(world, def)
	local route = { Nodes = {}, Order = {}, ByCheckpoint = {} }
	for index, spec in def.Route do
		local node = {
			Id = spec.Id,
			Index = index,
			WorldPos = spec.Pos,
			Next = spec.Next,
			Weights = spec.Weights,
			Checkpoint = spec.Checkpoint,
			Safe = spec.Safe == true or spec.Checkpoint ~= nil,
			Gate = spec.Gate,
			Timeout = spec.Timeout or 2.5,
			Fallback = spec.Fallback,
			AvoidVisited = spec.AvoidVisited == true,
			Hazard = spec.Hazard == true,
			Jump = spec.Jump,
			Finish = spec.Finish == true,
			Pause = spec.Pause,
		}
		if spec.On then
			local element = world.ById[spec.On]
			node.Attach = element
			if element and element.Type == "MovingPlatform" then
				node.AttachOffset = element.BaseCFrame:PointToObjectSpace(spec.Pos)
			end
		end
		route.Nodes[node.Id] = node
		table.insert(route.Order, node.Id)
		if node.Checkpoint ~= nil then
			route.ByCheckpoint[node.Checkpoint] = node.Id
		end
	end
	for index, id in route.Order do
		local node = route.Nodes[id]
		if node.Next == nil and not node.Finish and route.Order[index + 1] then
			node.Next = { route.Order[index + 1] }
		end
	end
	return route
end

---------------------------------------------------------------------------
-- Rival simulation
---------------------------------------------------------------------------
function Sim.RunRival(def, seed, maxSeconds)
	local Rival = H.Require("ServerScriptService.Server.Roles.Rival")
	local world = buildWorld(def, seed)
	local actor = newActor(world)
	local finished = false
	local inst = {
		Route = buildRoute(world, def),
		ById = world.ById,
		OriginPos = Vector3.zero,
		Checkpoints = { [0] = { DoppelCFrame = CFrame.new(0, 3, 0), SpawnCFrame = CFrame.new(0, 3, 0) } },
		Lasers = {},
		Beams = {},
	}
	local run = {
		Player = {},
		Instance = inst,
		Def = def,
		CheckpointIndex = def.RivalStartCheckpoint or 0,
		AIEnabled = true,
		RoleHistory = {},
	}
	local services = {
		ObstacleService = {
			VisibleRemaining = function(_, _inst, element)
				if element.Type ~= "Disappearing" then
					return math.huge
				end
				local cycle = element.Cycle
				local visible = cycle.Visible or 2
				local period = visible + (cycle.Hidden or 1.5)
				local p = (world.Clock + (cycle.Phase or 0)) % period
				return if p < visible then visible - p else 0
			end,
			IsElementSolid = function(_, element)
				if element.Type == "Fake" then
					return not (element.IsFake and element.Revealed)
				elseif element.Type == "Disappearing" then
					return element.Visible
				end
				return true
			end,
		},
		InteractionService = {
			IsSegmentDangerous = function()
				return false
			end,
		},
		CharacterService = {
			GetLiving = function()
				return nil, nil, 3
			end,
		},
		DoppelgangerService = {
			OnRivalFinished = function()
				finished = true
			end,
		},
	}
	H.SetClock(0)
	local role = Rival.new({
		Run = run,
		Actor = actor,
		Services = services,
		Rng = H.Random.new(seed * 7 + 3),
		Reveal = function() end,
		Status = function() end,
		Toast = function() end,
	})
	role:Start()

	-- os.clock is used by the role: drive a fake clock through the harness environment
	local dt = 1 / 30
	local visitedFinishAt = nil
	local steps = math.floor((maxSeconds or 240) / dt)
	for _ = 1, steps do
		stepWorld(world, dt)
		H.SetClock(world.Clock)
		if actor.State == "Dead" then
			if world.Clock - actor.DiedAt > 1.4 then
				actor:Respawn(role:GetRespawnCFrame())
				role:OnDoppelRespawned()
			end
		else
			role:Update(dt, world.Clock)
			-- pressing buttons: standing close to a button
			for _, button in world.Buttons do
				local p = button.Spec.Pos
				local feet = actor.Position - Vector3.new(0, ROOT, 0)
				if math.abs(feet.X - p.X) < 2.4 and math.abs(feet.Z - p.Z) < 2.4 and math.abs(feet.Y - p.Y) < 1.5 then
					button.ActiveUntil = world.Clock + button.Duration
				end
			end
			-- killed by the void
			if actor.Position.Y < -40 then
				actor:StartFall()
			end
		end
		if finished then
			visitedFinishAt = world.Clock
			break
		end
	end
	return {
		Finished = finished,
		Time = visitedFinishAt,
		Deaths = actor.Deaths,
		Revealed = (function()
			local n = 0
			for _, element in world.ById do
				if element.Revealed then
					n += 1
				end
			end
			return n
		end)(),
	}
end

---------------------------------------------------------------------------
-- Shadow simulation: a scripted player walks forward; the shadow must copy it with delay
---------------------------------------------------------------------------
function Sim.RunShadow(opts)
	local Shadow = H.Require("ServerScriptService.Server.Roles.Shadow")
	local TrailRecorder = H.Require("ServerScriptService.Server.Doppelganger.TrailRecorder")
	local def = {
		Id = 0,
		ShadowDelay = opts.Delay,
		ShadowPhase = opts.Phase,
		Elements = {
			{ Type = "Platform", Pos = Vector3.new(50, -0.5, 0), Size = Vector3.new(120, 1, 10) },
			opts.Door and { Type = "Door", Id = "D", Pos = Vector3.new(opts.Door, 5, 0), Size = Vector3.new(1, 10, 10) } or nil,
		},
	}
	local world = buildWorld(def, 1)
	local actor = newActor(world)
	actor.Position = Vector3.new(0, 3, 0)
	local recorder = TrailRecorder.new(30)
	local run = {
		Player = { Parent = nil },
		Instance = { Checkpoints = { [0] = { SpawnCFrame = CFrame.new(0, 3, 0), DoppelCFrame = CFrame.new(0, 3, 0) } } },
		Def = def,
		CheckpointIndex = 0,
		AIEnabled = true,
	}
	local role = Shadow.new({
		Run = run,
		Actor = actor,
		Recorder = recorder,
		Services = { DataService = { IncrementStat = function() end } },
		Rng = H.Random.new(1),
	})
	H.SetClock(0)
	role:Start()
	local dt = 1 / 60
	local nextSample = 0
	local samples = {}
	for step = 1, math.floor(opts.Seconds / dt) do
		local t = step * dt
		stepWorld(world, dt)
		H.SetClock(t)
		-- player walks at 16 studs/s along +X
		local playerPos = Vector3.new(math.min(t * 16, 95), 3, 0)
		if t >= nextSample then
			nextSample = t + 1 / 15
			recorder:Push(t, playerPos, 0, true, 0)
		end
		if opts.OpenDoorAt and t >= opts.OpenDoorAt and world.ById.D then
			world.ById.D.ForceOpen = true
		end
		role:Update(dt, t)
		table.insert(samples, { T = t, Player = playerPos, Shadow = actor.Position })
	end
	return samples, actor
end

return Sim
