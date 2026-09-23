local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local Fusion = require(Shared.Packages.Fusion)
local NetworkingClient = require(Shared.Networking.networkingClient)
local SoundController = require(Shared.Controllers.SoundController)
local UIMotion = require(Shared.Utilities.UIMotion)

local Scope = Fusion.scoped(Fusion)

--> The confirm popup. PurchaseUI in the place is a panel, a header bar, an X, an icon, a title,
--> a description and one green button, every one a copy of something drawn in ShopUI. The shop
--> hands an offer here; this fills the labels, pops the panel open over the shop with cash
--> falling behind it, and asks Roblox for the purchase when the button is pressed.
local GuiName = "PurchaseUI"

--> What falls behind the panel while it is open, and how thick it falls.
--> the coin glyph is not in Roblox's emoji font and draws as a box, so it stays out
local Emojis = { "💸", "💵", "💰", "💸", "💵" }
local RainInterval = 0.09
local MinSize, MaxSize = 34, 78
local MinFall, MaxFall = 2.2, 3.8
local MaxDrift = 0.12
local MaxSpin = 240

--> The burst when a purchase goes through: this many, thrown out from the middle.
local BurstCount = 36
local BurstTime = 1.1
local BurstReach = 0.55

local Spread = Random.new()

export type Offer = {
	Key: string,
	Kind: "Pass" | "Product",
	Id: number,
	Price: number,
	Title: string,
	Description: string,
	Icon: string,
}

local PurchaseController = {
	Gui = nil :: ScreenGui?,
	Motion = nil :: UIMotion.Handle?,
	Fade = nil :: UIMotion.Handle?,
	MotionScope = nil :: any,

	Offer = nil :: Offer?,
	Open = false,

	--> the rain loop of a popup that has since closed sees a new number and stops
	Generation = 0,
}

local function Child(Parent: Instance, Name: string): Instance
	local Found = Parent:FindFirstChild(Name)

	if not Found then
		error(`[Purchase] {GuiName} has nothing called {Name} under {Parent.Name}`)
	end

	return Found
end

local function BindPress(Object: GuiObject, Press: () -> ())
	Object.Active = true

	if Object:IsA("GuiButton") then
		Object.Activated:Connect(Press)

		Object.MouseEnter:Connect(function()
			SoundController:Play("Hover")
		end)

		return
	end

	Object.InputBegan:Connect(function(Input: InputObject)
		if
			Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		then
			Press()
		end
	end)
end

