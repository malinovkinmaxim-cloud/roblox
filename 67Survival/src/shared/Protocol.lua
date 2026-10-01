--[[
	Protocol - the binary format of the run "Frame" sent server -> client 10 times per second.

	A frame is a buffer of records: uint8 record id + fixed fields. Everything the client
	needs to draw a run travels here (enemy spawns / positions / deaths, hits for damage
	numbers, XP gems, pickups, weapon effects, boss telegraphs...). One reliable
	RemoteEvent call per frame keeps records ordered: a death is always seen before the
	spawn that reuses the id.

	Field types:
	  u8 u16 u32 i16 f32   plain numbers
	  q    coordinate (studs): int16 of v * CoordScale (+-327 studs, 1 cm precision)
	  a    angle (radians): uint16 of the full circle
	  s    small positive number: uint16 of v * 100 (0 .. 655.35)
	  v    velocity: int16 of v * 100 (+-327)
]]

local GameConfig = require(script.Parent.GameConfig)

local Protocol = {}

local SCALE = GameConfig.Sim.CoordScale
local TAU = math.pi * 2

-- name -> { Id, Fields }. Ids are the wire format: append new records at the end.
local RECORDS = {
	{ "State", { "f32", "u16", "u16", "u16", "u16", "u32", "u32", "u8" } }, -- time, hp, maxHp, level, xpFrac(0..65535), kills, coins, flags
	{ "Spawn", { "u16", "u8", "q", "q", "u8" } }, -- id, kind, x, z, flags
	{ "Death", { "u16", "u8" } }, -- id, cause (0 killed, 1 despawned)
	{ "Hit", { "u16", "u32", "u8" } }, -- id, damage, flags (Protocol.HitFlags)
	{ "GemSpawn", { "u16", "q", "q", "u8" } }, -- id, x, z, tier
	{ "GemTake", { "u16" } }, -- id (flies to the player)
	{ "GemTier", { "u16", "u8" } }, -- id, new tier (merged)
	{ "ItemSpawn", { "u16", "u8", "q", "q" } }, -- id, kind, x, z
	{ "ItemTake", { "u16" } }, -- id
	{ "Fx", { "u8", "q", "q", "a", "s", "s", "u8" } }, -- weapon id, x, z, angle, p1, p2, variant
	{ "Proj", { "u16", "u8", "q", "q", "a", "s", "s", "u16" } }, -- id, weapon id, x, z, angle, speed, life, target enemy
	{ "ProjEnd", { "u16", "q", "q", "u8" } }, -- id, x, z, flags (1 explode)
	{ "EProj", { "u16", "q", "q", "v", "v", "s", "s" } }, -- id, x, z, vx, vz, radius, life
	{ "EProjEnd", { "u16" } }, -- id
	{ "Telegraph", { "u8", "q", "q", "a", "s", "s", "s" } }, -- shape (1 circle, 2 dash line, 3 lingering zone, 4 laser line), x, z, angle, size, width (zone: duration), delay
	{ "Hurt", { "u16" } }, -- damage the player took
	{ "Heal", { "u16" } }, -- hp healed
	{ "Shrink", { "u16" } }, -- enemy id became tiny
	{ "Blink", { "u16", "q", "q" } }, -- enemy teleported
	{ "EState", { "u16", "u8" } }, -- enemy visual state (Protocol.EState)
	{ "Boss", { "u16", "u32", "u32" } }, -- boss id, hp, max hp
	{ "Ally", { "u8", "q", "q" } }, -- ally index, x, z
	{ "Coin", { "u16" } }, -- coins picked up
	{ "Pos", { "u16", "q", "q" } }, -- enemy id, x, z (the bulk of every frame)
	{ "Slash", { "u8", "q", "q" } }, -- ally bite / small hit effect: kind, x, z
	{ "ItemGone", { "u16" } }, -- pickup expired (no fly-to-player animation)
	{ "Zone", { "u16", "u8", "q", "q", "s", "s" } }, -- lingering weapon zone: id, weapon id, x, z, radius, duration
	{ "ZoneEnd", { "u16" } }, -- zone gone
	{ "Clone", { "q", "q", "s" } }, -- decoy clone: x, z, duration
	{ "Burn", { "u16", "s" } }, -- enemy id starts burning for n seconds (visual)
	-- 67 TOWN: bosses, elites, item loot, vaults (Sim/MiniBosses, Sim/Elites, Sim/Items)
	{ "MiniHP", { "u16", "u16", "u8" } }, -- boss / elite id, hp fraction (0..65535), flags (Protocol.MiniFlags)
	{ "LootSpawn", { "u16", "u8", "q", "q" } }, -- loot id, item id (shared/ItemData; 255 = a SOUL), x, z
	{ "LootTake", { "u16" } }, -- picked up
	{ "LootGone", { "u16" } }, -- removed without a pickup
	{ "Vault", { "u8", "u8", "u8" } }, -- vault index, state (Protocol.VaultState), capture percent
	{ "Dash", { "u8", "u8", "s" } }, -- dash charges, max charges, seconds to the next charge
	{ "Plating", { "u16", "u16" } }, -- plating shield: current, max
	{ "Shadow", { "q", "q", "u8" } }, -- SECOND SHADOW: x, z, shown (0/1)
}

