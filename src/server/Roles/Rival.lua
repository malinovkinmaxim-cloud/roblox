--[[
	Rival - Level 2 / 4 / 9 / 10
	Races the player to the finish along the level's Route (a small graph of nodes).
	Deliberately NOT a perfect bot:
	  - picks branches randomly (so it tries the "wrong" button / platform sometimes)
	  - hesitates at nodes (RIVAL_PAUSE_CHANCE)
	  - misjumps and falls (RIVAL_MISJUMP_CHANCE)
	  - sometimes runs into active hazards (RIVAL_HAZARD_IGNORE_CHANCE)
	  - rubber-bands: slows down when far ahead, speeds up when far behind
	It never gets stuck: blocked paths time out into fallback branches, deaths respawn it
	at its last safe node.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RoleBase = require(script.Parent.RoleBase)
local DoppelActor = require(script.Parent.Parent.Doppelganger.DoppelActor)

local Rival = RoleBase.Extend("Rival")

function Rival.new(ctx)
	local self = setmetatable(RoleBase.new(ctx), Rival)
	self.Route = self.Instance.Route
	self.BaseSpeed = Config.DOPPELGANGER_SPEED * Config.RIVAL_SPEED_MULTIPLIER
	self.Mode = "Starting"
	self.NodeId = nil
	self.Segment = nil
	self.Visited = {}
	self.LastSafeNode = nil
	self.WaitUntil = 0
	self.Planned = nil
	self.PauseRolled = false
	self.HazardGamble = nil
	self.GateSince = nil
	self.WaitSince = nil
	self.Status = nil
	self.Diff = 0
	self.LastStatusCheck = 0
	self.StartedRacing = false
	return self
end

---------------------------------------------------------------------------
-- Route helpers
---------------------------------------------------------------------------

function Rival:NodeForCheckpoint(index: number): string?
	local best, bestIndex = nil, -1
	for checkpoint, nodeId in self.Route.ByCheckpoint do
		if checkpoint <= index and checkpoint > bestIndex then
			best, bestIndex = nodeId, checkpoint
		end
	end
	return best or self.Route.Order[1]
end

function Rival:NodeRootPos(node): Vector3
	local base = node.WorldPos
	if node.Attach and node.AttachOffset and node.Attach.Part and node.Attach.Part.Parent then
		base = node.Attach.Part.CFrame:PointToWorldSpace(node.AttachOffset)
	end
	return base + Vector3.new(0, self.Actor.RootOffset, 0)
end

function Rival:_isUsable(node): boolean
	local element = node.Attach
	if not element then
		return true
	end
	if element.Type == "Fake" and element.Revealed then
		return false -- it saw that one break
	end
	return true
end

function Rival:_choose(list: { string }?, avoidVisited: boolean): string?
	if not list or #list == 0 then
		return nil
	end
	local nodes = self.Route.Nodes
	local candidates, weights = {}, {}
	local fromNode = nodes[self.NodeId]
	for index, id in list do
		local node = nodes[id]
		if node and self:_isUsable(node) then
			table.insert(candidates, id)
			local weight = 1
			if fromNode and fromNode.Weights and fromNode.Next == list then
				weight = fromNode.Weights[index] or 1
			end
			if avoidVisited and self.Visited[id] then
				weight *= 0.05
			end
			table.insert(weights, weight)
		end
	end
	if #candidates == 0 then
		-- everything looks broken: take anything that exists (it may fall - that's fine)
		return list[self.Rng:NextInteger(1, #list)]
	end
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = self.Rng:NextNumber() * total
	for index, weight in weights do
		roll -= weight
		if roll <= 0 then
			return candidates[index]
		end
	end
	return candidates[#candidates]
end

local function yawTowards(from: Vector3, to: Vector3): number?
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flat.Magnitude < 0.05 then
		return nil
	end
	return DoppelActor.YawFromLook(flat.Unit)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Rival:Start()
	local nodeId = self:NodeForCheckpoint(self.Run.CheckpointIndex)
	self:_placeAt(nodeId)
	self.Mode = "Starting"
	self.WaitUntil = os.clock() + Config.RIVAL_START_DELAY
	self:SetStatus(nil, nil)
end

function Rival:Stop()
	RoleBase.Stop(self)
	self:SetStatus(nil, nil)
end

function Rival:_placeAt(nodeId: string?)
	if not nodeId then
		return
	end
	local node = self.Route.Nodes[nodeId]
	if not node then
		return
	end
	self.NodeId = nodeId
	self.Visited = { [nodeId] = true }
	self.Segment = nil
	self.Planned = nil
	self.PauseRolled = false
	self.HazardGamble = nil
	self.GateSince = nil
	self.WaitSince = nil
	self.LastSafeNode = nodeId
	local position = self:NodeRootPos(node)
	local yaw = 0
	local nextId = node.Next and node.Next[1]
	if nextId and self.Route.Nodes[nextId] then
		yaw = yawTowards(position, self.Route.Nodes[nextId].WorldPos) or 0
	end
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	if self.Actor:IsAlive() then
		self.Actor:Teleport(cf)
	else
		self.Actor:Respawn(cf)
	end
end

function Rival:OnPlayerRespawn(_checkpoint)
	-- fair restart: the rival goes back to the same checkpoint and gives you a small head start
	self.Actor:SetEmote(nil)
	if self.Mode == "Finished" then
		return -- it already won; it waits at the finish
	end
	self:_placeAt(self:NodeForCheckpoint(self.Run.CheckpointIndex))
	self.Mode = "Starting"
	self.WaitUntil = os.clock() + Config.RIVAL_RESTART_DELAY
end

function Rival:GetRespawnCFrame(): CFrame
	local nodeId = self.LastSafeNode or self:NodeForCheckpoint(self.Run.CheckpointIndex)
	local node = nodeId and self.Route.Nodes[nodeId]
	if node then
		return CFrame.new(self:NodeRootPos(node))
	end
	return self:GetCheckpoint().DoppelCFrame
end

function Rival:OnDoppelRespawned()
	local nodeId = self.LastSafeNode or self:NodeForCheckpoint(self.Run.CheckpointIndex)
	self:_placeAt(nodeId)
	self.Mode = "Starting"
	self.WaitUntil = os.clock() + 0.6
end

function Rival:OnReachFinish()
	if self.Mode ~= "Finished" then
		self:_finish()
	end
end

function Rival:_finish()
	self.Mode = "Finished"
	self.Segment = nil
	self.Actor:SetEmote("Cheer")
	self.Services.DoppelgangerService:OnRivalFinished(self.Run)
end

---------------------------------------------------------------------------
-- Race status (DOPPELGÄNGER IS AHEAD!)
---------------------------------------------------------------------------

function Rival:_updateStatus(now: number)
	if now - self.LastStatusCheck < 0.25 then
		return
	end
	self.LastStatusCheck = now
	local root = self:GetPlayerRoot()
	if not root or not self.StartedRacing then
		return
	end
	local origin = self.Instance.OriginPos
	local diff = (self.Actor.Position.X - origin.X) - (root.Position.X - origin.X)
	self.Diff = diff
	local status = self.Status
	local margin = Config.RIVAL_STATUS_MARGIN
	if diff > margin then
		status = "Ahead"
	elseif diff < -margin then
		status = "Behind"
	end
	if status ~= self.Status then
		self.Status = status
		if status == "Ahead" then
			self:SetStatus("Ahead", "DOPPELGÄNGER IS AHEAD!")
		else
			self:SetStatus("Behind", "YOU ARE AHEAD!")
		end
	end
end

function Rival:_speed(): number
	local speed = self.BaseSpeed
	if self.Diff > Config.RIVAL_RUBBERBAND_AHEAD then
		speed *= 0.78
	elseif self.Diff < -Config.RIVAL_RUBBERBAND_BEHIND then
		speed *= 1.15
	end
	return speed
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

function Rival:Update(dt: number, now: number)
	local actor = self.Actor
	if not actor:IsControllable() then
		return
	end
	if not self.Run.AIEnabled then
		actor:Hold()
		return
	end
	self:_updateStatus(now)

	local mode = self.Mode
	if mode == "Finished" then
		actor:Hold()
		return
	end
	if mode == "Starting" or mode == "Paused" then
		self:_stickToNode()
		if now >= self.WaitUntil then
			self.Mode = "Idle"
			actor:SetEmote(nil)
		end
		return
	end
	if mode == "Idle" then
		self:_decide(now)
		if self.Mode == "Idle" then
			self:_stickToNode()
		end
		return
	end
	if mode == "Moving" then
		self:_move(dt, now)
	end
end

-- Stay on the current node (rides moving platforms, falls if the ground disappears).
function Rival:_stickToNode()
	local node = self.NodeId and self.Route.Nodes[self.NodeId]
	if not node then
		self.Actor:Hold()
		return
	end
	if node.Attach and node.AttachOffset then
		self.Actor:DriveTo(self:NodeRootPos(node), nil, true, { IgnoreBlockers = true })
	else
		self.Actor:DriveTo(self.Actor.Position, nil, true, { IgnoreBlockers = true })
	end
end

function Rival:_decide(now: number)
	local nodes = self.Route.Nodes
	local node = nodes[self.NodeId]
	if not node then
		return
	end
	if node.Finish then
		self:_finish()
		return
	end

	-- gate: wait until a door / bridge is powered (or give up after Timeout)
	if node.Gate then
		local gate = self.Instance.ById[node.Gate]
		local open = gate == nil or gate.Powered == true or gate.Open == true
		if not open then
			self.GateSince = self.GateSince or now
			if node.Fallback and now - self.GateSince > node.Timeout then
				self.GateSince = nil
				local fallback = self:_choose(node.Fallback, true)
				if fallback then
					self:_beginSegment(fallback, now)
				end
			end
			return
		end
		self.GateSince = nil
	end

	if not self.Planned then
		self.Planned = self:_choose(node.Next, node.AvoidVisited)
		self.WaitSince = now
	end
	local nextId = self.Planned
	if not nextId then
		return
	end
	local nextNode = nodes[nextId]
	local here = self.Actor.Position
	local there = self:NodeRootPos(nextNode)

	-- moving platform target: wait until it comes into jumping range
	if nextNode.Attach and nextNode.AttachOffset then
		if (there - here).Magnitude > Config.JUMP_RANGE and now - (self.WaitSince or now) < 12 then
			return
		end
	end
	-- vanishing / falling platform currently gone (or about to go): wait for it
	local attach = nextNode.Attach
	if attach and now - (self.WaitSince or now) < 8 then
		local obstacles = self.Services.ObstacleService
		if attach.Type ~= "Fake" and not obstacles:IsElementSolid(attach) then
			return
		end
		if obstacles:VisibleRemaining(self.Instance, attach) < 1.0 then
			return
		end
	end
	-- hazards: usually waits for a safe moment, sometimes gambles
	if node.Hazard then
		if self.HazardGamble == nil then
			self.HazardGamble = self.Rng:NextNumber() < Config.RIVAL_HAZARD_IGNORE_CHANCE
		end
		if not self.HazardGamble and now - (self.WaitSince or now) < 10 then
			if self.Services.InteractionService:IsSegmentDangerous(self.Instance, here, there, self.Actor.RootOffset) then
				return
			end
		end
	end
	-- occasional hesitation (never while standing on something that vanishes or falls)
	if not self.PauseRolled then
		self.PauseRolled = true
		local unstable = node.Attach ~= nil and (node.Attach.Type == "Disappearing" or node.Attach.Type == "Falling")
		local chance = if node.Pause or unstable then 0 else Config.RIVAL_PAUSE_CHANCE
		if self.Rng:NextNumber() < chance then
			local range = Config.RIVAL_PAUSE_TIME
			self.Mode = "Paused"
			self.WaitUntil = now + self.Rng:NextNumber(range[1], range[2])
			return
		end
	end
	self:_beginSegment(nextId, now)
end

function Rival:_needsJump(from: Vector3, to: Vector3, node): boolean
	if node.Jump ~= nil then
		return node.Jump
	end
	if math.abs(to.Y - from.Y) > 0.6 then
		return true
	end
	if node.Attach and node.Attach.Type == "MovingPlatform" then
		return true
	end
	-- any gap along the way (thin probes every half stud) means we have to jump
	local steps = math.max(2, math.ceil((to - from).Magnitude * 2))
	for i = 1, steps - 1 do
		if not self.Actor:HasGroundAt(from:Lerp(to, i / steps), 1.5, true) then
			return true
		end
	end
	return false
end

function Rival:_beginSegment(toId: string, _now: number)
	local toNode = self.Route.Nodes[toId]
	if not toNode then
		return
	end
	if not self.StartedRacing then
		self.StartedRacing = true
		self:Reveal() -- hidden rivals reveal themselves the moment they start racing
	end
	local from = self.Actor.Position
	local to = self:NodeRootPos(toNode)
	local jump = self:_needsJump(from, to, toNode)
	local segment = {
		FromId = self.NodeId,
		ToId = toId,
		From = from,
		Jump = jump,
		T = 0,
		Blocked = 0,
		Yaw = yawTowards(from, to),
		Misjump = false,
		Duration = 0,
		Height = 0,
	}
	if jump then
		local horizontal = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
		local dy = to.Y - from.Y
		segment.Height = 3.2 + math.max(0, dy) * 0.6
		segment.Duration = math.max(0.42, horizontal / (self:_speed() * 1.2))
		-- the "not perfect" part: sometimes the jump is short
		if horizontal > 5 and self.Rng:NextNumber() < Config.RIVAL_MISJUMP_CHANCE then
			segment.Misjump = true
		end
	end
	self.Segment = segment
	self.Planned = nil
	self.PauseRolled = false
	self.HazardGamble = nil
	self.WaitSince = nil
	self.Mode = "Moving"
end

function Rival:_move(dt: number, now: number)
	local segment = self.Segment
	if not segment then
		self.Mode = "Idle"
		return
	end
	local actor = self.Actor
	local toNode = self.Route.Nodes[segment.ToId]
	local to = self:NodeRootPos(toNode)

	if segment.Jump then
		segment.T += dt
		local alpha = math.clamp(segment.T / segment.Duration, 0, 1)
		local target = to
		if segment.Misjump then
			target = segment.From:Lerp(to, 0.55)
		end
		local flat = segment.From:Lerp(target, alpha)
		local y = segment.From.Y + (target.Y - segment.From.Y) * alpha + 4 * segment.Height * alpha * (1 - alpha)
		local position = Vector3.new(flat.X, y, flat.Z)
		local landed = alpha >= 1
		local result = actor:DriveTo(position, segment.Yaw, landed)
		if result == "blocked" then
			-- bonked into a closed door mid-air
			actor:StartFall(Vector3.new(0, -4, 0))
			return
		end
		if result == "fell" then
			return
		end
		if landed then
			if segment.Misjump then
				actor:StartFall(Vector3.new(0, -2, 0))
				return
			end
			self:_arrive(segment.ToId, now)
		end
		return
	end

	-- walking
	local here = actor.Position
	local delta = to - here
	local distance = delta.Magnitude
	local step = self:_speed() * dt
	local position, arrived
	if distance <= step then
		position, arrived = to, true
	else
		position, arrived = here + delta.Unit * step, false
	end
	local result = actor:DriveTo(position, yawTowards(here, to), true)
	if result == "blocked" then
		segment.Blocked += dt
		if segment.Blocked > Config.RIVAL_BLOCKED_TIMEOUT then
			self:_onBlocked(segment, now)
		end
		return
	end
	if result == "fell" then
		return
	end
	segment.Blocked = 0
	if arrived then
		self:_arrive(segment.ToId, now)
	end
end

-- A closed door is in the way for too long: try a fallback branch of the node we came from.
function Rival:_onBlocked(segment, now: number)
	local fromNode = segment.FromId and self.Route.Nodes[segment.FromId]
	local options = {}
	if fromNode then
		for _, list in { fromNode.Fallback, fromNode.Next } do
			if list then
				for _, id in list do
					if id ~= segment.ToId and not table.find(options, id) then
						table.insert(options, id)
					end
				end
			end
		end
	end
	local choice = self:_choose(options, true)
	if choice then
		self:_beginSegment(choice, now)
	else
		-- nothing else to try: wait a bit and retry the same way
		segment.Blocked = 0
		self.Mode = "Paused"
		self.WaitUntil = now + 1
		self.Segment = nil
	end
end

function Rival:_arrive(nodeId: string, now: number)
	self.NodeId = nodeId
	self.Visited[nodeId] = true
	self.Segment = nil
	self.Mode = "Idle"
	local node = self.Route.Nodes[nodeId]
	if not node then
		return
	end
	if node.Safe then
		self.LastSafeNode = nodeId
	end
	if node.Finish then
		self:_finish()
		return
	end
	if node.Pause then
		self.Mode = "Paused"
		self.WaitUntil = now + node.Pause
	end
end

return Rival
