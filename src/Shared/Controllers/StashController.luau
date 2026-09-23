local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CarryController = require(Shared.Controllers.CarryController)
local Items = require(Shared.Utilities.Items)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client
local SoundController = require(Shared.Controllers.SoundController)
local UIController = require(Shared.Controllers.UIController)

--> The button that used to cancel a pickup now puts the part away. Same screen in the place, same
--> X on it; what it does is the only thing that changed, since a part is never thrown away any more.
local GuiName = "CancelUI"

local StashController = {
	Gui = nil :: ScreenGui?,

	--> One stash in flight at a time, or a double click sends a second one that always comes back false.
	Stashing = false,
}

function StashController:GetGui(): ScreenGui?
	if self.Gui and self.Gui.Parent then
		return self.Gui
	end

	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	self.Gui = PlayerGui and PlayerGui:FindFirstChild(GuiName) :: ScreenGui?

	return self.Gui
end

--> Holding is the whole story: it is set the moment a part is picked up, stolen or equipped, and
--> emptied again once it is placed or stashed, so the prompt tracks it rather than the pickup itself.
--> The hud goes with it. Read off Holding rather than off CarryController so it is the same one
--> fact driving both: the save is what says a part is in hand, which means a respawn or a rejoin
--> mid carry comes back with the hud already out of the way instead of over the part.
--> A stolen part cannot be put away until it has been carried home, so the button stays down
--> while it is still tagged; the hud stays away either way, since the part is being aimed.
function StashController:Refresh()
	local Held = PlayerData.Holding()
	local Carrying = Items.IsHeld(Held)
	local Secured = Carrying and Held.StolenFrom == nil

	UIController:SetHudCarrying(Carrying)

	local Gui = self:GetGui()

	if not Gui then
		return
	end

	Gui.Enabled = Secured
end

--> Puts the held part in the inventory. The model that was carried goes with it; the inventory
--> screen is where it comes back from. Refresh takes the button down when Holding empties.
function StashController:Stash()
	if self.Stashing then
		return
	end

	self.Stashing = true

	NetworkingClient.Items.Stash
		.Invoke()
		:andThen(function(Stashed: boolean)
			SoundController:Play(if Stashed then "Confirm" else "Error")

			if Stashed then
				CarryController:Clear()
			end
		end)
		:catch(function(Problem)
			warn(`[Stash] {Problem}`)
		end)
		:finally(function()
			self.Stashing = false
		end)
end

function StashController:BindClose()
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

			--> No need to hide the prompt here: stashing empties Holding, and Refresh is watching it.
			Button.Activated:Connect(function()
				self:Stash()
			end)
		end
	end
end

function StashController:Start()
	Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild(GuiName)

	self:BindClose()

	PlayerData.Holding.Changed(function()
		self:Refresh()
	end)

	self:Refresh()
end

return StashController
