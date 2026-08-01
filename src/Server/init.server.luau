local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Unithub = require(Shared.Packages.Unithub)
local PlayerData = require(Shared.PlayerData)

Unithub:init({
	services = script.Services,
	controllers = Shared.Controllers,
})
