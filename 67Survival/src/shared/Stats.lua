--[[
	Stats - turns bonus sources (character, permanent upgrades, run passives, buffs) into the
	final numbers the simulation uses. Pure functions, shared by server and client (the
	UI shows the same numbers the server uses).

	Every source is a table of additive bonuses by stat key, e.g. { Might = 0.15, Armor = 1 }.
]]

local GameConfig = require(script.Parent.GameConfig)
local WeaponData = require(script.Parent.WeaponData)

export type Final = {
	Might: number,
	CooldownMult: number,
	Area: number,
	Amount: number,
	MoveSpeed: number,
	WalkSpeed: number,
	Growth: number,
	Crit: number,
	CritMult: number,
	PickupRange: number,
	MaxHP: number,
	Regen: number,
	Armor: number,
	Luck: number,
	Greed: number,
	ProjSpeed: number,
	Duration: number,
	Revives: number,
	Rerolls: number,
	ExtraWeapons: number,
	WeaponSlots: number,
	Range: number,
	Burn: number,
	Orbital: number,
	Lifesteal: number,
	Berserk: number,
	Execute: number,
}

local Stats = {}

-- keys a bonus source may contain
Stats.Keys = {
	"Might", "AttackSpeed", "Cooldown", "Area", "Amount", "MoveSpeed", "Growth", "Crit", "CritMult",
	"Magnet", "MaxHP", "MaxHPMult", "Regen", "Armor", "Luck", "Greed", "ProjSpeed", "Duration",
	"Revives", "Rerolls", "ExtraWeapons", "WeaponSlots", "Range", "Burn", "Orbital", "Lifesteal",
	"Berserk", "Execute",
}
local KNOWN = {}
for _, k in Stats.Keys do
	KNOWN[k] = true
end
Stats.Known = KNOWN

local function finite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

function Stats.Sum(sources: { { [string]: number } }): { [string]: number }
	local sum = {}
	for _, key in Stats.Keys do
		sum[key] = 0
	end
	for _, source in sources do
		for key, value in source do
			if KNOWN[key] and type(value) == "number" and finite(value) then
				sum[key] += value
			end
		end
	end
	return sum
end

function Stats.Compute(sources: { { [string]: number } }): Final
	local s = Stats.Sum(sources)
	local P = GameConfig.Player
	local moveSpeed = math.max(0.5, 1 + s.MoveSpeed)
	local attackSpeed = math.max(0.3, 1 + s.AttackSpeed)
	return {
		Might = math.max(0.1, 1 + s.Might),
		CooldownMult = math.clamp((1 / attackSpeed) * (1 - math.clamp(s.Cooldown, 0, 0.6)), 0.2, 3),
		Area = math.max(0.3, 1 + s.Area),
		Amount = math.max(0, math.floor(s.Amount + 0.5)),
		MoveSpeed = moveSpeed,
		WalkSpeed = math.min(P.MaxWalkSpeed, P.BaseWalkSpeed * moveSpeed),
		Growth = math.max(0.1, 1 + s.Growth),
		Crit = math.clamp(s.Crit, 0, 1),
		CritMult = 2 + s.CritMult,
		PickupRange = P.PickupRange * math.max(0.5, 1 + s.Magnet),
		MaxHP = math.max(10, math.floor((P.BaseHP + s.MaxHP) * math.max(0.2, 1 + s.MaxHPMult) + 0.5)),
		Regen = math.max(0, (P.BaseRegen or 0) + s.Regen),
		Armor = math.max(0, s.Armor),
		Luck = math.max(0.1, 1 + s.Luck),
		Greed = math.max(0, 1 + s.Greed),
		ProjSpeed = math.max(0.3, 1 + s.ProjSpeed),
		Duration = math.max(0.3, 1 + s.Duration),
		Revives = math.max(0, math.floor(s.Revives)),
		Rerolls = math.max(0, math.floor(s.Rerolls)),
		ExtraWeapons = math.max(0, math.floor(s.ExtraWeapons)),
		WeaponSlots = GameConfig.Player.MaxWeapons + math.max(0, math.floor(s.WeaponSlots)),
		Range = math.max(0.5, 1 + s.Range),
		Burn = math.max(0.2, 1 + s.Burn),
		Orbital = math.max(0.5, 1 + s.Orbital),
		Lifesteal = math.clamp(s.Lifesteal, 0, 0.6),
		Berserk = math.clamp(s.Berserk, 0, 1.5),
		Execute = math.clamp(s.Execute, 0, 0.3),
	}
end

--[[
	Final stats of one weapon for a player. Returns a new table:
	Damage, Cooldown, Amount, Radius, Speed, Duration, Pierce, Knockback, Range, HitCooldown,
	Orbit, Length, Chain, Slow, Burn, Arc, Pull... (whatever the ability uses).
]]
function Stats.Weapon(key: string, level: number, final: Final): { [string]: number }
	local def = WeaponData.Get(key)
	local w = WeaponData.RawStats(key, level)
	w.Damage = (w.Damage or 0) * final.Might
	w.Cooldown = math.max(0.12, (w.Cooldown or 1) * final.CooldownMult)
	if not def.NoAmount then
		w.Amount = math.max(1, math.floor((w.Amount or 1) + final.Amount))
	else
		w.Amount = 1
	end
	local area = final.Area
	local ring = def.Kind == "Orbit" or def.Kind == "Crown" -- (the Aura Crown turns like an orbit)
	local orbital = if ring then final.Orbital else 1
	if w.Radius then
		w.Radius *= area
	end
	if w.Orbit then
		w.Orbit *= area * orbital
	end
	if w.Length then
		w.Length *= area
	end
	if w.Blast then
		w.Blast *= area
	end
	if w.Explode then
		w.Explode *= area
	end
	if w.Range then
		w.Range *= final.Range
	end
	if w.Speed and ring then
		w.Speed *= math.min(2.5, 1 / final.CooldownMult) * orbital -- orbit spins faster with attack speed
	elseif w.Speed and def.Kind ~= "Allies" then
		w.Speed *= final.ProjSpeed
	end
	if w.Duration then
		w.Duration *= final.Duration
		if def.Kind == "Projectile" or def.Kind == "Swords" then
			w.Duration *= final.Range -- straight shots fly further with range
		end
	end
	if w.Burn then
		w.Burn *= final.Burn * final.Might
		w.BurnTime = (w.BurnTime or 2) * final.Duration * (1 + (final.Burn - 1) * 0.5)
	end
	return w
end

return Stats
