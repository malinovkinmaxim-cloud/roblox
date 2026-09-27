--!nocheck
--[[
	Bot - a simple survivor player for headless playtests.

	Movement: runs away from nearby enemies (bosses count more), steps out of boss
	telegraphs, dodges enemy projectiles, collects gems and pickups, chases loot crates
	and runaway goblins, stays away from the arena walls.
	Cards: rare > weapon level > new weapon > damage/speed passives > the rest.
]]

local Bot = {}

local HALF = 240

-- how close enemies may come: a player with only close-range weapons lets them into the aura
local function engageDistance(run): number
	local reach = 0
	for _, w in run.Weapons do
		local kind = w.Def.Kind
		if kind == "Aura" or kind == "FinalAura" or kind == "Slam" or kind == "Blast67" then
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
		if not e.NoContact then
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
		local v = if it.Kind == "Chest" then 30 elseif it.Kind == "Pizza" then (if hurt then 25 else 2) elseif it.Kind == "Magnet" then 12 else 4
		consider(it.X, it.Z, v)
	end
	for _, e in run.Enemies do
		if e.Key == "Crate" or e.Key == "Goblin67" or e.Key == "Runner" then
			consider(e.X, e.Z, 10)
		end
	end
	if best then
		local pull = if (mx * mx + mz * mz) > 0.5 then 0.35 else 0.9
		mx += best[1] * pull
		mz += best[2] * pull
	end

	-- boss telegraphs: get out
	for _, t in run.Telegraphs do
		if t.Shape == 1 then
			local dx, dz = px - t.X, pz - t.Z
			local d = math.sqrt(dx * dx + dz * dz) + 0.01
			if d < t.R + 3 then
				mx += dx / d * 4 * skill
				mz += dz / d * 4 * skill
			end
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

local PASSIVE_PRIORITY = { Might = 5, AttackSpeed = 5, Area = 4, Amount = 6, MaxHP = 3, Cooldown = 4, MoveSpeed = 2, Regen = 2, Armor = 3 }

function Bot.Pick(run): number
	local offer = run.Offer
	local best, bestScore = 1, -1
	for i, card in offer.Cards do
		local score = 1
		if card.Type == "Rare" then
			score = 20
		elseif card.Type == "WeaponLevel" then
			score = 10 + (card.Level or 0) * 0.1
		elseif card.Type == "Weapon" then
			score = if #run.Weapons < 6 then 12 else 3
		elseif card.Type == "Passive" then
			score = PASSIVE_PRIORITY[card.Key] or 1
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
