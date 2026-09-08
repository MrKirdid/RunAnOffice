local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared

local Store = require(Shared.Utilities.Store)

--> One boost for the whole server, bought by one player and felt by everyone. It is a fact about
--> the server rather than any save, so it lives as attributes on Workspace: replicated to every
--> client for the banner, read by every roll through Store.ServerLuck, and gone when the server
--> is. Nothing here is written to a profile.
local Interval = 1

local ServerLuckService = {}

function ServerLuckService:Get(): (number, number, string)
	local Multiplier = Workspace:GetAttribute(Store.LuckAttribute)
	local Expires = Workspace:GetAttribute(Store.ExpiresAttribute)
	local Sponsor = Workspace:GetAttribute(Store.SponsorAttribute)

	return if type(Multiplier) == "number" then Multiplier else 1,
		if type(Expires) == "number" then Expires else 0,
		if type(Sponsor) == "string" then Sponsor else ""
end

function ServerLuckService:Clear()
	Workspace:SetAttribute(Store.LuckAttribute, 1)
	Workspace:SetAttribute(Store.ExpiresAttribute, 0)
	Workspace:SetAttribute(Store.SponsorAttribute, "")
end

--> The rule the shop promises: a higher tier takes over and keeps whichever clock is longer, the
--> same tier adds its minutes on, and a lower tier bought while a higher one is running adds its
--> minutes to the higher one rather than pulling it down. Two tiers never multiply together.
function ServerLuckService:Apply(Sponsor: Player, Multiplier: number, Minutes: number): boolean
	if Multiplier < 1 or Minutes <= 0 then
		return false
	end

	local Now = os.time()
	local Current, Expires = self:Get()
	local Running = Expires > Now

	local Length = Minutes * 60

	if not Running then
		Workspace:SetAttribute(Store.LuckAttribute, Multiplier)
		Workspace:SetAttribute(Store.ExpiresAttribute, Now + Length)
		Workspace:SetAttribute(Store.SponsorAttribute, Sponsor.Name)

		return true
	end

	if Multiplier > Current then
		Workspace:SetAttribute(Store.LuckAttribute, Multiplier)
		Workspace:SetAttribute(Store.ExpiresAttribute, math.max(Expires, Now + Length))
		Workspace:SetAttribute(Store.SponsorAttribute, Sponsor.Name)

		return true
	end

	Workspace:SetAttribute(Store.ExpiresAttribute, Expires + Length)

	return true
end

function ServerLuckService:Start()
	self:Clear()

	--> The multiplier is read off the clock everywhere, so this only tidies the attributes once a
	--> boost has run out, which is what lets the banner go away.
	task.spawn(function()
		while true do
			task.wait(Interval)

			local Multiplier, Expires = self:Get()

			if Multiplier ~= 1 and Expires <= os.time() then
				self:Clear()
			end
		end
	end)
end

return ServerLuckService
