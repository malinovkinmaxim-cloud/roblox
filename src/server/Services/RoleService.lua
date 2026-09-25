--[[
	RoleService
	- discovers role modules in ServerScriptService.Server.Roles (add a module + RoleConfig entry = new role)
	- picks the role for a level (fixed or random pool weighted by Config.ROLE_CHANCES)
	- swaps roles mid-level (checkpoint SetRole) and handles the gradual reveal ("???" -> "THE TROLL.")
	- routes ABILITY / INTERACT input to the active role
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RoleConfig = require(ReplicatedStorage.Shared.RoleConfig)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local RoleService = {}
RoleService.Modules = {}

function RoleService:Init(services)
	self.Services = services
	local folder = script.Parent.Parent:FindFirstChild("Roles")
	if folder then
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") and module.Name ~= "RoleBase" then
				local ok, role = pcall(require, module)
				if ok then
					self.Modules[module.Name] = role
				else
					warn("[RoleService] failed to load role " .. module.Name .. ": " .. tostring(role))
				end
			end
		end
	end
end

function RoleService:Start()
	local limiter = RateLimiter.new(5, 6)
	Net.Event("UseAbility").OnServerEvent:Connect(function(player)
		if not limiter:Allow(player) then
			return
		end
		self:_useInput(player, "UseAbility")
	end)
	Net.Event("UseInteract").OnServerEvent:Connect(function(player)
		if not limiter:Allow(player) then
			return
		end
		self:_useInput(player, "UseInteract")
	end)
end

function RoleService:_useInput(player: Player, method: string)
	local run = self.Services.RoundService:GetRun(player)
	if not run or run.Ended or run.Player ~= player or run.State ~= "Playing" then
		return
	end
	local role = run.Role
	if not role then
		return
	end
	local ok, message = role[method](role)
	if not ok and message then
		Net.Event("Toast"):FireClient(player, message, "Hint")
	end
end

function RoleService:HasRole(name: string): boolean
	return self.Modules[name] ~= nil
end

-- Weighted pick among a pool using Config.ROLE_CHANCES.
function RoleService:PickFromPool(pool: { string }, rng: Random): string
	local total = 0
	for _, name in pool do
		total += Config.ROLE_CHANCES[name] or 0
	end
	if total <= 0 then
		return pool[rng:NextInteger(1, #pool)]
	end
	local roll = rng:NextNumber() * total
	for _, name in pool do
		roll -= Config.ROLE_CHANCES[name] or 0
		if roll <= 0 then
			return name
		end
	end
	return pool[#pool]
end

function RoleService:ChooseInitialRole(run): (string, boolean)
	local def = run.Def
	if run.ForcedRole and self.Modules[run.ForcedRole] then
		return run.ForcedRole, false
	end
	if type(def.Role) == "table" and def.Role.Pool then
		return self:PickFromPool(def.Role.Pool, run.Instance.Rng), true
	end
	return def.Role or "Follower", def.RoleHidden == true
end

function RoleService:AssignInitialRole(run)
	local name, hidden = self:ChooseInitialRole(run)
	self:SetRole(run, name, { Hidden = hidden, Reveal = not hidden, Initial = true })
end

function RoleService:_makeContext(run)
	local services = self.Services
	return {
		Run = run,
		Actor = run.Doppel,
		Recorder = run.Recorder,
		Services = services,
		Rng = run.Instance.Rng,
		Reveal = function()
			self:Reveal(run)
		end,
		Status = function(key: string?, text: string?)
			if run.Player.Parent then
				Net.Event("DoppelStatus"):FireClient(run.Player, key, text)
			end
		end,
		Toast = function(text: string, kind: string?)
			if run.Player.Parent then
				Net.Event("Toast"):FireClient(run.Player, text, kind or "Info")
			end
		end,
	}
end

--[[
	opts: Hidden (start as "???"), Reveal (play the reveal effect), Initial, Checkpoint
]]
function RoleService:SetRole(run, name: string, opts: { [string]: any }?)
	opts = opts or {}
	local module = self.Modules[name]
	if not module then
		warn("[RoleService] unknown role " .. tostring(name))
		return
	end
	if not run.Doppel then
		run.PendingRole = name
		return
	end
	if run.Role then
		run.Role:Stop()
		run.Role = nil
	end
	local role = module.new(self:_makeContext(run))
	run.Role = role
	run.RoleName = name
	run.RoleHistory[name] = true
	run.RoleRevealed = not (opts :: any).Hidden

	-- a role switch mid-level: make sure the doppel starts from a sane place
	if not (opts :: any).Initial and run.Doppel then
		if not run.Doppel:IsAlive() then
			run.Doppel:Respawn(run.Instance.Checkpoints[run.CheckpointIndex].DoppelCFrame)
		end
		run.Doppel:Glitch()
		if run.Recorder then
			run.Recorder:Clear()
		end
	end

	self:_refreshDisplay(run)
	role:Start()
	self:SendRoleState(run)
	if run.RoleRevealed and (opts :: any).Reveal then
		Net.Event("RoleRevealed"):FireClient(run.Player, name)
	end
end

function RoleService:Reveal(run)
	if run.RoleRevealed or run.Ended then
		return
	end
	run.RoleRevealed = true
	self:_refreshDisplay(run)
	self:SendRoleState(run)
	Net.Event("RoleRevealed"):FireClient(run.Player, run.RoleName)
end

function RoleService:_refreshDisplay(run)
	local doppel = run.Doppel
	if not doppel then
		return
	end
	local info = RoleConfig.Get(run.RoleName)
	if run.RoleRevealed and info then
		doppel:SetRoleDisplay(info.DisplayName, info.Color)
	else
		doppel:SetRoleDisplay(RoleConfig.HiddenName, RoleConfig.HiddenColor)
	end
end

function RoleService:GetRoleState(run)
	local info = RoleConfig.Get(run.RoleName)
	local abilities = if run.Role then run.Role:GetAbilityInfo() else {}
	local revealed = run.RoleRevealed
	return {
		Role = if revealed then run.RoleName else nil,
		Display = if revealed and info then info.DisplayName else RoleConfig.HiddenName,
		Color = if revealed and info then info.Color else RoleConfig.HiddenColor,
		Description = if revealed and info then info.Description else "What will it do?",
		Ability = abilities.Ability,
		Interact = abilities.Interact,
	}
end

function RoleService:SendRoleState(run)
	if run.Player.Parent then
		Net.Event("RoleState"):FireClient(run.Player, self:GetRoleState(run))
	end
end

return RoleService