Protocol.Records = {} :: { [string]: { Id: number, Fields: { string } } }
Protocol.ById = {} :: { [number]: { Name: string, Fields: { string } } }
for id, entry in RECORDS do
	Protocol.Records[entry[1]] = { Id = id, Fields = entry[2] }
	Protocol.ById[id] = { Name = entry[1], Fields = entry[2] }
end

Protocol.Flags = {
	Tiny = 1,
	Golden = 2,
	FromSky = 4,
	Boss = 8,
	Elite = 16,
	Giant = 32, -- 67 MODE: GIANT
	Champion = 64, -- a boss of 67 TOWN with a name plate
	Sketch = 128, -- THE ERASER's redrawn sketch of an elite (no loot)
	Paused = 1, -- State flags
	Dead = 2,
	Event67 = 4, -- a 67 event is running
	XPBoost = 8, -- XP is boosted (XP Storm, 67%)
	Shield = 16, -- Barrier has a charge
}

-- enemy visual states (EState record)
Protocol.EState = {
	Normal = 0,
	Windup = 1, -- about to attack (flashes)
	Dash = 2, -- charging / diving / jumping
	Frozen = 3,
	Phased = 4, -- Ghost: faded out, can't hurt or be hurt
	Dormant = 5, -- Mimic: still pretending to be a loot box
	Lit = 6, -- Bomber: fuse is burning
	Stunned = 7, -- stunned by an ability or an item (stars)
	Broken = 8, -- its shield / banner is broken (Shielder): the "Breakable" parts are gone
	Enraged = 9, -- raging (SIXLET without its SEVENLET, BERSERK): glows
}

-- boss / elite flags (MiniHP record)
Protocol.MiniFlags = {
	Shielded = 1, -- can't be hurt (JACKPOT JIMMY's tilt)
	Stunned = 2, -- JACKPOT! (takes more damage)
	Enraged = 4, -- phase 2+
	Home = 8, -- walking home to heal
	Exposed = 16, -- its WEAK POINT is open: hit it now
	Crowned = 32, -- 67 BOSS: tougher, double loot
	Marked = 64, -- a DEATH MARK is on it
}

-- 67 VAULT states (Vault record)
Protocol.VaultState = {
	Asleep = 0,
	Awake = 1, -- stand on the pad to open it
	Opened = 2,
}

-- Hit flags
Protocol.HitFlags = {
	Crit = 1,
	Six = 2, -- the 67% passive
	Burn = 4,
	Execute = 8,
	Weak = 16, -- hit a boss's open WEAK POINT
	Big = 32, -- a special strike (triple, crowned, 67 FRAGMENT)
}

-- pickup kinds (ItemSpawn kind = index)
Protocol.Items = { "Snack", "Magnet", "Nuke", "Chest", "CoinBag", "Coin", "Chest67", "Fragment" }
Protocol.ItemIndex = {} :: { [string]: number }
for i, name in Protocol.Items do
	Protocol.ItemIndex[name] = i
end

