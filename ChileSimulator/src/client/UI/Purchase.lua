--[[
	Purchase - Robux prompts. Items with Id = 0 are not configured yet:
	  * in Studio they can be "bought" for free to test them (StudioPurchase remote)
	  * in a live game they are hidden
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared").ShopConfig)

local Purchase = {}

function Purchase.Available(item): boolean
	return item.Id > 0 or RunService:IsStudio()
end

function Purchase.Pass(controllers, key: string)
	local pass = ShopConfig.Passes[key]
	if not pass then
		return
	end
	if pass.Id > 0 then
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.Id)
	elseif RunService:IsStudio() then
		controllers.ClientData:Fire("StudioPurchase", "Pass", key)
	end
end

function Purchase.Product(controllers, key: string)
	local product = ShopConfig.Products[key]
	if not product then
		return
	end
	if product.Id > 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.Id)
	elseif RunService:IsStudio() then
		controllers.ClientData:Fire("StudioPurchase", "Product", key)
	end
end

return Purchase
