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
	{ "Hit", { "u16", "u32", "u8" } }, -- id, damage, flags (1 crit, 2 "67")
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
	{ "Telegraph", { "u8", "q", "q", "a", "s", "s", "s" } }, -- shape (1 circle, 2 line), x, z, angle, size, width, delay
	{ "Hurt", { "u16" } }, -- damage the player took
	{ "Heal", { "u16" } }, -- hp healed
	{ "Shrink", { "u16" } }, -- enemy id became tiny
	{ "Blink", { "u16", "q", "q" } }, -- enemy teleported
	{ "EState", { "u16", "u8" } }, -- enemy visual state (0 normal, 1 windup, 2 dash, 3 frozen)
	{ "Boss", { "u16", "u32", "u32" } }, -- boss id, hp, max hp
	{ "Ally", { "u8", "q", "q" } }, -- ally index, x, z
	{ "Coin", { "u16" } }, -- coins picked up
	{ "Pos", { "u16", "q", "q" } }, -- enemy id, x, z (the bulk of every frame)
	{ "Slash", { "u8", "q", "q" } }, -- ally bite / small hit effect: kind, x, z
	{ "ItemGone", { "u16" } }, -- pickup expired (no fly-to-player animation)
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
	Paused = 1, -- State flags
	Dead = 2,
	Sigma = 4,
	Storm = 8,
}

-- pickup kinds (ItemSpawn kind = index)
Protocol.Items = { "Pizza", "Magnet", "Nuke", "Chest", "CoinBag", "Coin" }
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
	Slam = 20,
	Enrage = 21,
}

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
