local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskSlotController = require(Shared.Controllers.DeskSlotController)

--> The beam from the player's feet to a gift still wrapped on one of their desks. A gift opened is
--> gone, so the beam moves on to the next one until the desk wears none. The server sees the
--> last part land.

--> How often the gifts are looked over for one to point at.
local Poll = 0.25

local Stage = {
	--> set for as long as the step is up, so the loop stops with it
	Running = false,

	--> the gift the beam is on right now
	Target = nil :: Attachment?,
}

--> A gift standing on any desk, whichever comes first. They are only built over slots with
--> nothing on them, so any one found is one still to open.
local function FindGift(): Attachment?
	for _, Set in DeskSlotController.Buttons do
		for _, Entry in Set.Entries do
			if Entry.Anchor.Parent then
				return Entry.Anchor
			end
		end
	end

	return nil
end

function Stage.Start(Tutorial: any)
	Stage.Running = true
	Stage.Target = nil

	task.spawn(function()
		while Stage.Running do
			local Current = Stage.Target
			local Gone = Current == nil or Current.Parent == nil

			if Gone then
				local Next = FindGift()

				if Next then
					if Current then
						Tutorial.Follow:Switch(Next)
					else
						Tutorial.Follow:Start(Next)
					end
				elseif Current then
					Tutorial.Follow:Stop()
				end

				Stage.Target = Next
			end

			task.wait(Poll)
		end
	end)
end

function Stage.Cleanup(Tutorial: any)
	Stage.Running = false
	Stage.Target = nil

	Tutorial.Follow:Stop()
end

return Stage
