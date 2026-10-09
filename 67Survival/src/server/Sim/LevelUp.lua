--[[
	LevelUp - builds the 3 random cards of a LEVEL UP (or a chest) and applies the one the
	player picks. The client only ever sends an index into the current offer; everything
	else is decided and validated here.

	Card types
	  Weapon       a new ability                  WeaponLevel  the next level of an ability
	  Passive      a level-up upgrade (new or its next level, shared/UpgradeData)
	  Evolution    an ability's Mythic form       ItemLevel    rare: +1 level of an item you carry
	  Filler       a snack / coins when nothing else can be offered

	Every card says what changes: Level (the level it brings) / Current / MaxLevel, Change
	(the short change: "+1 bolt"), Mechanic (a NEW behaviour this level unlocks), Category
	(OFFENSE, PROJECTILES, DEFENSE, MOVEMENT, XP, ABILITY, ITEM), Synergy ("BULLET HELL 3/4":
	the build it moves forward, shared/SynergyData).
	No impossible cards: upgrades with Requires (a projectile ability, a dash) only show up
	when they can do something; maxed things never do.

	Weights: every ability / upgrade / item has a Rarity (shared/Rarity.lua); Luck makes the
	rare tiers more likely. An EVOLUTION that is ready always takes the first slot.
	PREMIUM abilities (Robux, run.Unlocked only when owned) weigh AbilityConfig.PremiumWeight;
	the first LEVEL UP of a run shows one of them (an owner always gets to pick it once).
	Offers: Level (3 cards), Chest (3, THE LUCKY +1), Chest67 (4, luck boosted a lot).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local WeaponData = require(Shared.WeaponData)
local UpgradeData = require(Shared.UpgradeData)
local ItemData = require(Shared.ItemData)
local SynergyData = require(Shared.SynergyData)
local Rarity = require(Shared.Rarity)
local AbilityConfig = require(Shared.AbilityConfig)

local Perks = require(script.Parent.Perks)
local Items = require(script.Parent.Items)

local LevelUp = {}

export type Card = {
	Id: string,
	Type: string,
	Key: string,
	Title: string,
	Desc: string,
	Change: string?,
	Mechanic: string?,
	Rarity: string,
	Category: string?,
	Symbol: string?,
	Level: number?,
	Current: number?,
	MaxLevel: number?,
	New: boolean?,
	Evolves: string?, -- this pick completes an evolution recipe
	Synergy: string?, -- "BULLET HELL 3/4"
	Premium: boolean?, -- a premium (Robux / trial) ability
}

local PROJECTILE_KINDS = { Projectile = true, Missile = true, Boomerang = true, Swords = true, Drone = true, Lob = true }

local function passiveCount(run): number
	local n = 0
	for _ in run.Passives do
		n += 1
	end
	return n
end

-- the build after a pick, for synergy tags ("tag" as SynergyData.Of: "Upgrade:Key" ...)
local function synergyTag(run, tag: string, key: string, kind: string): string?
	if not SynergyData.Of[tag] then
		return nil
	end
	local before = Perks.Build(run)
	local after = {
		Upgrades = table.clone(before.Upgrades),
		Items = table.clone(before.Items),
		Abilities = table.clone(before.Abilities),
		Dash = before.Dash,
	}
	if kind == "Upgrade" then
		after.Upgrades[key] = (after.Upgrades[key] or 0) + 1
	elseif kind == "Item" then
		after.Items[key] = (after.Items[key] or 0) + 1
	else
		after.Abilities[key] = true
	end
	local syn, have, total = SynergyData.BestFor(tag, after)
	if not syn then
		return nil
	end
	local had = SynergyData.Progress(syn, before)
	if have <= had or have < 2 then
		return nil -- it does not move a synergy forward (yet)
	end
	return if have >= total then syn.Name .. " READY" else string.format("%s %d/%d", syn.Name, have, total)
end

local function weaponCard(run, def, level: number): Card
	local isNew = level == 1
	local delta = def.Levels[level]
	return {
		Id = (if isNew then "W:" else "L:") .. def.Key,
		Type = if isNew then "Weapon" else "WeaponLevel",
		Key = def.Key,
		Title = def.Name,
		Desc = def.Desc,
		Change = if isNew then def.Desc else (delta and delta.Desc or "Stronger"),
		Mechanic = if not isNew and delta and delta.New then delta.Desc else nil,
		Rarity = def.Rarity,
		Category = def.Category,
		Level = level,
		Current = level - 1,
		MaxLevel = def.MaxLevel,
		New = isNew,
		Premium = def.Premium,
		Synergy = if isNew then synergyTag(run, "Ability:" .. def.Key, def.Key, "Ability") else nil,
	}
end

local function evolutionCard(run, baseKey: string): Card
	local evo = WeaponData.EvolutionOf[baseKey]
	local base = WeaponData.Get(baseKey)
	local with = UpgradeData.PassiveByKey[evo.Evolution.With]
	return {
		Id = "E:" .. evo.Key,
		Type = "Evolution",
		Key = baseKey,
		Title = evo.Name,
		Desc = evo.Desc,
		Change = evo.Desc,
		Rarity = "Mythic",
		Category = evo.Category,
		Evolves = base.Name .. " + " .. (if with then with.Name else evo.Evolution.With),
	}
end

-- which passive completes an evolution of an owned ability (hint on the card)
local function evolvesWith(run, passiveKey: string): string?
	for _, w in run.Weapons do
		local evo = WeaponData.EvolutionOf[w.Key]
		if evo and evo.Evolution.With == passiveKey then
			return evo.Name
		end
	end
	return nil
end

-- can this upgrade do something for this build?
local function requirementsMet(run, def): boolean
	local req = def.Requires
	if not req then
		return true
	end
	if req.Category then
		for _, w in run.Weapons do
			if w.Def.Category == req.Category or (req.Category == "PROJECTILE" and PROJECTILE_KINDS[w.Def.Kind]) then
				return true
			end
		end
		return false
	end
	if req.Dash then
		return Perks.HasDash(run)
	end
	return true
end
LevelUp.RequirementsMet = requirementsMet

local function passiveCard(run, def, level: number): Card
	local l = def.Levels[level]
	return {
		Id = "P:" .. def.Key,
		Type = "Passive",
		Key = def.Key,
		Title = def.Name,
		Desc = def.Desc,
		Change = l.Desc,
		Mechanic = l.New,
		Rarity = def.Rarity,
		Category = def.Category,
		Symbol = def.Symbol,
		Level = level,
		Current = level - 1,
		MaxLevel = def.MaxLevel,
		New = level == 1,
		Evolves = if level == 1 then evolvesWith(run, def.Key) else nil,
		Synergy = synergyTag(run, "Upgrade:" .. def.Key, def.Key, "Upgrade"),
	}
end

local function itemCard(run, def, level: number): Card
	local l = def.Levels[level]
	return {
		Id = "I:" .. def.Key,
		Type = "ItemLevel",
		Key = def.Key,
		Title = def.Name,
		Desc = def.Desc,
		Change = l.Desc,
		Mechanic = l.New,
		Rarity = def.Rarity,
		Category = "ITEM",
		Symbol = def.Symbol,
		Level = level,
		Current = level - 1,
		MaxLevel = def.MaxLevel,
		New = false,
		Synergy = synergyTag(run, "Item:" .. def.Key, def.Key, "Item"),
	}
end

-- every normal card that could be offered right now, with weights
local function candidates(run, luck: number): { { any } }
	local out = {}
	local cfg = GameConfig.LevelUp
	for _, w in run.Weapons do
		if w.Level < w.Def.MaxLevel then
			table.insert(out, { weaponCard(run, w.Def, w.Level + 1), cfg.WeaponLevelWeight })
		end
	end
	if #run.Weapons < run.Stats.WeaponSlots then
		for _, def in WeaponData.List do
			if
				run.Unlocked[def.Key]
				and def.Evolution == nil
				and not run:GetWeapon(def.Key)
				and (def.MinPlayerLevel or 0) <= run.Level
			then
				local weight = if def.Premium then AbilityConfig.PremiumWeight else Rarity.WeightFor(def.Rarity, luck)
				table.insert(out, { weaponCard(run, def, 1), cfg.NewWeaponWeight * weight })
			end
		end
	end
	local canAddPassive = passiveCount(run) < GameConfig.Player.MaxPassives
	-- new upgrades share one budget (the list is long: it must not crowd out the abilities);
	-- the next level of an upgrade you have keeps the full weight
	local fresh = {}
	for _, def in UpgradeData.Passives do
		local level = run.Passives[def.Key] or 0
		local available = def.Secret == nil or run.Unlocked[def.Key] == true
		if available and level < def.MaxLevel and (level > 0 or canAddPassive) and requirementsMet(run, def) then
			local card = passiveCard(run, def, level + 1)
			local weight = cfg.PassiveWeight * Rarity.WeightFor(def.Rarity, luck)
			if card.Evolves then
				weight *= 1.6 -- nudges players towards discovering evolutions
			end
			if card.Synergy then
				weight *= 1.3 -- ... and towards finishing a synergy
			end
			local entry = { card, weight }
			table.insert(out, entry)
			if level == 0 then
				table.insert(fresh, entry)
			end
		end
	end
	if #fresh > cfg.NewPassiveShare then
		local k = cfg.NewPassiveShare / #fresh
		for _, entry in fresh do
			entry[2] *= k
		end
	end
	-- rare: one more level of an item you carry
	if run.Level >= cfg.ItemFromLevel then
		for _, key in run.ItemOrder do
			local def = ItemData.ByKey[key]
			local level = run.Items[key] or 0
			if def and not def.Secret and level < def.MaxLevel then
				table.insert(out, { itemCard(run, def, level + 1), cfg.ItemWeight * Rarity.WeightFor(def.Rarity, luck) })
			end
		end
	end
	return out
end

local function pick(rng, list: { { any } }, taken: { [string]: boolean }): Card?
	local total = 0
	for _, entry in list do
		if not taken[entry[1].Id] then
			total += entry[2]
		end
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber(0, total)
	for _, entry in list do
		if not taken[entry[1].Id] then
			r -= entry[2]
			if r <= 0 then
				return entry[1]
			end
		end
	end
	return nil
end

function LevelUp.Build(run, kind: string): { Card }
	local rng = run.Rng
	local count = GameConfig.LevelUp.Choices
	local luck = run.Stats.Luck
	if kind == "Chest" and run.Mech == "Jackpot" then
		count += 1
	elseif kind == "Chest67" then
		count += 1
		luck += 5
	end
	local pool = candidates(run, luck)
	local taken = {}
	local cards = {}

	-- a ready evolution always shows up first
	local ready = run:EvolutionsReady()
	if #ready > 0 then
		local card = evolutionCard(run, ready[rng:NextInteger(1, #ready)])
		taken[card.Id] = true
		table.insert(cards, card)
	end
	-- SECRET 67 promised the 67% card
	if run.Bonus67 and not run.Passives.Percent67 then
		run.Bonus67 = false
		for _, entry in pool do
			if entry[1].Key == "Percent67" and #cards < count then
				taken[entry[1].Id] = true
				table.insert(cards, entry[1])
			end
		end
	end
	-- an owned premium ability shows up in the first level up of the run
	if kind == "Level" and not run.PremiumOffered and #cards < count then
		local premium = {}
		for _, entry in pool do
			local def = entry[1].Type == "Weapon" and WeaponData.ByKey[entry[1].Key]
			if def and def.Premium then
				table.insert(premium, entry[1])
			end
		end
		if #premium > 0 then
			run.PremiumOffered = true
			local card = premium[rng:NextInteger(1, #premium)]
			taken[card.Id] = true
			table.insert(cards, card)
		end
	end
	for slot = #cards + 1, count do
		local card = pick(rng, pool, taken)
		if not card then
			local fill = UpgradeData.Fillers[(slot - 1) % #UpgradeData.Fillers + 1]
			card = { Id = "F:" .. fill.Key, Type = "Filler", Key = fill.Key, Title = fill.Name, Desc = fill.Desc, Change = fill.Desc, Rarity = "Common" }
		end
		if not taken[card.Id] then
			taken[card.Id] = true
			table.insert(cards, card)
		end
	end
	return cards
end

local function sendOffer(run)
	local offer = run.Offer
	run:Event("Offer", {
		Kind = offer.Kind,
		Level = run.Level,
		Cards = offer.Cards,
		Rerolls = run.Rerolls,
	})
end

function LevelUp.Open(run, kind: string)
	run.Offer = { Kind = kind, Cards = LevelUp.Build(run, kind) }
	run.PausedFor = 0
	sendOffer(run)
end

function LevelUp.OpenNext(run)
	if (run.PendingChests67 or 0) > 0 then
		run.PendingChests67 -= 1
		LevelUp.Open(run, "Chest67")
	elseif run.PendingChests > 0 then
		run.PendingChests -= 1
		LevelUp.Open(run, "Chest")
	elseif run.PendingLevels > 0 then
		LevelUp.Open(run, "Level")
	end
end

function LevelUp.Apply(run, card: Card)
	local t = card.Type
	if t == "Weapon" then
		run:AddWeapon(card.Key)
	elseif t == "WeaponLevel" then
		local w = run:GetWeapon(card.Key)
		if w and w.Level < w.Def.MaxLevel then
			w.Level += 1
		end
	elseif t == "Passive" then
		local key = card.Key
		local def = UpgradeData.PassiveByKey[key]
		if not def or (run.Passives[key] or 0) >= def.MaxLevel then
			return
		end
		if not run.Passives[key] then
			table.insert(run.PassiveOrder, key)
		end
		run.Passives[key] = (run.Passives[key] or 0) + 1
		run.Result.Picked[key] = true
		if key == "Percent67" then
			-- "Something is coming...": a 67% EVENT within 6.7 seconds
			local w = run.Wave
			w.Force67 = true
			w.NextEventAt = math.min(w.NextEventAt, run.Time + 6.7)
		end
	elseif t == "Evolution" then
		run:Evolve(card.Key)
	elseif t == "ItemLevel" then
		Items.Gain(run, card.Key)
	elseif t == "Filler" then
		if card.Key == "Snack" then
			run:Heal(30)
		else
			run:AddCoins(8)
		end
	end
	if (Rarity.Index[card.Rarity] or 1) >= Rarity.Index.Rare then
		run.Result.Rares += 1
	end
	run:RefreshStats()
	run:SendLoadout()
	run:CheckEvolutions()
end

local function close(run, skipped: boolean)
	local offer = run.Offer
	run.Offer = nil
	if offer.Kind == "Level" then
		run.PendingLevels = math.max(0, run.PendingLevels - 1)
	end
	run:Event("OfferClosed", { Skipped = skipped })
	LevelUp.OpenNext(run)
end

function LevelUp.Choose(run, index: number): boolean
	local offer = run.Offer
	if not offer or type(index) ~= "number" or index ~= math.floor(index) then
		return false
	end
	local card = offer.Cards[index]
	if not card then
		return false
	end
	LevelUp.Apply(run, card)
	run:Event("Picked", { Id = card.Id, Type = card.Type, Rarity = card.Rarity, Title = card.Title, Key = card.Key })
	close(run, false)
	return true
end

function LevelUp.Reroll(run): boolean
	if not run.Offer or run.Rerolls <= 0 then
		return false
	end
	run.Rerolls -= 1
	run.Offer.Cards = LevelUp.Build(run, run.Offer.Kind)
	sendOffer(run)
	return true
end

function LevelUp.Skip(run): boolean
	if not run.Offer then
		return false
	end
	run:AddCoins(GameConfig.LevelUp.SkipCoins)
	close(run, true)
	return true
end

return LevelUp
