--[[
	LevelKit
	Helpers for authoring levels as pure data (ServerStorage.Levels.LevelXX).

	Coordinate system (level-local, studs):
	  +X = forward (the direction the player progresses)
	  +Y = up
	  +Z = right-hand side when looking forward is -Z... just think "sideways"
	  y = 0 is the top surface of the start platform.

	All helpers take the TOP SURFACE height `y` for floors/pads so jumps are easy to reason about.
	Player numbers: walk 16 studs/s, jump height 7.2 -> comfortable gaps <= 7 studs, steps up <= 5.

	Activators (who can press a button / plate):
	  "Any"    - yellow   - player or doppelgänger
	  "Player" - orange   - player only
	  "Doppel" - cyan     - doppelgänger only (the core of the game)
]]

local K = {}

local V = Vector3.new

K.Colors = {
	Floor = Color3.fromRGB(236, 239, 245),
	FloorAlt = Color3.fromRGB(214, 220, 232),
	Wall = Color3.fromRGB(70, 78, 98),
	Start = Color3.fromRGB(120, 200, 255),
	Checkpoint = Color3.fromRGB(95, 110, 130),
	CheckpointActive = Color3.fromRGB(70, 225, 140),
	Finish = Color3.fromRGB(255, 205, 70),
	Kill = Color3.fromRGB(255, 60, 70),
	Laser = Color3.fromRGB(255, 40, 60),
	Door = Color3.fromRGB(60, 66, 90),
	Any = Color3.fromRGB(255, 215, 60),
	Player = Color3.fromRGB(255, 150, 50),
	Doppel = Color3.fromRGB(60, 225, 255),
	Mover = Color3.fromRGB(130, 170, 255),
	Vanish = Color3.fromRGB(190, 150, 255),
	Falling = Color3.fromRGB(255, 185, 120),
	Launch = Color3.fromRGB(120, 255, 170),
	Teleport = Color3.fromRGB(200, 120, 255),
}

local function merge(base: { [string]: any }, extra: { [string]: any }?)
	if extra then
		for key, value in extra do
			base[key] = value
		end
	end
	return base
end

---------------------------------------------------------------------------
-- Static geometry
---------------------------------------------------------------------------

-- Floor with its top surface at y. Thickness 1 (or opts.Thickness).
function K.Floor(x: number, y: number, z: number, sx: number, sz: number, opts: { [string]: any }?)
	local thickness = (opts and opts.Thickness) or 1
	return merge({
		Type = "Platform",
		Pos = V(x, y - thickness / 2, z),
		Size = V(sx, thickness, sz),
	}, opts)
end

-- Box given by its center.
function K.Block(x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Platform",
		Pos = V(x, y, z),
		Size = V(sx, sy, sz),
	}, opts)
end

-- Wall standing on floor height y.
function K.Wall(x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Platform",
		Pos = V(x, y + sy / 2, z),
		Size = V(sx, sy, sz),
		Color = K.Colors.Wall,
	}, opts)
end

-- Non-colliding decoration
function K.Decor(x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Decor",
		Pos = V(x, y, z),
		Size = V(sx, sy, sz),
	}, opts)
end

---------------------------------------------------------------------------
-- Flow: start, checkpoints, finish
---------------------------------------------------------------------------

function K.Start(x: number, y: number, z: number, opts: { [string]: any }?)
	return merge({
		Type = "Start",
		Pos = V(x, y, z),
		Size = V(14, 1, 14),
	}, opts)
end

-- opts.SetRole = "Rival" switches the doppelgänger role when this checkpoint is reached.
function K.Checkpoint(index: number, x: number, y: number, z: number, opts: { [string]: any }?)
	return merge({
		Type = "Checkpoint",
		Index = index,
		Pos = V(x, y, z),
		Size = V(10, 1, 10),
	}, opts)
end

function K.Finish(x: number, y: number, z: number, opts: { [string]: any }?)
	return merge({
		Type = "Finish",
		Pos = V(x, y, z),
		Size = V(12, 1, 12),
	}, opts)
end

---------------------------------------------------------------------------
-- Hazards
---------------------------------------------------------------------------

-- Kill block given by its center.
function K.Kill(x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Kill",
		Pos = V(x, y, z),
		Size = V(sx, sy, sz),
	}, opts)
end

