local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local Unithub = require(Shared.Packages.Unithub)
local PlayerData = require(Shared.PlayerData)
local Proximityprompt = require(Shared.Packages.Proximityprompt)
local Renders = require(Shared.Configs.Renders)

local function RenderTree(): Folder
	local Tree = Instance.new("Folder")
	Tree.Name = "RenderPreload"

	for _, Components in Renders.Components do
		for _, AssetId in Components do
			local Label = Instance.new("ImageLabel")
			Label.Image = AssetId
			Label.Parent = Tree
		end
	end

	for _, AssetId in Renders.Employees do
		local Label = Instance.new("ImageLabel")
		Label.Image = AssetId
		Label.Parent = Tree
	end

	Tree.Parent = script

	return Tree
end

Unithub:init({
	Preload = {
		Aggressive = false,
		--> Critical, unlike the renders: it is two animations rather than 48 images, and a seated
		--> employee is built during Start, so it has to be typing the frame it appears.
		CriticalRoots = { Assets:WaitForChild("Animations") },
		BackgroundRoots = { RenderTree() },
	},
})

Proximityprompt.Init()