local function Emoji(Parent: Instance, Size: number): TextLabel
	local Label = Instance.new("TextLabel")
	Label.BackgroundTransparency = 1
	Label.BorderSizePixel = 0
	Label.AnchorPoint = Vector2.new(0.5, 0.5)
	Label.Size = UDim2.fromOffset(Size, Size)
	Label.Text = Emojis[Spread:NextInteger(1, #Emojis)]
	Label.TextScaled = true
	Label.Rotation = Spread:NextNumber(-25, 25)
	Label.Parent = Parent

	return Label
end

--> One note falling from above the top edge to below the bottom, drifting a little sideways.
local function Drop(Rain: GuiObject)
	local Size = Spread:NextInteger(MinSize, MaxSize)
	local X = Spread:NextNumber(0, 1)
	local Life = Spread:NextNumber(MinFall, MaxFall)
	local Label = Emoji(Rain, Size)

	Label.Position = UDim2.new(X, 0, 0, -Size)

	TweenService:Create(Label, TweenInfo.new(Life, Enum.EasingStyle.Linear), {
		Position = UDim2.new(X + Spread:NextNumber(-MaxDrift, MaxDrift), 0, 1, Size),
		Rotation = Label.Rotation + Spread:NextNumber(-MaxSpin, MaxSpin),
	}):Play()

	Debris:AddItem(Label, Life)
end

--> A fistful thrown out from the middle, fading as it flies.
local function Burst(Rain: GuiObject)
	for _ = 1, BurstCount do
		local Label = Emoji(Rain, Spread:NextInteger(MinSize, MaxSize))
		local Angle = Spread:NextNumber(0, math.pi * 2)
		local Reach = Spread:NextNumber(BurstReach * 0.3, BurstReach)

		Label.Position = UDim2.fromScale(0.5, 0.5)

		TweenService:Create(Label, TweenInfo.new(BurstTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5 + math.cos(Angle) * Reach, 0.5 + math.sin(Angle) * Reach),
			Rotation = Spread:NextNumber(-MaxSpin, MaxSpin),
			TextTransparency = 1,
		}):Play()

		Debris:AddItem(Label, BurstTime)
	end
end

function PurchaseController:_Rain()
	local Gui = self.Gui

	if not Gui then
		return
	end

	local Rain = Child(Child(Gui, "Dim"), "Rain") :: GuiObject

	self.Generation += 1

	local Mine = self.Generation

	task.spawn(function()
		while self.Open and self.Generation == Mine do
			Drop(Rain)
			task.wait(RainInterval)
		end
	end)
end

function PurchaseController:Show(Offer: Offer)
	local Gui = self.Gui

	if not Gui then
		warn(`[Purchase] no {GuiName} to open`)
		return
	end

	local Panel = Child(Gui, "Panel");
	(Child(Panel, "Title") :: TextLabel).Text = Offer.Title;
	(Child(Panel, "Description") :: TextLabel).Text = Offer.Description;
	(Child(Panel, "Icon") :: ImageLabel).Image = Offer.Icon;
	(Child(Child(Panel, "Buy"), "TitleName") :: TextLabel).Text = Format.Robux(Offer.Price)

	self.Offer = Offer
	self.Open = true

	Gui.Enabled = true

	if self.Motion then
		self.Motion.Show()
	end

	if self.Fade then
		self.Fade.Show()
	end

	SoundController:Play("MenuOpen")
	self:_Rain()
end

function PurchaseController:Close()
	local Gui = self.Gui

	if not self.Open or not Gui then
		return
	end

	self.Open = false
	self.Offer = nil

	if self.Motion then
		self.Motion.Hide()
	end

	if self.Fade then
		self.Fade.Hide()
	end

	task.delay(UIMotion.ShutTime, function()
		if not self.Open and Gui.Parent then
			Gui.Enabled = false
		end
	end)
end

--> The moment a purchase lands: the sound and the fistful of cash, over whatever is open.
function PurchaseController:Celebrate()
	local Gui = self.Gui

	if not Gui then
		return
	end

	SoundController:Play("PurchaseSuccess")

	--> the screen comes on for the burst alone when nothing is open; the dim is faded out then
	local Rain = Child(Child(Gui, "Dim"), "Rain") :: GuiObject

	Gui.Enabled = true
	Burst(Rain)

	task.delay(BurstTime, function()
		if not self.Open and Gui.Parent then
			Gui.Enabled = false
		end
	end)
end

--> The green button. A product with a real id goes to Roblox. One without an id yet is bought
--> straight from the server in Studio, so the whole thing can be played through before the
--> products exist; in a live game it only says in the output that nothing was sold.
function PurchaseController:Confirm()
	local Offer = self.Offer

	if not Offer then
		return
	end

	SoundController:Play("ShopClick")

	if Offer.Id == 0 then
		self:Close()

		if not RunService:IsStudio() then
			warn(`[Purchase] "{Offer.Key}" has no product id yet, nothing was bought`)
			return
		end

		NetworkingClient.Shop.DevBuy.Invoke(Offer.Key):andThen(function(Granted: boolean)
			if Granted then
				self:Celebrate()
			else
				SoundController:Play("Error")
				warn(`[Purchase] Studio buy of "{Offer.Key}" was refused`)
			end
		end)

		return
	end

	if Offer.Kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, Offer.Id)
	else
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, Offer.Id)
	end

	self:Close()
end

function PurchaseController:_Bind(Gui: ScreenGui)
	local Panel = Child(Gui, "Panel") :: GuiObject
	local Dim = Child(Gui, "Dim") :: GuiObject

	self.Gui = Gui
	self.Open = false
	Gui.Enabled = false

	local Previous = self.MotionScope

	if Previous then
		Fusion.doCleanup(Previous)
	end

	local Inner = Fusion.innerScope(Scope)

	self.MotionScope = Inner
	self.Motion = UIMotion.Attach(Inner, Panel)
	self.Fade = UIMotion.Fade(Inner, Dim)

	BindPress(Child(Panel, "CloseButton") :: GuiObject, function()
		SoundController:Play("Click")
		self:Close()
	end)

	BindPress(Dim, function()
		self:Close()
	end)

	BindPress(Child(Panel, "Buy") :: GuiObject, function()
		self:Confirm()
	end)
end

function PurchaseController:Init()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	self:_Bind(PlayerGui:WaitForChild(GuiName) :: ScreenGui)

	--> cloned again every respawn, and the copy has none of these connections
	PlayerGui.ChildAdded:Connect(function(Added: Instance)
		if Added:IsA("ScreenGui") and Added.Name == GuiName then
			self:_Bind(Added)
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(Player: Player, _Id: number, Purchased: boolean)
		if Player == Players.LocalPlayer and Purchased then
			self:Celebrate()
		end
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(UserId: number, _Id: number, Purchased: boolean)
		if UserId == Players.LocalPlayer.UserId and Purchased then
			self:Celebrate()
		end
	end)
end

return PurchaseController
