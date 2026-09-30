--[[
	Items - the ITEMS of a run (shared/ItemData.lua): what you carry and at which level, the
	loot lying on the map, picking it up, SOULS, and the DASH.

	  run.Items[key]  = level (1..MaxLevel), run.ItemOrder = the order you found them
	  run.Loot        = items and souls on the ground: { Id, Key, X, Z, At, Soul? }

	Loot: Items.Roll(run, source) picks an item for a LootData source (elite, vault, boss 1-4,
	secret) from the player's pool (base items + unlocked premium items; boss relics only drop
	from their boss via Items.DropRelic). Items.Drop puts it ON THE MAP (LootSpawn); walking
	over it takes it (Items.Gain): a new item starts at level I, one you carry goes up a level
	(II, III...), a maxed one turns into coins. Every pickup is decided here, once: the client
	only draws what it is told, so nothing can be picked up twice.

	What items DO lives in Sim/Perks.lua (the effects of items, level ups and synergies).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local ItemData = require(Shared.ItemData)
local LootData = require(Shared.LootData)
local ArenaData = require(Shared.ArenaData)
local Rarity = require(Shared.Rarity)
local Protocol = require(Shared.Protocol)

local Perks = require(script.Parent.Perks)

local Items = {}

local sqrt, max, abs, cos, sin, atan2 = math.sqrt, math.max, math.abs, math.cos, math.sin, math.atan2
local GFX = Protocol.Fx
local BY_KEY = ItemData.ByKey
Items.SOUL = 255 -- LootSpawn item id of a soul (Soul Collector)

-- lazy: EnemyManager requires modules that require this one
local enemies: any = nil
local function EM(): any
	if not enemies then
		enemies = require(script.Parent.EnemyManager) :: any
	end
	return enemies
end

function Items.Init(run, unlocks: { [string]: boolean }?)
	run.Items = {} -- key -> level
	run.ItemOrder = {}
	run.ItemUnlocks = unlocks or {} -- premium items / boss relics unlocked with CHIPS
	run.Loot = {}
	run.DashState = nil
	Perks.Init(run)
end

function Items.Level(run, key: string): number
	return run.Items[key] or 0
end

-- can this item be in the player's loot pool at all?
function Items.InPool(run, def): boolean
	if def.Secret then
		return false
	end
	if def.Type == "BossRelic" then
		return false -- only from its boss
	end
	if ItemData.NeedsUnlock(def) and not run.ItemUnlocks[def.Key] then
		return false
	end
	if def.Requires and def.Requires.Item and (run.Items[def.Requires.Item] or 0) <= 0 then
		return false
	end
	return true
end

-- the level it would have once everything already lying on the ground is taken
local function pendingLevel(run, key: string): number
	local n = run.Items[key] or 0
	for _, l in run.Loot do
		if l.Key == key then
			n += 1
		end
	end
	return n
end

-- a random item for a loot source (LootData.Sources), or nil when everything is maxed
function Items.Roll(run, sourceName: string): string?
	local source = LootData.Source(sourceName)
	local rng = run.Rng
	-- "find it again": upgrade an item you carry
	if source.Owned > 0 and rng:NextNumber() < source.Owned then
		local owned = {}
		for _, key in run.ItemOrder do
			local def = BY_KEY[key]
			if def and not def.Secret and pendingLevel(run, key) < def.MaxLevel then
				table.insert(owned, key)
			end
		end
		if #owned > 0 then
			return owned[rng:NextInteger(1, #owned)]
		end
	end
	local weights = source.Weights
	local luck = run.Stats.Luck
	local pools = {}
	for _, def in ItemData.List do
		if weights[def.Rarity] and Items.InPool(run, def) and pendingLevel(run, def.Key) < def.MaxLevel then
			pools[def.Rarity] = pools[def.Rarity] or {}
			table.insert(pools[def.Rarity], def.Key)
		end
	end
	local function weightOf(rarity: string): number
		if not pools[rarity] then
			return 0
		end
		return weights[rarity] * max(0.2, 1 + (luck - 1) * (Rarity.LuckScale[rarity] or 0))
	end
	local total = 0
	for _, rarity in ItemData.Tiers do
		total += weightOf(rarity)
	end
	if total <= 0 then
		-- the source's rarities are all taken: anything still available
		for _, rarity in ItemData.Tiers do
			local list = pools[rarity]
			if list then
				return list[rng:NextInteger(1, #list)]
			end
		end
		return nil
	end
	local r = rng:NextNumber(0, total)
	for _, rarity in ItemData.Tiers do
		local w = weightOf(rarity)
		if w > 0 then
			r -= w
			if r <= 0 then
				local list = pools[rarity]
				return list[rng:NextInteger(1, #list)]
			end
		end
	end
	return nil
end

-- a free spot for loot near (x, z): inside the map, out of walls
local function spot(run, x: number, z: number): (number, number)
	local h = GameConfig.Arena.HalfSize - 4
	x, z = math.clamp(x, -h, h), math.clamp(z, -h, h)
	for i = 0, 7 do
		if not EM().InsideCollider(run, x, z, 1) then
			break
		end
		local a = i * (math.pi / 4)
		x, z = math.clamp(x + cos(a) * 4, -h, h), math.clamp(z + sin(a) * 4, -h, h)
	end
	return x, z
end

local function put(run, key: string?, itemId: number, x: number, z: number, soul: boolean?)
	x, z = spot(run, x, z)
	local loot = run.Loot
	if #loot >= LootData.MaxOnGround then
		-- the oldest SOUL goes first, then the oldest item
		local drop = 1
		for i, l in loot do
			if l.Soul then
				drop = i
				break
			end
		end
		local old = table.remove(loot, drop)
		run:Write("LootGone", old.Id)
	end
	run.NextLootId = (run.NextLootId or 0) % 65535 + 1
	local l = { Id = run.NextLootId, Key = key, X = x, Z = z, At = run.Time, Soul = soul }
	table.insert(loot, l)
	run:Write("LootSpawn", l.Id, itemId, x, z)
	return l
end

-- puts an item on the ground
function Items.Drop(run, key: string, x: number, z: number)
	local def = BY_KEY[key]
	if not def then
		return nil
	end
	return put(run, key, def.Id, x, z)
end

-- rolls a source and drops what it gives around (x, z). Returns the keys dropped.
function Items.DropFrom(run, sourceName: string, x: number, z: number, count: number?): { string }
	local source = LootData.Source(sourceName)
	local out = {}
	local n = count or source.Count
	local chance = source.Chance
	local luck = sourceName == "Elite" and run.UP and run.UP.Luck and run.UP.Luck.EliteLoot
	if luck then
		chance *= luck -- Luck IV
	end
	for i = 1, n do
		if run.Rng:NextNumber() <= chance then
			local key = Items.Roll(run, sourceName)
			if key then
				local a = (i - 1) * 2.4 + 0.6
				local r = if n > 1 then 3.5 else 0
				Items.Drop(run, key, x + cos(a) * r, z + sin(a) * r)
				table.insert(out, key)
			end
		end
	end
	return out
end

-- a boss's own relic (only when the player unlocked it); true when it dropped
function Items.DropRelic(run, bossKey: string, x: number, z: number): boolean
	local def = ItemData.ByBoss[bossKey]
	if not def or not run.ItemUnlocks[def.Key] then
		return false
	end
	if pendingLevel(run, def.Key) >= def.MaxLevel then
		return false
	end
	Items.Drop(run, def.Key, x, z)
	return true
end

-- a SOUL (Soul Collector): lies on the ground until taken
function Items.DropSoul(run, x: number, z: number)
	put(run, nil, Items.SOUL, x, z, true)
end

-- the item is yours (a new one at level I, else one level up)
function Items.Gain(run, key: string)
	local def = BY_KEY[key]
	if not def then
		return
	end
	local level = run.Items[key] or 0
	if level >= def.MaxLevel then
		run:AddCoins(LootData.MaxedCoins)
		run:Event("Item", { Key = key, Level = level, Old = level, Maxed = true })
		return
	end
	local old = level
	level += 1
	run.Items[key] = level
	if old == 0 then
		table.insert(run.ItemOrder, key)
	end
	-- revives come with the level that grants them (Golden Snack)
	local before = ItemData.At(key, old)
	local now = ItemData.At(key, level)
	local gained = ((now and now.Stats and now.Stats.Revives) or 0) - ((before and before.Stats and before.Stats.Revives) or 0)
	if gained > 0 then
		run.Revives += gained
	end
	run.Result.ItemsPicked = (run.Result.ItemsPicked or 0) + 1
	Perks.Refresh(run)
	run:RefreshStats()
	run:SendLoadout()
	run:Write("Fx", 0, run.PX, run.PZ, 0, 6, def.Id, GFX.RelicTake)
	run:Event("Item", { Key = key, Level = level, Old = old, New = now and now.New or nil })
end

local function stepLoot(run)
	local loot = run.Loot
	local r2 = LootData.PickupRadius * LootData.PickupRadius
	local i = 1
	while i <= #loot do
		local l = loot[i]
		local dx, dz = l.X - run.PX, l.Z - run.PZ
		if dx * dx + dz * dz <= r2 then
			table.remove(loot, i)
			run:Write("LootTake", l.Id)
			if l.Soul then
				Perks.GainSoul(run)
			else
				Items.Gain(run, l.Key)
			end
		else
			i += 1
		end
	end
end

---------------------------------------------------------------------------
-- dash
---------------------------------------------------------------------------
local function sendDash(run)
	local dash = run.DashState
	if dash then
		run:Write("Dash", dash.Charges, dash.Max, if dash.Charges < dash.Max then max(0, dash.Timer) else 0)
	end
end
Items.SendDash = sendDash

-- true when the simulation must not put the player at (x, z): a wall, the map edge, the
-- sealed rift, the sealed 67 ARENA ring
function Items.Blocked(run, x: number, z: number): boolean
	local h = GameConfig.Arena.HalfSize - 3
	if abs(x) > h or abs(z) > h then
		return true
	end
	if run.Map and not run.Map.RiftOpen and ArenaData.ZoneAt(x, z).Locked then
		return true
	end
	local arena = run.Map and run.Map.ArenaSealed
	if arena then
		local d = sqrt((x - arena.X) ^ 2 + (z - arena.Z) ^ 2)
		if d > arena.R - 1.5 then
			return true
		end
	end
	return EM().InsideCollider(run, x, z, 1.2)
end

function Items.Dash(run, dx: number, dz: number): boolean
	local dash = run.DashState
	if not dash or dash.Charges < 1 or run:IsPaused() or run.Dead or run.Ended then
		return false
	end
	if dx ~= dx or dz ~= dz then
		dx, dz = 0, 0
	end
	local len = sqrt(dx * dx + dz * dz)
	if len < 0.1 then
		dx, dz = run.FX, run.FZ -- no direction held: dash where you face
	else
		dx, dz = dx / len, dz / len
	end
	-- step along the line: stop in front of walls
	local x, z = run.PX, run.PZ
	local moved = 0
	for i = 1, math.floor(dash.Distance) do
		local nx, nz = run.PX + dx * i, run.PZ + dz * i
		if Items.Blocked(run, nx, nz) then
			break
		end
		x, z, moved = nx, nz, i
	end
	if moved < 2 then
		return false
	end
	local fromX, fromZ = run.PX, run.PZ
	run:Write("Fx", 0, run.PX, run.PZ, atan2(dz, dx), moved, 0, GFX.Dash)
	run.PX, run.PZ = x, z
	run.FX, run.FZ = dx, dz
	run.TeleportTo = { X = x, Z = z }
	run.Invulnerable = max(run.Invulnerable, dash.Invulnerable)
	if dash.Charges >= dash.Max then
		dash.Timer = dash.Recharge
	end
	dash.Charges -= 1
	run.Result.Dashes = (run.Result.Dashes or 0) + 1
	Perks.OnDash(run, fromX, fromZ, x, z, dx, dz, moved)
	sendDash(run)
	return true
end

-- dash charges come back over time (faster at full KING OF MOVEMENT + PERPETUAL MOTION)
local function stepDash(run, dt: number)
	local dash = run.DashState
	if dash and dash.Charges < dash.Max then
		dash.Timer -= dt * Perks.DashRechargeRate(run)
		if dash.Timer <= 0 then
			dash.Charges += 1
			dash.Timer = if dash.Charges < dash.Max then dash.Recharge else 0
			sendDash(run)
		end
	end
end

function Items.Step(run, dt: number)
	stepDash(run, dt)
	Perks.Step(run, dt)
	stepLoot(run)
end

return Items
