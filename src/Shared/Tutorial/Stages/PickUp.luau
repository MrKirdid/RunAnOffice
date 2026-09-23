local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotController = require(Shared.Controllers.PlotController)

--> The beam from the player's feet to the part standing on the first pad: the part itself, not the
--> pad under it. It is stood up by the roll's own animation a beat after the roll lands, so it is
--> waited for. The server sees it arrive in the hands.

local PromptName = "Pickup"

--> How long the part gets to appear, and how often it is looked for.
local PartWait = 12
local PartPoll = 0.2

--> How far from the pad's centre a part still counts as standing on it.
local PadReach = 4

--> The first pad on the plot, which is where the rigged roll lands.
local function FindPad(): BasePart?
	local _, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local Pads = Plot:FindFirstChild("Pads")
	local Pad = Pads and Pads:FindFirstChild("1")

	return if Pad then Pad:FindFirstChildWhichIsA("BasePart", true) else nil
end

--> The part with a live pickup prompt nearest the pad, or nothing while the roll is still
--> putting it there.
local function FindPart(Pad: BasePart): Model?
	local Best: Model? = nil
	local BestDistance = PadReach

	for _, Descendant in workspace:GetDescendants() do
		if not Descendant:IsA("ProximityPrompt") or Descendant.Name ~= PromptName or not Descendant.Enabled then
			continue
		end

		local Model = Descendant:FindFirstAncestorOfClass("Model")
		local Distance = if Model then (Model:GetPivot().Position - Pad.Position).Magnitude else math.huge

		if Distance < BestDistance then
			Best = Model
			BestDistance = Distance
		end
	end

	return Best
end

local Stage = {
	--> set while a start is still waiting for the part, so a cleanup that comes first wins
	Looking = false,
}

function Stage.Start(Tutorial: any)
	local Pad = FindPad()

	if not Pad then
		warn("[Tutorial] the plot has no first pad to point at")
		return
	end

	Stage.Looking = true

	local Part = FindPart(Pad)
	local Waited = 0

	while not Part and Stage.Looking and Waited < PartWait do
		Waited += task.wait(PartPoll)
		Part = FindPart(Pad)
	end

	if not Stage.Looking then
		return
	end

	Stage.Looking = false

	--> the pad itself if the part never showed, so the step still points somewhere
	local Anchor = if Part then Part:FindFirstChildWhichIsA("BasePart", true) else nil

	Tutorial.Follow:Start(Anchor or Pad)
end

function Stage.Cleanup(Tutorial: any)
	Stage.Looking = false

	Tutorial.Follow:Stop()
end

return Stage
