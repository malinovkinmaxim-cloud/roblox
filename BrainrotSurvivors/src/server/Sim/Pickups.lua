--[[
	Pickups - XP gems and items of a run.

	Gems: collected inside the pickup range (Magnet stat). When the gem cap is reached new
	XP is merged into a nearby gem (it grows a tier) instead of creating more objects.
	Items: Pizza (heal), Magnet (collect every gem), Nuke (clear the screen), Chest (a
	treasure offer), CoinBag, Coin.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)

local Pickups = {}

local ITEM = Protocol.ItemIndex
local ITEM_LIFE = { Coin = 45, Pizza = 90, Magnet = 90, Nuke = 90, CoinBag = 90 }

local function tierOf(value: number): number
	local tiers = GameConfig.Drops.GemTiers
	local tier = 1
	for i, threshold in tiers do
		if value >= threshold then
			tier = i
		end
	end
	return tier
end
Pickups.TierOf = tierOf

local function nextId(run, field: string): number
	run[field] = (run[field] or 0) % 65535 + 1
	return run[field]
end

function Pickups.SpawnGem(run, x: number, z: number, value: number)
	local gems = run.Gems
	if #gems >= GameConfig.Sim.MaxGems then
		-- merge into the closest gem nearby, or the oldest one
		local best, bestD = gems[1], math.huge
		for _, g in gems do
			local dx, dz = g.X - x, g.Z - z
			local d = dx * dx + dz * dz
			if d < bestD then
				best, bestD = g, d
			end
		end
		if bestD > 144 then
			best = gems[1]
		end
		best.Value += value
		local tier = tierOf(best.Value)
		if tier ~= best.Tier then
			best.Tier = tier
			run:Write("GemTier", best.Id, tier)
		end
		return
	end
	local g = { Id = nextId(run, "NextGemId"), X = x, Z = z, Value = value, Tier = tierOf(value) }
	table.insert(gems, g)
	run:Write("GemSpawn", g.Id, x, z, g.Tier)
end

function Pickups.SpawnItem(run, kind: string, x: number, z: number)
	local items = run.Items
	if #items >= GameConfig.Sim.MaxPickups then
		-- drop the oldest coin (or oldest non-chest) to make room
		local victim = nil
		for i, it in items do
			if it.Kind == "Coin" then
				victim = i
				break
			end
		end
		if not victim then
			for i, it in items do
				if it.Kind ~= "Chest" then
					victim = i
					break
				end
			end
		end
		if not victim then
			return
		end
		run:Write("ItemGone", items[victim].Id)
		table.remove(items, victim)
	end
	local half = GameConfig.Arena.HalfSize
	x, z = math.clamp(x, -half, half), math.clamp(z, -half, half)
	local life = ITEM_LIFE[kind]
	local it = { Id = nextId(run, "NextItemId"), Kind = kind, X = x, Z = z, Expires = if life then run.Time + life else nil }
	table.insert(items, it)
	run:Write("ItemSpawn", it.Id, ITEM[kind], x, z)
end

local function nuke(run)
	local EnemyManager = require(script.Parent.EnemyManager) :: any -- lazy: EnemyManager requires Pickups
	local r2 = GameConfig.Drops.NukeRadius ^ 2
	for _, e in table.clone(run.Enemies) do
		local dx, dz = e.X - run.PX, e.Z - run.PZ
		if dx * dx + dz * dz <= r2 and e.Key ~= "Crate" then
			local dmg = if e.IsBoss then e.MaxHP * 0.05 else e.HP + 1
			EnemyManager.Damage(run, e, dmg, 0, dx, dz, 6)
		end
	end
	run:Write("Fx", 0, run.PX, run.PZ, 0, GameConfig.Drops.NukeRadius, 0, Protocol.Fx.Nuke)
	run:Event("Nuke", {})
end

local function collectItem(run, it)
	local kind = it.Kind
	if kind == "Pizza" then
		run:Heal(GameConfig.Drops.HealAmount)
	elseif kind == "Magnet" then
		run.MagnetAll = true
	elseif kind == "Nuke" then
		nuke(run)
	elseif kind == "Chest" then
		run.PendingChests += 1
	elseif kind == "CoinBag" then
		run:AddCoins(GameConfig.Rewards.CoinBagValue)
	elseif kind == "Coin" then
		run:AddCoins(GameConfig.Rewards.CoinDropValue)
	end
end

function Pickups.Step(run, _dt: number)
	local px, pz = run.PX, run.PZ
	local range = run.Stats.PickupRange
	if run:Buff("Sigma") then
		range *= 1.5
	end
	local r2 = range * range

	local gems = run.Gems
	local all = run.MagnetAll
	run.MagnetAll = false
	local i = 1
	while i <= #gems do
		local g = gems[i]
		local dx, dz = g.X - px, g.Z - pz
		if all or dx * dx + dz * dz <= r2 then
			run:Write("GemTake", g.Id)
			run.Result.Gems += 1
			run:AddXP(g.Value)
			table.remove(gems, i) -- keeps age order (index 1 = oldest) for merging
		else
			i += 1
		end
	end

	local items = run.Items
	local itemR2 = math.max(16, r2 * 0.35)
	i = 1
	while i <= #items do
		local it = items[i]
		local dx, dz = it.X - px, it.Z - pz
		local reach = if it.Kind == "Coin" then r2 else itemR2
		if dx * dx + dz * dz <= reach then
			run:Write("ItemTake", it.Id)
			table.remove(items, i)
			collectItem(run, it)
		elseif it.Expires and run.Time >= it.Expires then
			run:Write("ItemGone", it.Id)
			table.remove(items, i)
		else
			i += 1
		end
	end
end

return Pickups
