--[[
	TitleConfig
	Titles are EARNED (never bought) and shown above the player's head.
	Requirement: Level = N  (complete level N)  or  Stat = "...", Goal = N  (profile.Stats)
]]

local TitleConfig = {}

TitleConfig.Default = "Newcomer"

TitleConfig.Order = {
	"Newcomer",
	"EchoFriend",
	"Racer",
	"ShadowWalker",
	"Tester",
	"ChapterOne",
	"Flawless",
	"RivalSlayer",
	"TrustIssues",
	"DoppelMaster",
}

TitleConfig.Titles = {
	Newcomer = { Text = "NEWCOMER", Color = Color3.fromRGB(200, 205, 220), Description = "Everyone starts somewhere." },
	EchoFriend = { Text = "ECHO FRIEND", Color = Color3.fromRGB(120, 215, 255), Level = 3, Description = "Complete level 3." },
	Racer = { Text = "RACER", Color = Color3.fromRGB(255, 150, 80), Stat = "RivalWins", Goal = 1, Description = "Beat your Rival once." },
	ShadowWalker = { Text = "SHADOW WALKER", Color = Color3.fromRGB(170, 120, 255), Level = 8, Description = "Complete level 8." },
	Tester = { Text = "PLATFORM TESTER", Color = Color3.fromRGB(255, 210, 70), Level = 9, Description = "Complete level 9." },
	ChapterOne = { Text = "CHAPTER ONE", Color = Color3.fromRGB(80, 230, 140), Level = 10, Description = "Pass the Final Test." },
	Flawless = { Text = "FLAWLESS", Color = Color3.fromRGB(60, 225, 255), Stat = "NoDeathClears", Goal = 10, Description = "Finish 10 levels without dying." },
	RivalSlayer = { Text = "RIVAL SLAYER", Color = Color3.fromRGB(255, 80, 80), Stat = "RivalWins", Goal = 10, Description = "Beat your Rival 10 times." },
	TrustIssues = { Text = "TRUST ISSUES", Color = Color3.fromRGB(255, 80, 200), Level = 12, Description = "Complete level 12." },
	DoppelMaster = { Text = "DOPPEL MASTER", Color = Color3.fromRGB(255, 200, 60), Stat = "UniqueLevelsCompleted", Goal = 12, Description = "Complete every level." },
}

function TitleConfig.IsUnlocked(profile, titleId: string): boolean
	local title = TitleConfig.Titles[titleId]
	if not title or not profile then
		return false
	end
	if title.Level then
		return profile.CompletedLevels ~= nil and profile.CompletedLevels["L" .. tostring(title.Level)] == true
	end
	if title.Stat then
		return ((profile.Stats or {})[title.Stat] or 0) >= (title.Goal or 1)
	end
	return true
end

return TitleConfig
