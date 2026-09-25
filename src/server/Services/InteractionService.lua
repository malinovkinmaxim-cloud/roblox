--[[
	InteractionService
	Universal interaction system. ONE loop (30 Hz) for every run on the server:
	  for every actor (player, doppelgänger, duo partner):
	    one spatial query against the level's "Interactive" folder
	    -> hazards, checkpoints, finish, buttons / pressure plates, fake & falling platforms,
	       launch pads, teleport pads
	  then every button / plate updates its state and powers its targets (doors, bridges,
	  lasers, moving platforms) through the link table built by LevelBuilder.

	Nothing here is level specific: levels only declare elements and links as data.
	The doppelgänger interacts through exactly the same code path as the player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local InteractionService = {}

local TICK = 1 / Config.INTERACTION_RATE
local BODY_WIDTH = 1.7

function InteractionService:Init(services)
	self.Services = services
end

function InteractionService:Start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK then
			return
		end
		accumulator = 0
		local now = os.clock()
		local serverNow = Workspace:GetServerTimeNow()
		for _, run in table.clone(self.Services.RoundService.ActiveRuns) do
			if not run.Ended then
				local ok, err = pcall(self._tickRun, self, run, now, serverNow)
				if not ok then
					warn("[InteractionService] tick error: " .. tostring(err))
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function activatorMatches(activator: string, actor): boolean
	if activator == "Any" then
		return true
	end
	return activator == actor.Kind
end

-- Rotating beam hit test (the beam only rotates on clients; the server uses math).
function InteractionService.BeamHits(beam, pos: Vector3, bottomY: number, topY: number, serverNow: number, margin: number?): boolean
	local pivot = beam.PivotCFrame.Position
	local half = beam.Thickness / 2
	if pivot.Y + half < bottomY or pivot.Y - half > topY then
		return false
	end
	local angle = beam.StartAngle + beam.Speed * (serverNow - beam.Instance.StartServerTime)
	local dir = Vector3.new(math.cos(angle), 0, -math.sin(angle))
	local rel = Vector3.new(pos.X - pivot.X, 0, pos.Z - pivot.Z)
	local along = math.clamp(rel:Dot(dir), -beam.Length / 2, beam.Length / 2)
	local distance = (rel - dir * along).Magnitude
	return distance < half + 0.7 + (margin or 0)
end

---------------------------------------------------------------------------
-- Per-run tick
---------------------------------------------------------------------------

function InteractionService:_tickRun(run, now: number, serverNow: number)
	if run.State ~= "Playing" and run.State ~= "Dead" and run.State ~= "Finished" then
		return
	end
	local inst = run.Instance
	local actors = self.Services.RoundService:GetActors(run)
	local pressed = {} -- [source] = actor

	for _, actor in actors do
		local pos: Vector3 = actor.Position
		if pos.Y < inst.KillY then
			self:KillActor(run, actor, "Fell")
			continue
		end
		local feetY = pos.Y - actor.RootOffset
		local bottom = feetY - 0.6
		local top = pos.Y + 2.4
		local boxCFrame = CFrame.new(pos.X, (bottom + top) / 2, pos.Z)
		local boxSize = Vector3.new(BODY_WIDTH, top - bottom, BODY_WIDTH)
		local parts = Workspace:GetPartBoundsInBox(boxCFrame, boxSize, inst.OverlapParams)
		local dead = false
		for _, part in parts do
			local element = inst.PartToElement[part]
			if element and self:_handle(run, actor, element, now, pressed) then
				dead = true
				break
			end
		end
		if not dead and run.State ~= "Finished" then
			for _, beam in inst.Beams do
				if InteractionService.BeamHits(beam, pos, bottom + 0.4, top, serverNow) then
					self:KillActor(run, actor, "Beam")
					break
				end
			end
		end
	end

	for _, source in inst.Sources do
		self:_updateSource(run, source, pressed[source], now)
	end
end

-- returns true when the actor died
function InteractionService:_handle(run, actor, element, now: number, pressed): boolean
	local kind = element.Kind
	local finished = run.State == "Finished"
	if kind == "Kill" then
		if finished then
			return false
		end
		return self:KillActor(run, actor, "Hazard")
	elseif kind == "Laser" then
		if not finished and element.On and now >= element.LethalAt then
			return self:KillActor(run, actor, "Laser")
		end
	elseif kind == "Checkpoint" then
		if actor.Kind == "Player" or actor.IsPartner then
			self.Services.CheckpointService:Reach(run, element.Index, actor.Player)
		end
	elseif kind == "Finish" then
		if actor.Kind == "Player" then
			self.Services.RoundService:Finish(run)
		elseif actor.Actor then
			self.Services.DoppelgangerService:OnDoppelReachedFinish(run)
		end
	elseif kind == "Source" then
		if activatorMatches(element.Activator, actor) then
			if pressed[element] == nil then
				pressed[element] = actor
			end
		elseif actor.Kind == "Player" and element.Activator == "Doppel" then
			self:_doppelOnlyHint(run)
		end
	elseif kind == "Fake" then
		if actor.Ghost then
			self.Services.ObstacleService:GhostShimmer(element, now)
		else
			self.Services.ObstacleService:CollapseFake(run.Instance, element)
		end
	elseif kind == "Falling" then
		if not actor.Ghost then
			self.Services.ObstacleService:TriggerFalling(run.Instance, element)
		end
	elseif kind == "Launch" then
		self:_launch(run, actor, element, now)
	elseif kind == "Teleport" then
		self:_teleport(run, actor, element, now)
	end
	return false
end

function InteractionService:_doppelOnlyHint(run)
	local now = os.clock()
	if run.LastDoppelHint and now - run.LastDoppelHint < Config.DOPPEL_ONLY_HINT_COOLDOWN then
		return
	end
	run.LastDoppelHint = now
	Net.Event("Toast"):FireClient(run.Player, "Only your DOPPELGÄNGER can press CYAN buttons!", "Hint")
end

local function actorKey(actor): any
	return actor.Player or actor.Actor
end

function InteractionService:_launch(run, actor, element, now: number)
	element.LastUse = element.LastUse or {}
	local key = actorKey(actor)
	if element.LastUse[key] and now - element.LastUse[key] < 0.6 then
		return
	end
	element.LastUse[key] = now
	local velocity: Vector3 = element.Velocity
	if actor.Player then
		Net.Event("Launch"):FireClient(actor.Player, velocity)
	elseif actor.Actor and not (run.Role and run.Role.ReplaysPlayer) then
		actor.Actor:Launch(velocity)
	end
end

function InteractionService:_teleport(run, actor, element, now: number)
	element.LastUse = element.LastUse or {}
	local key = actorKey(actor)
	if element.LastUse[key] and now - element.LastUse[key] < 1 then
		return
	end
	element.LastUse[key] = now
	local target = CFrame.new(element.TargetPos + Vector3.new(0, actor.RootOffset + 0.2, 0))
	if actor.Player then
		if run.Recorder and actor.Kind == "Player" then
			run.Recorder:MarkTeleport()
		end
		-- keep facing direction
		local look = actor.Root.CFrame.LookVector
		self.Services.CharacterService:Teleport(actor.Player, CFrame.lookAt(target.Position, target.Position + Vector3.new(look.X, 0, look.Z)))
		-- prevent bouncing back immediately from the destination pad
		element.LastUse[key] = now + 1
	elseif actor.Actor and not (run.Role and run.Role.ReplaysPlayer) then
		actor.Actor:Teleport(target)
	end
end

---------------------------------------------------------------------------
-- Death
---------------------------------------------------------------------------

function InteractionService:KillActor(run, actor, cause: string): boolean
	if actor.Actor then
		self.Services.DoppelgangerService:KillDoppel(run, cause)
		return true
	end
	if actor.Player then
		if run.State == "Finished" and cause ~= "Fell" then
			return false
		end
		self.Services.RoundService:KillPlayer(run, actor.Player, cause)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Buttons / plates
---------------------------------------------------------------------------

function InteractionService:_updateSource(run, source, presser, now: number)
	local occupied = presser ~= nil
	local mode = source.Mode
	local active = source.Active
	local newlyPressed = occupied and not source.WasOccupied

	if mode == "Hold" then
		if occupied then
			source.LastOccupied = now
		end
		active = occupied or (now - source.LastOccupied) < source.ReleaseDelay
	elseif mode == "Toggle" then
		if newlyPressed then
			active = not active
		end
	elseif mode == "Timed" then
		if newlyPressed then
			source.ActiveUntil = now + source.Duration
		end
		active = now < source.ActiveUntil
	elseif mode == "Once" then
		if occupied then
			active = true
		end
	end

	if newlyPressed then
		self:_pressedVisual(source, true)
		if source.Sound then
			source.Sound:Play()
		end
		if presser.Kind == "Doppel" then
			self.Services.DataService:IncrementStat(run.Player, "DoppelPresses", 1)
		end
		self.Services.DoppelgangerService:OnSourcePressed(run, source, presser)
	elseif not occupied and source.WasOccupied then
		self:_pressedVisual(source, false)
	end
	source.WasOccupied = occupied

	-- timed buttons blink during their last second
	if mode == "Timed" and active then
		local remaining = source.ActiveUntil - now
		local blink = remaining < 1.2 and math.floor(remaining * 8) % 2 == 0
		if blink ~= source.Blink then
			source.Blink = blink
			source.Part.Material = if blink then Enum.Material.SmoothPlastic else Enum.Material.Neon
		end
	end

	if active ~= source.Active then
		self:SetSourceActive(run.Instance, source, active)
	end
end

function InteractionService:_pressedVisual(source, down: boolean)
	local part = source.Part :: BasePart
	if source.Mode == "Hold" then
		return
	end
	part.CFrame = source.PartCFrame - Vector3.new(0, if down then 0.25 else 0, 0)
end

function InteractionService:SetSourceActive(inst, source, active: boolean)
	source.Active = active
	source.Blink = nil
	local part = source.Part :: BasePart
	part.Material = if active then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, targetId in source.Targets do
		self:RecomputeTarget(inst, targetId)
	end
end

function InteractionService:RecomputeTarget(inst, targetId: string)
	local target = inst.ById[targetId]
	local sources = inst.Links[targetId]
	if not target or not sources then
		return
	end
	local powered
	if target.Logic == "All" or (target.Spec and target.Spec.Logic == "All") then
		powered = true
		for _, source in sources do
			if not source.Active then
				powered = false
				break
			end
		end
	else
		powered = false
		for _, source in sources do
			if source.Active then
				powered = true
				break
			end
		end
	end
	self.Services.ObstacleService:SetPowered(inst, target, powered)
end

---------------------------------------------------------------------------
-- Queries used by AI roles
---------------------------------------------------------------------------

local function pointInPart(part: BasePart, point: Vector3, margin: number): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2 + Vector3.new(margin, margin, margin)
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- Is walking/jumping from a to b (root positions) dangerous right now or very soon?
function InteractionService:IsSegmentDangerous(inst, a: Vector3, b: Vector3, rootOffset: number): boolean
	local serverNow = Workspace:GetServerTimeNow()
	local distance = (b - a).Magnitude
	local steps = math.max(1, math.ceil(distance / 2))
	for i = 0, steps do
		local p = a:Lerp(b, i / steps)
		local feet = p - Vector3.new(0, rootOffset - 0.5, 0)
		local head = p + Vector3.new(0, 2, 0)
		for _, laser in inst.Lasers do
			local soon = laser.On or laser.Warning or laser.PendingOn
			if soon and (pointInPart(laser.Part, p, 1) or pointInPart(laser.Part, feet, 1) or pointInPart(laser.Part, head, 1)) then
				return true
			end
		end
		-- a beam that is here now or will be here while we cross
		local eta = (i / steps) * distance / Config.DOPPELGANGER_SPEED
		for _, beam in inst.Beams do
			if InteractionService.BeamHits(beam, p, feet.Y, head.Y, serverNow + eta, 1.2) then
				return true
			end
		end
	end
	return false
end

-- Nearest ally-usable target in front of a player (for Ally / Troll "SEND").
function InteractionService:FindTargetInFront(inst, root: BasePart, maxDistance: number, cone: number, filter: ((any) -> boolean)?)
	local origin = root.Position
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		return nil
	end
	look = look.Unit
	local best, bestScore = nil, math.huge
	local function consider(element, position: Vector3)
		if filter and not filter(element) then
			return
		end
		local offset = position - origin
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = flat.Magnitude
		if distance > maxDistance or distance < 1 then
			return
		end
		local dot = flat.Unit:Dot(look)
		if dot < cone then
			return
		end
		local score = distance * (1.6 - dot)
		if score < bestScore then
			best, bestScore = element, score
		end
	end
	for _, element in inst.AllyTargets do
		consider(element, element.Part.Position)
	end
	for _, element in inst.Elements do
		if element.Type == "Fake" and not element.Revealed then
			consider(element, element.Part.Position)
		end
	end
	return best
end

return InteractionService
