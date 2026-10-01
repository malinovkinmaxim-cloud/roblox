--!nocheck
--[[
	Bot - a simple survivor player for headless playtests.

	Movement: runs away from nearby enemies (bosses count more), steps out of telegraphs
	(boss circles, laser lines, void zones, puddles, spills, lit bombers, leaper landings,
	sniper lines), dodges enemy projectiles, collects gems and pickups, chases loot crates and
	runaway goblins, stays away from the arena walls and walks around ponds (water slows you).
	67 TOWN: goes for items and souls on the ground, open vaults, the bosses of the timeline
	(when the build can take them; THE FINAL ONE always) and the 67 RUSH zone, stays out of the
	sealed rift, stays inside THE FINAL ONE's sealed arena, dashes out of circles.
	Cards: evolution > weapon level > new weapon > item levels > damage/speed upgrades > rest.
]]

local Harness = require("./harness")
local ArenaData = Harness.Require("ReplicatedStorage.Modules.ArenaData")

local Bot = {}

local HALF = 240

-- how close enemies may come: a player with only close-range weapons lets them into the aura
local function engageDistance(run): number
	local reach = 0
	for _, w in run.Weapons do
		local kind = w.Def.Kind
		if kind == "Aura" or kind == "FireRing" or kind == "Field" or kind == "Slam" or kind == "Blast67" or kind == "Slash" then
			reach = math.max(reach, (w.S.Radius or 6) * 0.7)
		elseif kind == "Orbit" then
			reach = math.max(reach, (w.S.Orbit or 6) * 0.9)
		else
			return 18
		end
	end
	return math.clamp(reach, 5, 18)
end