-- Kill strip lying on a floor whose top is y (slightly raised so it is visible).
function K.KillStrip(x: number, y: number, z: number, sx: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Kill",
		Pos = V(x, y + 0.25, z),
		Size = V(sx, 0.5, sz),
	}, opts)
end

--[[
	Laser beam (center + size). Options:
	  Cycle = { On = 1.2, Off = 1.2, Phase = 0 }  -- blinking laser
	  Trap = true                                 -- off until a linked button powers it
	  (default)                                   -- on; a linked button turns it OFF
]]
function K.Laser(id: string?, x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Laser",
		Id = id,
		Pos = V(x, y, z),
		Size = V(sx, sy, sz),
	}, opts)
end

-- Rotating kill beam spinning around a vertical pivot at (x, z); beam height y (center).
function K.Beam(x: number, y: number, z: number, length: number, speed: number, opts: { [string]: any }?)
	return merge({
		Type = "RotatingBeam",
		Pos = V(x, y, z),
		Length = length,
		Speed = speed, -- radians per second (negative = other direction)
		Thickness = 1,
	}, opts)
end

---------------------------------------------------------------------------
-- Platforms with behaviour
---------------------------------------------------------------------------

--[[
	Moving platform. motion:
	  { Kind = "Linear", Offset = Vector3, Period = 4, Pause = 0.6 }   -- back and forth (horizontal or vertical)
	  { Kind = "Circle", Radius = 8, Period = 6 }                      -- circular (around its start point + radius on X)
	  opts.Id + Powered = true -> only moves while a linked button/plate is active
]]
function K.Mover(x: number, y: number, z: number, sx: number, sz: number, motion: { [string]: any }, opts: { [string]: any }?)
	return merge({
		Type = "MovingPlatform",
		Pos = V(x, y - 0.5, z),
		Size = V(sx, 1, sz),
		Motion = motion,
	}, opts)
end

-- Appears / disappears on a timer. cycle = { Visible = 2, Hidden = 1.5, Phase = 0 }
function K.Vanish(x: number, y: number, z: number, sx: number, sz: number, cycle: { [string]: number }, opts: { [string]: any }?)
	return merge({
		Type = "Disappearing",
		Pos = V(x, y - 0.5, z),
		Size = V(sx, 1, sz),
		Cycle = cycle,
	}, opts)
end

-- Falls shortly after something stands on it, comes back later.
function K.Falling(x: number, y: number, z: number, sx: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Falling",
		Pos = V(x, y - 0.5, z),
		Size = V(sx, 1, sz),
	}, opts)
end

--[[
	Fake platform: looks exactly like a normal floor, vanishes when stepped on (stays revealed).
	opts.Group = "row1" + level.FakeGroups = { row1 = { Fake = 1 } } -> the level randomly
	picks which platforms of the group are fake every run (the rest are real).
]]
function K.Fake(id: string, x: number, y: number, z: number, sx: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Fake",
		Id = id,
		Pos = V(x, y - 0.5, z),
		Size = V(sx, 1, sz),
	}, opts)
end

-- Launch pad with a local-space velocity.
function K.Launch(x: number, y: number, z: number, velocity: Vector3, opts: { [string]: any }?)
	return merge({
		Type = "LaunchPad",
		Pos = V(x, y, z),
		Size = V(6, 0.4, 6),
		Velocity = velocity,
	}, opts)
end

-- Teleport pad -> target (level-local, floor top of the destination).
function K.Teleport(x: number, y: number, z: number, target: Vector3, opts: { [string]: any }?)
	return merge({
		Type = "TeleportPad",
		Pos = V(x, y, z),
		Size = V(6, 0.4, 6),
		Target = target,
	}, opts)
end

---------------------------------------------------------------------------
-- Interaction: sources (buttons / plates) and targets (doors / bridges / lasers / movers)
---------------------------------------------------------------------------

--[[
	Button on a floor with top y.
	opts:
	  Targets   = { "D1", ... }       ids of doors / bridges / lasers / movers
	  Activator = "Any" | "Player" | "Doppel"
	  Mode      = "Toggle" | "Timed" | "Once" | "Hold"
	  Duration  = 5                   (Timed)
	  Shuffle   = "group"             buttons in the same group swap targets randomly each run
	  Bad       = true                marks a trap button (Troll likes those)
]]
function K.Button(id: string, x: number, y: number, z: number, opts: { [string]: any }?)
	return merge({
		Type = "Button",
		Id = id,
		Pos = V(x, y, z),
		Size = V(4, 0.5, 4),
		Mode = "Timed",
		Duration = 6,
		Activator = "Any",
		Targets = {},
	}, opts)
