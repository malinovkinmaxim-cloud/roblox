--[[
	Codes - promo codes (server only, so players cannot read the list from the client).
	Each code works once per profile. Keys are UPPERCASE; players can type any case.
	Add codes for updates / milestones here.
]]

return {
	["67"] = { Coins = 67, Text = "Six seven. +67 coins" },
	["BRAINROT"] = { Coins = 150, Text = "+150 coins" },
	["SIGMA"] = { Coins = 100, Text = "+100 coins, sigma" },
	["GOOBER"] = { Coins = 100, Text = "+100 coins" },
	["RELEASE"] = { Coins = 250, Text = "Thanks for playing! +250 coins" },
} :: { [string]: { Coins: number, Text: string } }