-- Fx records with weapon id 0 are generic effects; the variant says which one
Protocol.Fx = {
	Revive = 9,
	Nuke = 10,
	Storm = 11,
	Freeze = 12,
	Shrink = 13,
	SigmaStare = 14,
	Blast67 = 15, -- THE 67 hero: every 67th kill
	GlitchStep = 16, -- THE GLITCH hero teleports (x, z = from; p1 = angle, p2 = distance)
	Thorns = 17,
	Bomb = 18, -- a Bomber exploded
	Land = 19, -- a Leaper / boss landed
	Slam = 20,
	Enrage = 21,
	Teleport = 22, -- a boss teleported
	Sweep = 23, -- a boss laser line fired (angle, length, width)
	Chaos67 = 24,
	Event67 = 25, -- the 67 event started (big ring)
	Hazard = 26, -- a void zone tick
	Execute = 27,
	Evolve = 28, -- an ability evolved
	MiniSpawn = 29, -- a mini-boss arrives (p1 = radius)
	Trail = 30, -- a fire patch of the Hot Sauce Socks (p1 = radius, p2 = life)
	Dash = 31, -- the player dashed (x, z = from; angle; p1 = distance)
	VaultOpen = 32, -- a 67 VAULT cracked open
	Jackpot = 33, -- JACKPOT JIMMY hit 7-7-7 (coins burst)
	RelicTake = 34, -- a relic picked up (p2 = relic id)
	TwinRevive = 35, -- SIX or SEVEN came back
	Alarm = 36, -- TICK TOCK's alarm: it escapes
	Zap = 37, -- a zap from (x, z) along angle for p1 studs
	TimeStop = 38, -- the Pocket Watch (p1 = radius)
	-- the build (Sim/Perks.lua): p1 = radius unless noted
	Synergy = 39, -- a synergy switched on
	Crowned = 40, -- a crowned / 67 FRAGMENT strike
	Stomp = 41, -- Giant's Toe
	Strike = 42, -- a lightning strike (STORM FRONT)
	MarkBlast = 43, -- a DEATH MARK exploded
	Nova = 44, -- a blast around you (shockwaves, panic, marathon...)
	Pact = 45, -- Twin Pact passes a kill on (angle, p1 = length)
	Shatter = 46, -- DEEP FREEZE
	Dodge = 47,
	Guard = 48, -- the Fang's guard blocked a hit
	Panic = 49,
	Fracture = 50, -- TIME FRACTURE (p2 = duration)
	Ram = 51, -- Cart Wheel dash (angle, p1 = length, p2 = width)
	Pulse = 52, -- Magnetic Bolt pulse
	Reel = 53, -- Lucky Lever: no jackpot
	Flop = 54, -- Quack Core belly-flop
	Servo = 55, -- Servo Laser (angle, p1 = length, p2 = width)
	Troops = 56, -- Overlord's Banner
	Marked = 57, -- a DEATH MARK was placed
	Whoopee = 58,
	ShadowIn = 59, -- the SECOND SHADOW appears
	Soul = 60, -- a soul taken
	Mirror = 61, -- the Void Mirror reflected a shot
	-- bosses and elites
	Phase = 62, -- a boss entered its next phase
	Exposed = 63, -- a boss's weak point opened
	Seal = 64, -- the 67 ARENA was sealed (p1 = radius)
	EliteSpawn = 65, -- an elite appeared (p1 = radius)
	EliteBlast = 66, -- a VOLATILE elite blew up
	Pull = 67, -- the main boss pulls you into its arena
	-- the harder tiers
	Lava = 68, -- an Eruptor's lava lob (x, z = from; angle; p1 = distance; p2 = flight time)
	Gravity = 69, -- a gravity pulse (p1 = radius)
	ShieldBreak = 70, -- a Shielder's shield / a SHIELDED elite's shield broke (p1 = radius)
	Rage = 71, -- a SIXLET / SEVENLET / BERSERK elite goes mad (p1 = radius)
	Hatch = 72, -- a goo egg hatched (p1 = radius)
	Rally = 73, -- a war banner / bannerman rally pulse (p1 = radius)
	Block = 74, -- a hit bounced off a shield (p1 = radius)
}

-- Zone record "weapon id" for the build's own pools (Sim/Perks.lua)
Protocol.ZoneStyle = { Puddle = 250, Void = 251, Cloud = 252, Spill = 253, Gravity = 254 }

--[[
	Telegraph shapes (Telegraph record):
	  1 circle   2 dash line (visual)   3 lingering void zone (width = duration)
	  4 laser line   5 slippery puddle (lingering, slows you; width = duration)
	  6 spill (lingering, small, hurts; width = duration)
	  7 sector: a pie slice around (x, z) towards angle, radius = size, width = half its arc;
	    it burns for SectorBurn seconds after it fills
	  8 safe circle (white, visual): stand here when everything around burns
	  9 erased floor (white, lingering, hurts; width = duration)
	  10 safe sector (white, visual)
]]
Protocol.Shapes = { Circle = 1, DashLine = 2, Void = 3, Laser = 4, Puddle = 5, Spill = 6, Sector = 7, Safe = 8, Erase = 9, SafeSector = 10 }
Protocol.SectorBurn = 1.2 -- seconds a sector keeps burning after its warning

local SIZES = { u8 = 1, u16 = 2, u32 = 4, i16 = 2, f32 = 4, q = 2, a = 2, s = 2, v = 2 }

---------------------------------------------------------------------------
-- writer
---------------------------------------------------------------------------
export type Writer = { Buf: buffer, Pos: number, Count: number }

