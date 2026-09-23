local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Admins = require(Shared.Configs.Admins)
local CommandUtil = require(Shared.Console.CommandUtil)

local CmdrController = {
	Cmdr = nil :: any,
}

--> A phone has no F2. The button only ever shows the console: Cmdr already hides itself on a tap
--> outside its own bar, and that tap lands before Activated does, so a toggle here would reopen
--> what the tap just closed. Closing is tapping anywhere else, which is the desktop behaviour too.
local function BuildTouchButton(Cmdr: any)
	local Gui = Instance.new("ScreenGui")
	Gui.Name = "CmdrTouch"
	Gui.ResetOnSpawn = false
	Gui.DisplayOrder = 100

	local Button = Instance.new("TextButton")
	Button.Name = "Open"
	Button.AnchorPoint = Vector2.new(1, 0)
	Button.Position = UDim2.new(1, -8, 0, 8)
	Button.Size = UDim2.fromOffset(44, 28)
	Button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	Button.BackgroundTransparency = 0.3
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.Font = Enum.Font.GothamBold
	Button.TextSize = 12
	Button.Text = ">_"
	Button.Parent = Gui

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 6)
	Corner.Parent = Button

	Button.Activated:Connect(function()
		Cmdr:Show()
	end)

	Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function CmdrController:Init()
	--> The server moves this out of the package and into ReplicatedStorage on boot, so it is not
	--> there when the client starts and has to be waited on.
	local Cmdr = require(ReplicatedStorage:WaitForChild("CmdrClient")) :: any

	self.Cmdr = Cmdr

	local IsAdmin = CommandUtil.IsAdmin(Players.LocalPlayer)

	Cmdr:SetActivationKeys(Admins.ActivationKeys)
	Cmdr:SetPlaceName(Admins.PlaceName)
	--> Nothing to open for anyone the server would refuse anyway.
	Cmdr:SetEnabled(IsAdmin)

	--> A refusal here rather than a round trip: a client-run command never reaches the server's
	--> hook at all, and the rest get the same answer sooner. The server's copy is the real gate.
	Cmdr.Registry:RegisterHook("BeforeRun", function(Context)
		if not CommandUtil.IsAdmin(Context.Executor) then
			return "You do not have permission to run commands here."
		end

		return nil
	end)

	if IsAdmin and UserInputService.TouchEnabled then
		BuildTouchButton(Cmdr)
	end
end

return CmdrController
