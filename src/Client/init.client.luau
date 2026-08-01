local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Unithub = require(Shared.Packages.Unithub)
local PlayerData = require(Shared.PlayerData)
local Proximityprompt = require(Shared.Packages.Proximityprompt)

Unithub:init()
Proximityprompt.Init()