function Bot.Direction(run, skill: number?): (number, number)
	skill = skill or 1
	local px, pz = run.PX, run.PZ
	local mx, mz = 0, 0
	local engage = engageDistance(run)

	for _, e in run.Enemies do
		if not (e.NoContact or e.Dormant) or e.Lit then
			local dx, dz = px - e.X, pz - e.Z
			local d2 = dx * dx + dz * dz
			local r = engage + e.Radius * (if e.IsBoss then 3 else 1)
			if d2 < r * r then
				local d = math.sqrt(d2) + 0.01
				local w = (r - d) / r
				w = w * w * (if e.IsBoss then 5 else 1)
				mx += dx / d * w
				mz += dz / d * w
			end
		end
	end
	mx *= skill
	mz *= skill

	-- targets worth walking to
	local best, bestScore = nil, 0
	local hurt = run.HP < run.Stats.MaxHP * 0.5
	local function consider(x, z, value)
		local dx, dz = x - px, z - pz
		local d = math.sqrt(dx * dx + dz * dz) + 1
		local score = value / d
		if score > bestScore then
			best, bestScore = { dx / d, dz / d }, score
		end
	end
	for _, g in run.Gems do
		consider(g.X, g.Z, 1 + g.Value * 0.2)
	end
	for _, it in run.Drops do
		local v = if it.Kind == "Chest" or it.Kind == "Chest67" then 30
			elseif it.Kind == "Snack" then (if hurt then 25 else 2)
			elseif it.Kind == "Magnet" then 12
			elseif it.Kind == "Fragment" then 10
			else 4
		consider(it.X, it.Z, v)
	end
	-- 67 TOWN: relics on the ground, an open vault, a mini-boss worth hunting, the 67 RUSH
	for _, l in run.Loot or {} do
		consider(l.X, l.Z, 45)
	end
	local m = run.Map
	if m then
		local healthy = run.HP >= run.Stats.MaxHP * 0.55
		-- a careful player: dangerous zones wait until the build can take them
		local function brave(zoneKey: string): boolean
			return healthy and ArenaData.ByKey[zoneKey].Stars * 7 <= run.Level
		end
		for i, v in m.Vaults do
			local def = ArenaData.Vaults[i]
			if v.State == 1 and brave(def.Zone) then
				consider(def.X, def.Z, 26)
			end
		end
		for _, enc in m.Encounters do
			if enc.Main or (run.Level >= 6 and brave(enc.Zone)) then
				local x, z = enc.X, enc.Z
				for _, body in enc.Bodies do
					if body.Alive then
						x, z = body.X, body.Z
					end
				end
				consider(x, z, if enc.Main then 400 else 45)
			end
		end
		if m.Hot and brave(m.Hot.Zone) then
			local r = ArenaData.ByKey[m.Hot.Zone].Rect
			consider((r.MinX + r.MaxX) / 2, (r.MinZ + r.MaxZ) / 2, 5)
		end
	end
	for _, e in run.Enemies do
		if e.Key == "Crate" or e.Key == "Goblin67" or e.Key == "CoinStack" then
			consider(e.X, e.Z, 10)
		end
	end
	if best then
		local pull = if (mx * mx + mz * mz) > 0.5 then 0.35 else 0.9
		mx += best[1] * pull
		mz += best[2] * pull
	end
	-- badly hurt away from the square: fall back towards the centre (calmer, crates and snacks)
	if run.HP < run.Stats.MaxHP * 0.35 and not (m and m.ArenaSealed) then
		local d = math.sqrt(px * px + pz * pz)
		if d > 60 then
			mx -= px / d * 0.8
			mz -= pz / d * 0.8
		end
	end

	-- telegraphs: get out
	local function flee(x, z, r)
		local dx, dz = px - x, pz - z
		local d = math.sqrt(dx * dx + dz * dz) + 0.01
		if d < r + 3 then
			mx += dx / d * 4 * skill
			mz += dz / d * 4 * skill
		end
	end
	local function sidestep(x, z, a, len, width)
		local ux, uz = math.cos(a), math.sin(a)
		local rx, rz = px - x, pz - z
		local along = rx * ux + rz * uz
		if along > -2 and along < len + 2 then
			local side = rx * -uz + rz * ux
			if math.abs(side) < width / 2 + 3 then
				local sgn = if side >= 0 then 1 else -1
				mx += -uz * sgn * 4 * skill
				mz += ux * sgn * 4 * skill
			end
		end
	end
	-- a sector (THE FURNACE, ROULETTE, THE SCARECROW): leave it sideways, over its nearer edge
	local function leaveSector(x, z, a, half, r)
		local dx, dz = px - x, pz - z
		local d = math.sqrt(dx * dx + dz * dz) + 0.01
		if d > r + 2 then
			return
		end
		local diff = ((math.atan2(dz, dx) - a + math.pi) % (2 * math.pi)) - math.pi
		if math.abs(diff) > half + 2 / d then
			return
		end
		local sgn = if diff >= 0 then 1 else -1
		mx += -dz / d * sgn * 4 * skill
		mz += dx / d * sgn * 4 * skill
	end
	for _, t in run.Telegraphs do
		if t.Safe then
			-- COLLAPSE: walk into the nearest safe circle
			local best, bx, bz = math.huge, nil, nil
			for _, hole in t.Safe do
				local d2 = (hole.X - px) ^ 2 + (hole.Z - pz) ^ 2
				if d2 < best then
					best, bx, bz = d2, hole.X, hole.Z
				end
			end
			if bx and best > 1 then
				local d = math.sqrt(best)
				mx += (bx - px) / d * 6 * skill
				mz += (bz - pz) / d * 6 * skill
			end
		elseif t.Shape == 1 or t.Shape == 3 or t.Shape == 5 or t.Shape == 6 or t.Shape == 9 then
			flee(t.X, t.Z, t.R)
		elseif t.Shape == 4 then
			sidestep(t.X, t.Z, t.Angle, t.R, t.Width)
		elseif t.Shape == 7 then
			leaveSector(t.X, t.Z, t.Angle, t.Width, t.R)
		end
	end
	-- the sealed rift: stay out (the gates are closed for real players)
	if run.Map and not run.Map.RiftOpen then
		local r = ArenaData.ByKey.Rift.Rect
		if px < r.MaxX + 6 and pz < r.MaxZ + 6 then
			mz += 2
		end
	end
	for _, h in run.Hazards do
		if h.Sector then
			leaveSector(h.X, h.Z, h.Sector, h.Half, h.R)
		elseif h.Damage > 0 or h.Slow then
			flee(h.X, h.Z, h.R)
		end
	end
	for _, e in run.Enemies do
		if e.Lit then
			flee(e.X, e.Z, e.Def.Params.BlastRadius)
		elseif e.Behavior == "Leap" and e.State == 1 and e.TX then
			flee(e.TX, e.TZ, e.Def.Params.LandRadius)
		elseif e.Behavior == "Sniper" and e.State == 1 then
			sidestep(e.X, e.Z, math.atan2(e.DirZ, e.DirX), 80, 2)
		end
	end
	-- boss dashing towards us: sidestep
	local boss = run.Boss
	if boss and (boss.DashAt or boss.Dashing) then
		mx += -boss.DirZ * 2 * skill
		mz += boss.DirX * 2 * skill
	end
	-- a mini-boss charge line (CARTZILLA): step off it
	for _, t in run.Telegraphs do
		if t.Shape == 2 then
			sidestep(t.X, t.Z, t.Angle, t.R, t.Width)
		end
	end
	-- enemy projectiles coming at us: sidestep
	for _, p in run.EnemyProjectiles do
		local dx, dz = px - p.X, pz - p.Z
		local d2 = dx * dx + dz * dz
		if d2 < 12 * 12 and (dx * p.VX + dz * p.VZ) > 0 then
			local len = math.sqrt(p.VX * p.VX + p.VZ * p.VZ) + 0.01
			mx += -p.VZ / len * 1.5 * skill
			mz += p.VX / len * 1.5 * skill
		end
	end

	-- ponds slow you down: steer around them like a player would
	local water = run.Colliders and run.Colliders.Water
	if water then
		for _, w in water do
			local dx, dz = px - w.X, pz - w.Z
			local d = math.sqrt(dx * dx + dz * dz) + 0.01
			local edge = w.R + 6
			if d < edge then
				local push = (edge - d) / edge * 2.5
				mx += dx / d * push
				mz += dz / d * push
			end
		end
	end

	-- walls
	local margin = HALF - 40
	if px > margin then
		mx -= (px - margin) / 20
	elseif px < -margin then
		mx += (-margin - px) / 20
	end
	if pz > margin then
		mz -= (pz - margin) / 20
	elseif pz < -margin then
		mz += (-margin - pz) / 20
	end

	-- THE FINAL ONE's sealed arena: stay inside the ring and circle around the boss
	local seal = run.Map and run.Map.ArenaSealed
	if seal then
		for _, e in run.Enemies do
			if e.Encounter and e.Encounter.Main and e.Alive then
				local bx, bz = px - e.X, pz - e.Z
				local bd = math.sqrt(bx * bx + bz * bz) + 0.01
				if bd < e.Radius + 16 then
					-- sideways (the way that heads back towards the centre of the ring)
					local tx, tz = -bz / bd, bx / bd
					local cx, cz = seal.X - px, seal.Z - pz
					if tx * cx + tz * cz < 0 then
						tx, tz = -tx, -tz
					end
					mx += tx * 3 * skill
					mz += tz * 3 * skill
				end
			end
		end
		local ax, az = px - seal.X, pz - seal.Z
		local ad = math.sqrt(ax * ax + az * az) + 0.01
		if ad > seal.R - 6 then
			local k = (ad - (seal.R - 6)) / 4
			mx -= ax / ad * k * 3
			mz -= az / ad * k * 3
		end
	end

	local len = math.sqrt(mx * mx + mz * mz)
	if len < 0.05 then
		return 0, 0
	end
	return mx / len, mz / len
