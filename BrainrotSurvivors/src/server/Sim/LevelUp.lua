--[[
	LevelUp - builds the random cards of a LEVEL UP (or a boss / goblin chest) and applies
	the one the player picks. The client only ever sends an index into the current offer;
	everything else is decided and validated here.

	Card types: Weapon (new), WeaponLevel, Passive, Rare, Filler
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local WeaponData = require(Shared.WeaponData)
local UpgradeData = require(Shared.UpgradeData)

local LevelUp = {}

local RARITY_WEIGHT = { Common = 1, Rare = 0.5, Legendary = 0.3 }

export type Card = {
	Id: string,
	Type: string,
	Key: string,
	Title: string,
	Desc: string,
	Icon: string,
	Rarity: string,
	Level: number?,
	New: boolean?,
}

local function passiveCount(run): number
	local n = 0
	for _ in run.Passives do
		n += 1
	end
	return n
end

local function weaponCard(run, def, level: number): Card
	local isNew = level == 1
	return {
		Id = (if isNew then "W:" else "L:") .. def.Key,
		Type = if isNew then "Weapon" else "WeaponLevel",
		Key = def.Key,
		Title = def.Name,
		Desc = if isNew then def.Desc else (def.Levels[level] and def.Levels[level].Desc or "Stronger"),
		Icon = def.Icon,
		Rarity = def.Rarity,
		Level = level,
		New = isNew,
	}
end

-- every normal card that could be offered right now, with weights
local function candidates(run): { { any } }
	local out = {}
	local cfg = GameConfig.LevelUp
	for _, w in run.Weapons do
		if w.Level < w.Def.MaxLevel then
			table.insert(out, { weaponCard(run, w.Def, w.Level + 1), cfg.WeaponLevelWeight })
		end
	end
	if #run.Weapons < run.Stats.WeaponSlots then
		for _, def in WeaponData.List do
			if run.Unlocked[def.Key] and not run:GetWeapon(def.Key) and (def.MinPlayerLevel or 0) <= run.Level then
				table.insert(out, { weaponCard(run, def, 1), cfg.NewWeaponWeight * (RARITY_WEIGHT[def.Rarity] or 1) })
			end
		end
	end
	local canAddPassive = passiveCount(run) < GameConfig.Player.MaxPassives
	for _, def in UpgradeData.Passives do
		local stacks = run.Passives[def.Key] or 0
		if stacks < def.MaxStacks and (stacks > 0 or canAddPassive) then
			table.insert(out, {
				{
					Id = "P:" .. def.Key,
					Type = "Passive",
					Key = def.Key,
					Title = def.Name,
					Desc = def.Desc,
					Icon = def.Icon,
					Rarity = "Common",
					Level = stacks + 1,
					New = stacks == 0,
				},
				cfg.PassiveWeight,
			})
		end
	end
	return out
end

local function rareCards(run): { { any } }
	local out = {}
	for _, def in UpgradeData.Rares do
		local stacks = run.Rares[def.Key] or 0
		if def.Key == "Awaken" then
			for _, w in run.Weapons do
				if w.Level >= w.Def.MaxLevel and not w.Awakened then
					table.insert(out, {
						{
							Id = "R:Awaken:" .. w.Key,
							Type = "Rare",
							Key = "Awaken",
							Weapon = w.Key,
							Title = "AWAKEN " .. string.upper(w.Def.Name),
							Desc = def.Desc,
							Icon = w.Def.Icon,
							Rarity = def.Rarity,
						},
						def.Weight,
					})
				end
			end
		elseif stacks < def.MaxStacks then
			table.insert(out, {
				{
					Id = "R:" .. def.Key,
					Type = "Rare",
					Key = def.Key,
					Title = def.Name,
					Desc = def.Desc,
					Icon = def.Icon,
					Rarity = def.Rarity,
				},
				def.Weight,
			})
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
	local count = GameConfig.LevelUp.Choices + (if run.Character == "Brainrot" then 1 else 0)
	local pool = candidates(run)
	local rares = rareCards(run)
	local rareChance = GameConfig.LevelUp.RareChance * run.Stats.Luck
	if run.Character == "SixSeven" then
		rareChance *= 2
	end
	if kind == "Chest" then
		rareChance = math.max(rareChance, 0.4)
	end
	local taken = {}
	local cards = {}
	for slot = 1, count do
		local card = nil
		if slot == 1 and run.Bonus67 and not run.Rares.Percent67 then
			run.Bonus67 = false
			for _, entry in rares do
				if entry[1].Key == "Percent67" then
					card = entry[1]
				end
			end
		end
		if not card and rng:NextNumber() < rareChance then
			card = pick(rng, rares, taken)
		end
		if not card then
			card = pick(rng, pool, taken)
		end
		if not card then
			local fill = UpgradeData.Fillers[(slot - 1) % #UpgradeData.Fillers + 1]
			card = { Id = "F:" .. fill.Key, Type = "Filler", Key = fill.Key, Title = fill.Name, Desc = fill.Desc, Icon = fill.Icon, Rarity = "Common" }
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
	if run.PendingChests > 0 then
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
		if not run.Passives[card.Key] then
			table.insert(run.PassiveOrder, card.Key)
		end
		run.Passives[card.Key] = (run.Passives[card.Key] or 0) + 1
	elseif t == "Rare" then
		local key = card.Key
		run.Rares[key] = (run.Rares[key] or 0) + 1
		run.Result.Rares += 1
		if key == "Percent67" then
			run.Wave.Force67 = true
			run.Wave.NextEventAt = math.min(run.Wave.NextEventAt, run.Time + 6.7)
		elseif key == "MainCharacter" then
			run.Revives += 1
		elseif key == "SigmaMode" then
			run.SigmaModeAt = run.Time + 3
		elseif key == "Awaken" then
			local w = run:GetWeapon((card :: any).Weapon)
			if w then
				w.Awakened = true
				run.Result.Awakened += 1
			end
		end
	elseif t == "Filler" then
		if card.Key == "Snack" then
			run:Heal(30)
		else
			run:AddCoins(8)
		end
	end
	run:RefreshStats()
	run:SendLoadout()
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
