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
}

local Stats = {}

-- keys a bonus source may contain
Stats.Keys = {
	"Might", "AttackSpeed", "Cooldown", "Area", "Amount", "MoveSpeed", "Growth", "Crit", "CritMult",
	"Magnet", "MaxHP", "MaxHPMult", "Regen", "Armor", "Luck", "Greed", "ProjSpeed", "Duration",
	"Revives", "Rerolls", "ExtraWeapons", "WeaponSlots",
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
		Regen = math.max(0, s.Regen),
		Armor = math.max(0, s.Armor),
		Luck = math.max(0.1, 1 + s.Luck),
		Greed = math.max(0, 1 + s.Greed),
		ProjSpeed = math.max(0.3, 1 + s.ProjSpeed),
		Duration = math.max(0.3, 1 + s.Duration),
		Revives = math.max(0, math.floor(s.Revives)),
		Rerolls = math.max(0, math.floor(s.Rerolls)),
		ExtraWeapons = math.max(0, math.floor(s.ExtraWeapons)),
		WeaponSlots = GameConfig.Player.MaxWeapons + math.max(0, math.floor(s.WeaponSlots)),
	}
end

--[[
	Final stats of one weapon for a player. Returns a new table:
	Damage, Cooldown, Amount, Radius, Speed, Duration, Pierce, Knockback, Range, HitCooldown,
	Orbit, Length, Chain, Percent, Slow (whatever the weapon uses).
]]
function Stats.Weapon(key: string, level: number, awakened: boolean, final: Final): { [string]: number }
	local def = WeaponData.Get(key)
	local w = WeaponData.RawStats(key, level)
	local awaken = WeaponData.Awaken
	w.Damage = (w.Damage or 0) * final.Might * (if awakened then awaken.Damage else 1)
	w.Cooldown = math.max(0.12, (w.Cooldown or 1) * final.CooldownMult)
	if not def.NoAmount then
		w.Amount = math.max(1, math.floor((w.Amount or 1) + final.Amount + (if awakened then awaken.Amount else 0)))
	else
		w.Amount = 1
	end
	local area = final.Area * (if awakened then awaken.Radius else 1)
	if w.Radius then
		w.Radius *= area
	end
	if w.Orbit then
		w.Orbit *= area
	end
	if w.Length then
		w.Length *= area
	end
	if w.Speed and def.Kind ~= "Orbit" then
		w.Speed *= final.ProjSpeed
	elseif w.Speed then
		w.Speed *= math.min(2.5, 1 / final.CooldownMult) -- orbit spins faster with attack speed
	end
	if w.Duration then
		w.Duration *= final.Duration
	end
	return w
end

return Stats
