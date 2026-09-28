--[[
	CollectionData - the COLLECTION BOOK: everything a player can discover.

	  Heroes     unlocked heroes
	  Weapons    abilities picked at least once in a run
	  Abilities  passives picked at least once + evolutions reached
	  Bosses     bosses defeated
	  Enemies    enemies defeated
	  Events     67 events witnessed
	  Secrets    secrets found

	Entries marked Secret show as "???" until they are collected. The book is computed
	from the saved profile (no extra saved state): Collected(profile) -> n, total.
]]

local HeroData = require(script.Parent.HeroData)
local WeaponData = require(script.Parent.WeaponData)
local UpgradeData = require(script.Parent.UpgradeData)
local EnemyData = require(script.Parent.EnemyData)
local WaveData = require(script.Parent.WaveData)
local AchievementData = require(script.Parent.AchievementData)

export type Entry = { Key: string, Name: string, Desc: string, Rarity: string, Secret: boolean? }
export type Category = { Key: string, Name: string, Entries: { Entry } }

local CollectionData = {}

local function list(): { Category }
	local heroes = {}
	for _, def in HeroData.List do
		table.insert(heroes, { Key = def.Key, Name = def.Name, Desc = def.Desc, Rarity = def.Rarity, Secret = def.Secret })
	end
	local weapons, abilities = {}, {}
	for _, def in WeaponData.List do
		if def.Evolution == nil then
			table.insert(weapons, { Key = def.Key, Name = def.Name, Desc = def.Desc, Rarity = def.Rarity, Secret = def.Unlock.Secret ~= nil })
		end
	end
	for _, def in UpgradeData.Passives do
		table.insert(abilities, { Key = def.Key, Name = def.Name, Desc = def.Desc, Rarity = def.Rarity, Secret = def.Secret ~= nil })
	end
	for _, def in WeaponData.Evolutions do
		table.insert(abilities, { Key = def.Key, Name = def.Name, Desc = def.Desc, Rarity = "Mythic" })
	end
	local bosses, enemies = {}, {}
	for _, def in EnemyData.List do
		if def.Collection then
			local rarity = if def.Secret then "Secret" elseif def.Rare then "Legendary" elseif def.Boss or def.MiniBoss then "Epic" else "Common"
			local entry = { Key = def.Key, Name = def.Name, Desc = def.Desc, Rarity = rarity, Secret = def.Secret or def.Key == "The67" }
			if def.Boss or def.MiniBoss then
				table.insert(bosses, entry)
			else
				table.insert(enemies, entry)
			end
		end
	end
	local events = {}
	for _, e in WaveData.Events do
		table.insert(events, { Key = e.Key, Name = e.Title, Desc = e.Sub, Rarity = if e.Weight < 1 then "Legendary" else "Rare", Secret = e.Key == "The67" })
	end
	local secrets = {}
	for _, key in AchievementData.Secrets do
		local def = AchievementData.ByKey[key]
		table.insert(secrets, { Key = key, Name = def.Name, Desc = def.Desc, Rarity = "Secret", Secret = true })
	end
	return {
		{ Key = "Heroes", Name = "Heroes", Entries = heroes },
		{ Key = "Weapons", Name = "Abilities", Entries = weapons },
		{ Key = "Abilities", Name = "Passives & Evolutions", Entries = abilities },
		{ Key = "Bosses", Name = "Bosses", Entries = bosses },
		{ Key = "Enemies", Name = "Enemies", Entries = enemies },
		{ Key = "Events", Name = "67 Events", Entries = events },
		{ Key = "Secrets", Name = "Secrets", Entries = secrets },
	}
end

CollectionData.Categories = list()
CollectionData.ByKey = {} :: { [string]: Category }
CollectionData.Total = 0
for _, cat in CollectionData.Categories do
	CollectionData.ByKey[cat.Key] = cat
	CollectionData.Total += #cat.Entries
end

-- is one entry collected in this profile (the saved data or the client's snapshot)?
function CollectionData.Has(profile, category: string, key: string): boolean
	if type(profile) ~= "table" then
		return false
	end
	local seen = profile.Seen or {}
	if category == "Heroes" then
		return profile.Heroes ~= nil and profile.Heroes[key] == true
	elseif category == "Weapons" then
		return seen.Weapons ~= nil and seen.Weapons[key] == true
	elseif category == "Abilities" then
		return (seen.Passives ~= nil and seen.Passives[key] == true) or (seen.Evolutions ~= nil and seen.Evolutions[key] == true)
	elseif category == "Bosses" or category == "Enemies" then
		return profile.Collection ~= nil and (profile.Collection[key] or 0) > 0
	elseif category == "Events" then
		return seen.Events ~= nil and seen.Events[key] == true
	elseif category == "Secrets" then
		return profile.Achievements ~= nil and (profile.Achievements[key] or 0) > 0
	end
	return false
end

-- collected entries: total, and per category
function CollectionData.Count(profile): (number, number, { [string]: number })
	local n = 0
	local per = {}
	for _, cat in CollectionData.Categories do
		local c = 0
		for _, entry in cat.Entries do
			if CollectionData.Has(profile, cat.Key, entry.Key) then
				c += 1
			end
		end
		per[cat.Key] = c
		n += c
	end
	return n, CollectionData.Total, per
end

return CollectionData
