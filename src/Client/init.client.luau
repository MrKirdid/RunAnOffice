local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Unithub = require(Shared.Packages.Unithub)
local PlayerData = require(Shared.PlayerData)
local Proximityprompt = require(Shared.Packages.Proximityprompt)
local Renders = require(Shared.Configs.Renders)

--> Every part render, which lives only as a string in Renders until a roll lands and an item card
--> is built. Nothing in the tree holds one, so the preloader would never find them on its own.
--> They are carried in on ImageLabels rather than handed over as ids because ContentProvider
--> resolves a bare id with no idea what type it is and fails all 48; on a label it reads them as
--> images and takes all 48. The labels are never drawn, and they stay parented both because the
--> preloader skips unparented roots and because they keep the renders referenced afterwards.
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

	Tree.Parent = script

	return Tree
end

--> Background rather than critical: no render is on screen at spawn, and a critical root holds
--> every controller's Start behind the fetch. Aggressive is off for the same reason, so this
--> stays a preload of the renders and not of the whole place.
Unithub:init({
	Preload = {
		Aggressive = false,
		BackgroundRoots = { RenderTree() },
	},
})

Proximityprompt.Init()