function Protocol.NewWriter(capacity: number?): Writer
	return { Buf = buffer.create(capacity or 1024), Pos = 0, Count = 0 }
end

local function ensure(w: Writer, n: number)
	local len = buffer.len(w.Buf)
	if w.Pos + n <= len then
		return
	end
	local size = len * 2
	while w.Pos + n > size do
		size *= 2
	end
	local new = buffer.create(size)
	buffer.copy(new, 0, w.Buf, 0, w.Pos)
	w.Buf = new
end

local function clampInt(v: number, lo: number, hi: number): number
	if v ~= v then
		return 0
	end
	v = math.floor(v + 0.5)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function writeField(w: Writer, kind: string, value: number)
	local b, p = w.Buf, w.Pos
	if kind == "u8" then
		buffer.writeu8(b, p, clampInt(value, 0, 255))
	elseif kind == "u16" then
		buffer.writeu16(b, p, clampInt(value, 0, 65535))
	elseif kind == "u32" then
		buffer.writeu32(b, p, clampInt(value, 0, 4294967295))
	elseif kind == "i16" then
		buffer.writei16(b, p, clampInt(value, -32768, 32767))
	elseif kind == "f32" then
		buffer.writef32(b, p, if value == value then value else 0)
	elseif kind == "q" then
		buffer.writei16(b, p, clampInt(value * SCALE, -32768, 32767))
	elseif kind == "a" then
		local turns = (value % TAU) / TAU
		buffer.writeu16(b, p, clampInt(turns * 65536, 0, 65536) % 65536)
	elseif kind == "s" then
		buffer.writeu16(b, p, clampInt(value * 100, 0, 65535))
	elseif kind == "v" then
		buffer.writei16(b, p, clampInt(value * 100, -32768, 32767))
	else
		error("unknown field type " .. kind)
	end
	w.Pos = p + SIZES[kind]
end

-- Protocol.Write(writer, "Spawn", id, kind, x, z, flags)
function Protocol.Write(w: Writer, name: string, ...: number)
	local record = Protocol.Records[name]
	assert(record, "unknown record " .. name)
	local fields = record.Fields
	local size = 1
	for _, kind in fields do
		size += SIZES[kind]
	end
	ensure(w, size)
	buffer.writeu8(w.Buf, w.Pos, record.Id)
	w.Pos += 1
	for i, kind in fields do
		writeField(w, kind, (select(i, ...)) or 0)
	end
	w.Count += 1
end

-- The finished frame (a right-sized copy of the written bytes)
function Protocol.Finish(w: Writer): buffer
	local out = buffer.create(w.Pos)
	buffer.copy(out, 0, w.Buf, 0, w.Pos)
	return out
end

function Protocol.Reset(w: Writer)
	w.Pos = 0
	w.Count = 0
end

---------------------------------------------------------------------------
-- reader
---------------------------------------------------------------------------
local function readField(b: buffer, p: number, kind: string): number
	if kind == "u8" then
		return buffer.readu8(b, p)
	elseif kind == "u16" then
		return buffer.readu16(b, p)
	elseif kind == "u32" then
		return buffer.readu32(b, p)
	elseif kind == "i16" then
		return buffer.readi16(b, p)
	elseif kind == "f32" then
		return buffer.readf32(b, p)
	elseif kind == "q" then
		return buffer.readi16(b, p) / SCALE
	elseif kind == "a" then
		return buffer.readu16(b, p) / 65536 * TAU
	elseif kind == "s" then
		return buffer.readu16(b, p) / 100
	elseif kind == "v" then
		return buffer.readi16(b, p) / 100
	end
	error("unknown field type " .. kind)
end

--[[
	Calls handlers[recordName](fields...) for every record, in order.
	Unknown or truncated data stops decoding (returns false) instead of throwing.
]]
function Protocol.Decode(b: buffer, handlers: { [string]: (...number) -> () }): boolean
	if typeof(b) ~= "buffer" then
		return false
	end
	local len = buffer.len(b)
	local p = 0
	local values = table.create(8, 0)
	while p < len do
		local record = Protocol.ById[buffer.readu8(b, p)]
		if not record then
			return false
		end
		p += 1
		local fields = record.Fields
		local n = #fields
		for i = 1, n do
			local kind = fields[i]
			if p + SIZES[kind] > len then
				return false
			end
			values[i] = readField(b, p, kind)
			p += SIZES[kind]
		end
		local handler = handlers[record.Name]
		if handler then
			handler(table.unpack(values, 1, n))
		end
	end
	return true
end

return Protocol
