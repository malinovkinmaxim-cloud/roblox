--!nocheck
--[[
	Bot - a simple survivor player for headless playtests.

	Movement: runs away from nearby enemies (bosses count more), steps out of telegraphs
	(boss circles, laser lines, void zones, lit bombers, leaper landings, sniper lines),
	dodges enemy projectiles, collects gems and pickups, chases loot crates and runaway
	goblins, stays away from the arena walls.
	Cards: evolution > weapon level > new weapon > damage/speed passives > the rest.
]]

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
	for _, it in run.Items do
		local v = if it.Kind == "Chest" or it.Kind == "Chest67" then 30
			elseif it.Kind == "Snack" then (if hurt then 25 else 2)
			elseif it.Kind == "Magnet" then 12
			elseif it.Kind == "Fragment" then 10
			else 4
		consider(it.X, it.Z, v)
	end
	for _, e in run.Enemies do
		if e.Key == "Crate" or e.Key == "Goblin67" then
			consider(e.X, e.Z, 10)
		end
	end
	if best then
		local pull = if (mx * mx + mz * mz) > 0.5 then 0.35 else 0.9
		mx += best[1] * pull
		mz += best[2] * pull
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
	for _, t in run.Telegraphs do
		if t.Shape == 1 or t.Shape == 3 then
			flee(t.X, t.Z, t.R)
		elseif t.Shape == 4 then
			sidestep(t.X, t.Z, t.Angle, t.R, t.Width)
		end
	end
	for _, h in run.Hazards do
		flee(h.X, h.Z, h.R)
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

	local len = math.sqrt(mx * mx + mz * mz)
	if len < 0.05 then
		return 0, 0
	end
	return mx / len, mz / len
end

local PASSIVE_PRIORITY = { Power = 5, RapidFire = 5, Expansion = 4, DoubleShot = 6, Vitality = 3, Armor = 3, Swiftness = 2, Regeneration = 2, CritMaster = 4, Percent67 = 6, Berserk = 3 }

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
		elseif card.Type == "Passive" then
			score = (PASSIVE_PRIORITY[card.Key] or 1) + (if card.Evolves then 4 else 0)
			-- a fragile build takes some defence
			if (card.Key == "Vitality" or card.Key == "Armor") and run.Stats.MaxHP < 100 + run.Level * 3 then
				score = 9
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
	local speed = run.Stats.WalkSpeed
	run:SetPlayer(run.PX + dx * speed * dt, run.PZ + dz * speed * dt, dx, dz)
	run:Step(dt)
end

return Bot
