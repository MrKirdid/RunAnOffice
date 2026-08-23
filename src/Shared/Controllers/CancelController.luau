local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CarryController = require(Shared.Controllers.CarryController)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client

local GuiName = "CancelUI"

local CancelController = {
	Gui = nil :: ScreenGui?,

	--> One drop in flight at a time, or a double click sends a second one that always comes back false.
	Dropping = false,
}

function CancelController:GetGui(): ScreenGui?
	if self.Gui and self.Gui.Parent then
		return self.Gui
	end

	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	self.Gui = PlayerGui and PlayerGui:FindFirstChild(GuiName) :: ScreenGui?

	return self.Gui
end

--> Holding is the whole story: it is set the moment a rolled part is picked up off a pad and
--> emptied again once it is placed, so the prompt tracks it rather than the pickup itself.
function CancelController:Refresh()
	local Gui = self:GetGui()

	if not Gui then
		return
	end

	local Held = PlayerData.Holding()

	Gui.Enabled = type(Held) == "table" and Held.Component ~= nil
end

--> Undoes the pickup: the server lets go of what is held, and the model that was carried over from
--> the pad goes with it. Refresh takes the prompt back down when Holding empties.
function CancelController:Drop()
	if self.Dropping then
		return
	end

	self.Dropping = true

	NetworkingClient.Items.Drop
		.Invoke()
		:andThen(function(Dropped: boolean)
			if Dropped then
				CarryController:Clear()
			end
		end)
		:catch(function(Problem)
			warn(`[Cancel] {Problem}`)
		end)
		:finally(function()
			self.Dropping = false
		end)
end

function CancelController:BindClose()
	local Gui = self:GetGui()
	local Outer = Gui and Gui:FindFirstChild("MainBackground")
	local Inner = Outer and Outer:FindFirstChild("MainBackground")

	if not Inner then
		return
	end

	--> There are two CloseButtons stacked in the mock; bind whatever is there.
	for _, Button in Inner:GetChildren() do
		if Button.Name == "CloseButton" and Button:IsA("ImageButton") then
			--> Inactive GuiButtons swallow the click without firing Activated.
			Button.Active = true

			--> No need to hide the prompt here: dropping empties Holding, and Refresh is watching it.
			Button.Activated:Connect(function()
				self:Drop()
			end)
		end
	end
end

function CancelController:Start()
	Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild(GuiName)

	self:BindClose()

	PlayerData.Holding.Changed(function()
		self:Refresh()
	end)

	self:Refresh()
end

return CancelController
