local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local EmployeeController = require(Shared.Controllers.EmployeeController)
local PlayerData = require(Shared.PlayerData).client
local TutorialConfigs = require(Shared.Configs.Tutorial)

--> The beam from the player's feet to whichever unhired employee the player can actually pay for
--> is nearest right now. They walk, so the target is picked again every frame and the beam's far
--> end moved when it changes. The server counts the hire the moment it is paid for.

--> How long with nobody affordable in the street before the bar says so.
local NobodyPatience = 4

local Stage = {
	Connections = {} :: { RBXScriptConnection },

	--> when the street last had somebody affordable in it, and whether the bar has said it has not
	SeenAt = 0,
	Told = false,

	--> who the beam is on, so it is only moved when that changes
	Target = nil :: BasePart?,
}

--> The nearest employee in the street with nobody's name on them and a price the player can pay,
--> by the character's own root.
local function NearestAffordable(): BasePart?
	local Character = Players.LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	if not Root or not Root:IsA("BasePart") then
		return nil
	end

	local Cash = PlayerData.Cash()
	local Best: BasePart? = nil
	local BestDistance = math.huge

	for _, Employee in EmployeeController.Employees do
		if Employee.Owner or Employee.Cost > Cash or not Employee.Root:IsDescendantOf(workspace) then
			continue
		end

		local Distance = (Employee.Root.Position - Root.Position).Magnitude

		if Distance < BestDistance then
			Best = Employee.Root
			BestDistance = Distance
		end
	end

	return Best
end

function Stage.Start(Tutorial: any)
	Stage.SeenAt = os.clock()
	Stage.Told = false
	Stage.Target = nil

	--> aims the beam, and says when there has been nobody to point at for a while
	table.insert(
		Stage.Connections,
		RunService.Heartbeat:Connect(function()
			local Now = os.clock()
			local Target = NearestAffordable()

			if Target ~= Stage.Target then
				Stage.Target = Target

				if Target then
					Tutorial.Follow:Switch(Target)
				else
					Tutorial.Follow:Stop()
				end
			end

			if Target then
				Stage.SeenAt = Now
				Stage.Told = false
				return
			end

			if not Stage.Told and Now - Stage.SeenAt > NobodyPatience then
				Stage.Told = true
				Tutorial:Notify(TutorialConfigs.Notices.NoAffordable)
			end
		end)
	)

	--> the beam's near end is on the character's root, which a respawn replaces; forgetting the
	--> target has the next frame run it again to the new one
	table.insert(
		Stage.Connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			Stage.Target = nil
		end)
	)
end

function Stage.Cleanup(Tutorial: any)
	for _, Connection in Stage.Connections do
		Connection:Disconnect()
	end

	table.clear(Stage.Connections)

	Stage.Target = nil
	Tutorial.Follow:Stop()
end

return Stage