end

-- Pressure plate: active only while something valid stands on it (+ optional ReleaseDelay).
function K.Plate(id: string, x: number, y: number, z: number, opts: { [string]: any }?)
	return merge({
		Type = "Button",
		Id = id,
		Pos = V(x, y, z),
		Size = V(6, 0.4, 6),
		Mode = "Hold",
		ReleaseDelay = 0.4,
		Activator = "Doppel",
		Targets = {},
	}, opts)
end

--[[
	Door standing on floor y. Slides by OpenOffset when powered (default: sinks into the floor).
	opts.Logic = "All" -> needs every linked source active (default "Any").
	opts.Cycle = { Open = 2, Closed = 3, Phase = 0 } -> timed door (no buttons needed).
]]
function K.Door(id: string, x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: { [string]: any }?)
	return merge({
		Type = "Door",
		Id = id,
		Pos = V(x, y + sy / 2, z),
		Size = V(sx, sy, sz),
		OpenOffset = V(0, -(sy + 0.2), 0),
	}, opts)
end

-- Bridge with top y. Retracted by HiddenOffset while unpowered, slides into place when powered.
function K.Bridge(id: string, x: number, y: number, z: number, sx: number, sz: number, opts: { [string]: any }?)
	local hidden = (opts and opts.HiddenOffset) or V(0, -8, 0)
	return merge({
		Type = "Door",
		Bridge = true,
		Id = id,
		-- the "closed" (unpowered) position is the hidden one, OpenOffset brings it back
		Pos = V(x, y - 0.5, z) + hidden,
		Size = V(sx, 1, sz),
		OpenOffset = -hidden,
	}, opts)
end

-- Door + two side posts so nobody can walk around it. Returns a group (flattened by K.Level).
function K.Gate(id: string, x: number, y: number, z: number, width: number, height: number, opts: { [string]: any }?)
	local wing = (opts and opts.Wing) or 3
	local door = K.Door(id, x, y, z, 1, height, width, opts)
	return {
		door,
		K.Wall(x, y, z - width / 2 - wing / 2, 1.4, height + 1, wing),
		K.Wall(x, y, z + width / 2 + wing / 2, 1.4, height + 1, wing),
	}
end

---------------------------------------------------------------------------
-- Guidance
---------------------------------------------------------------------------

-- Floating billboard text (always faces the camera). y = floor height below the sign.
function K.Sign(x: number, y: number, z: number, text: string, opts: { [string]: any }?)
	return merge({
		Type = "Sign",
		Pos = V(x, y + 7, z),
		Text = text,
	}, opts)
end

---------------------------------------------------------------------------
-- AI route nodes (Rival / Ally / Troll). Pos = the floor point the doppelgänger stands on.
--[[
	opts:
	  Next        = { "id", ... }      (default: the next node in the list)
	  Weights     = { 1, 2 }           branch weights
	  Checkpoint  = 1                  rival respawns here when the player is at checkpoint 1 (0 = start)
	  Safe        = true               rival respawns here after its own death
	  On          = "elementId"        node sits on a moving / fake platform
	  Gate        = "D1"               wait here until mechanism D1 is powered
	  Timeout     = 2.5                (Gate) give up after this long -> Fallback
	  Fallback    = { "id", ... }      nodes to try when a gate times out or the path is blocked
	  AvoidVisited = true              prefer branches not visited yet
	  Hazard      = true               check for active hazards before leaving this node
	  Jump        = true / false       force / forbid a jump to reach this node
	  Finish      = true               reaching it = the rival finished
]]
---------------------------------------------------------------------------
function K.Node(id: string, x: number, y: number, z: number, opts: { [string]: any }?)
	return merge({
		Id = id,
		Pos = V(x, y, z),
	}, opts)
end

---------------------------------------------------------------------------
-- Level wrapper: flattens nested element groups (K.Gate etc.) into one list.
---------------------------------------------------------------------------
local function flatten(list, out)
	for _, item in list do
		if type(item) == "table" and item.Type == nil and item[1] ~= nil then
			flatten(item, out)
		else
			table.insert(out, item)
		end
	end
	return out
end

function K.Level(def: { [string]: any })
	def.Elements = flatten(def.Elements or {}, {})
	return def
end

return K
