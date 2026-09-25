--[[
	TrailRecorder
	Records the player's movement as snapshots (default 15 per second, Config.SHADOW_SAMPLE_RATE)
	and can sample the recording at any past time with interpolation.

	Snapshot = { T, Position, Yaw, Grounded, Jump, Teleport }
	  T         os.clock() timestamp
	  Position  HumanoidRootPart position
	  Yaw       facing (radians)
	  Grounded  server raycast found ground under the player
	  Jump      player left the ground upwards since the previous snapshot
	  Teleport  discontinuity (respawn / teleport pad) - never interpolate across it

	Pure data structure: no Roblox API calls except inside Record(), so it is unit-testable.
]]

local TrailRecorder = {}
TrailRecorder.__index = TrailRecorder

function TrailRecorder.new(maxAge: number)
	return setmetatable({
		Snapshots = {},
		First = 1, -- index of the oldest live snapshot (avoids table.remove(1) cost)
		Last = 0, -- index of the newest snapshot (never use # on a table with leading holes)
		MaxAge = maxAge or 30,
		PendingTeleport = false,
		LastGrounded = true,
		Cursor = 1,
	}, TrailRecorder)
end

function TrailRecorder:Clear()
	self.Snapshots = {}
	self.First = 1
	self.Last = 0
	self.Cursor = 1
	self.PendingTeleport = false
end

function TrailRecorder:MarkTeleport()
	self.PendingTeleport = true
end

function TrailRecorder:Count(): number
	return self.Last - self.First + 1
end

function TrailRecorder:Latest()
	if self.Last < self.First then
		return nil
	end
	return self.Snapshots[self.Last]
end

function TrailRecorder:Oldest()
	if self.Last < self.First then
		return nil
	end
	return self.Snapshots[self.First]
end

function TrailRecorder:Push(t: number, position: Vector3, yaw: number, grounded: boolean, velocityY: number?)
	local snapshot = {
		T = t,
		Position = position,
		Yaw = yaw,
		Grounded = grounded,
		Jump = (not grounded) and self.LastGrounded and (velocityY or 0) > 2,
		Teleport = self.PendingTeleport,
	}
	self.PendingTeleport = false
	self.LastGrounded = grounded
	self.Last += 1
	self.Snapshots[self.Last] = snapshot
	self:_trim(t)
	return snapshot
end

function TrailRecorder:_trim(now: number)
	local snapshots = self.Snapshots
	while self.First < self.Last and now - snapshots[self.First].T > self.MaxAge do
		snapshots[self.First] = nil :: any
		self.First += 1
	end
	-- compact occasionally so indices don't grow forever
	if self.First > 256 then
		local compact = table.move(snapshots, self.First, self.Last, 1, {})
		self.Snapshots = compact
		self.Cursor = math.max(1, self.Cursor - self.First + 1)
		self.Last = self.Last - self.First + 1
		self.First = 1
	end
end

local function lerpAngle(a: number, b: number, alpha: number): number
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * alpha
end

--[[
	Sample(t) -> sample table or nil when t is before the first snapshot.
	After the last snapshot the last snapshot is returned (the doppel waits there).
	Returned table is reused - copy values if you need to keep them.
]]
local sampleResult = { Position = Vector3.zero, Yaw = 0, Grounded = true, Jump = false, Teleport = false, T = 0, AtEnd = false }

function TrailRecorder:Sample(t: number)
	local snapshots = self.Snapshots
	local first, last = self.First, self.Last
	if last < first then
		return nil
	end
	if t < snapshots[first].T then
		return nil
	end
	local lastSnapshot = snapshots[last]
	if t >= lastSnapshot.T then
		sampleResult.Position = lastSnapshot.Position
		sampleResult.Yaw = lastSnapshot.Yaw
		sampleResult.Grounded = lastSnapshot.Grounded
		sampleResult.Jump = false
		sampleResult.Teleport = false
		sampleResult.T = lastSnapshot.T
		sampleResult.AtEnd = true
		return sampleResult
	end
	-- cursor walk (samples are requested in increasing time order almost always)
	local i = math.clamp(self.Cursor, first, last - 1)
	while i > first and snapshots[i].T > t do
		i -= 1
	end
	while i < last - 1 and snapshots[i + 1].T <= t do
		i += 1
	end
	self.Cursor = i
	local a, b = snapshots[i], snapshots[i + 1]
	local alpha = 0
	local span = b.T - a.T
	if span > 0 then
		alpha = math.clamp((t - a.T) / span, 0, 1)
	end
	if b.Teleport then
		-- never slide across a teleport; jump once we reach it
		sampleResult.Position = a.Position
		sampleResult.Yaw = a.Yaw
		sampleResult.Grounded = a.Grounded
		sampleResult.Teleport = false
	else
		sampleResult.Position = a.Position:Lerp(b.Position, alpha)
		sampleResult.Yaw = lerpAngle(a.Yaw, b.Yaw, alpha)
		-- only "grounded" when both ends are grounded (jump arcs are never ground-checked)
		sampleResult.Grounded = a.Grounded and b.Grounded
		sampleResult.Teleport = a.Teleport and alpha < 0.01
	end
	sampleResult.Jump = b.Jump
	sampleResult.T = t
	sampleResult.AtEnd = false
	return sampleResult
end

-- Newest snapshot at or before time t that satisfies predicate(snapshot) (checks at most `limit`).
function TrailRecorder:FindBefore(t: number, predicate: (any) -> boolean, limit: number?)
	local snapshots = self.Snapshots
	local checked = 0
	for i = self.Last, self.First, -1 do
		local snapshot = snapshots[i]
		if snapshot.T <= t then
			checked += 1
			if predicate(snapshot) then
				return snapshot
			end
			if checked >= (limit or 40) then
				return nil
			end
		end
	end
	return nil
end

-- Walk back from the newest snapshot and return the time where the trail is `distance` studs
-- (path length) behind the newest point. Used by the Follower.
function TrailRecorder:TimeAtDistanceBehind(distance: number): number?
	local snapshots = self.Snapshots
	local first, last = self.First, self.Last
	if last < first then
		return nil
	end
	local travelled = 0
	for i = last, first + 1, -1 do
		local b, a = snapshots[i], snapshots[i - 1]
		if b.Teleport then
			return b.T
		end
		local segment = (b.Position - a.Position).Magnitude
		if travelled + segment >= distance then
			local alpha = if segment > 0 then (distance - travelled) / segment else 0
			return b.T + (a.T - b.T) * alpha
		end
		travelled += segment
	end
	return snapshots[first].T
end

return TrailRecorder