end

local PASSIVE_PRIORITY = {
	Power = 5, RapidFire = 5, Expansion = 4, DoubleShot = 6, Vitality = 3, Armor = 3, Swiftness = 2, Regeneration = 3,
	CritMaster = 4, Percent67 = 6, Berserk = 3, Brutal = 3, GiantSlayer = 4, Plating = 3, ToughSkin = 3, Penetration = 4,
	Ricochet = 4, Split = 3, Momentum = 3, Execution = 3, Vampire = 3, Homing = 3, Explosive = 4, ChainShot = 3,
	BigShots = 3, Dodge = 3, LastStand = 3, Combo = 3, Rampage = 3, Bully = 3,
}

function Bot.Pick(run): number
	local offer = run.Offer
	local best, bestScore = 1, -1
	for i, card in offer.Cards do
		local score = 1
		if card.Type == "Evolution" then
			score = 30
		elseif card.Type == "WeaponLevel" then
			score = 10 + (card.Level or 0) * 0.1
		elseif card.Type == "Weapon" then
			score = if #run.Weapons < 6 then 12 else 3
		elseif card.Type == "ItemLevel" then
			score = 11
		elseif card.Type == "Passive" then
			score = (PASSIVE_PRIORITY[card.Key] or 1) + (if card.Evolves then 4 else 0)
			-- a fragile build takes some defence (any DEFENSE upgrade: HP, armour, plating, regen...)
			if card.Category == "DEFENSE" and run.Stats.MaxHP < 100 + run.Level * 3 then
				score = if card.Key == "Vitality" or card.Key == "Armor" or card.Key == "Regeneration" then 9 else 7
			end
		end
		if score > bestScore then
			best, bestScore = i, score
		end
	end
	return best
end

-- advances a run by one step with the bot playing
function Bot.Step(run, dt: number, skill: number?)
	if run.Offer then
		run:Choose(Bot.Pick(run))
	end
	local dx, dz = Bot.Direction(run, skill)
	-- Rocket Skates: dash out of a telegraph we are standing in
	local dash = run.DashState
	if dash and dash.Charges > 0 and (dx ~= 0 or dz ~= 0) then
		for _, t in run.Telegraphs do
			if t.Shape == 1 and (run.PX - t.X) ^ 2 + (run.PZ - t.Z) ^ 2 < t.R * t.R and t.At - run.Time < 0.4 then
				run:Dash(dx, dz)
				break
			end
		end
	end
	local speed = run.Stats.WalkSpeed * run:SpeedFactor()
	run:SetPlayer(run.PX + dx * speed * dt, run.PZ + dz * speed * dt, dx, dz)
	run:Step(dt)
end

return Bot
