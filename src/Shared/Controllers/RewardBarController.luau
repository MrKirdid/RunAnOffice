local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client
local PurchaseController = require(Shared.Controllers.PurchaseController)
local RewardConfigs = require(Shared.Configs.Rewards)
local SoundController = require(Shared.Controllers.SoundController)
local Store = require(Shared.Utilities.Store)

--> The bar on the right of the hud, as drawn in the place: a claim button with what it pays beside
--> it, and the next rung of the cash ladder with its Robux price. The claim counts down to its
--> next one on its own button; the rung button sells whichever rung is next and goes once the
--> ladder is done.
local HudName = "HudGUI"
local BarPath = { "Root", "RewardBar" }
local RateAttribute = "MoneyPerSecond"
local LadderKey = "Ladder"
local ReadyText = "Claim!"

--> the parts of the bar that belong to the rung button, hidden with it when there is no next rung
local RungParts = { "DoubleCashButton", "RobuxPriceLabel", "RobuxIcon" }

local RewardBarController = {
	Bar = nil :: Instance?,
	Claiming = false,
}

local function Walk(From: Instance, Path: { string }): Instance?
	local At: Instance? = From

	for _, Name in Path do
		At = At and At:FindFirstChild(Name)
	end

	return At
end

local function SetText(Parent: Instance?, Name: string, Text: string)
	local Found = Parent and Parent:FindFirstChild(Name, true)

	if Found and Found:IsA("TextLabel") then
		Found.Text = Text
	end
end

--> mm:ss, which is all a quarter of an hour ever needs
local function Clock(Seconds: number): string
	local Whole = math.max(0, math.ceil(Seconds))
	local Rest = Whole % 60

	return `{Whole // 60}:{if Rest < 10 then "0" else ""}{Rest}`
end

function RewardBarController:GetBar(): Instance?
	if self.Bar and self.Bar.Parent then
		return self.Bar
	end

	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local Hud = PlayerGui and PlayerGui:FindFirstChild(HudName)

	self.Bar = Hud and Walk(Hud, BarPath)

	if self.Bar then
		self:_Bind(self.Bar)
	end

	return self.Bar
end

function RewardBarController:SecondsLeft(): number
	return RewardConfigs.ClaimInterval - (os.time() - PlayerData.LastClaim())
end

--> What the claim would pay right now, off the same rate the hud shows over the plot.
function RewardBarController:Preview(): number
	local Rate = Players.LocalPlayer:GetAttribute(RateAttribute)

	return if type(Rate) == "number" then math.floor(Rate * RewardConfigs.ClaimSeconds) else 0
end

function RewardBarController:_NextRung(): (Store.Rung?, number)
	local Owned = PlayerData.Store.CashRung()

	return Store.Rungs()[Owned + 1], Owned
end

function RewardBarController:Refresh()
	local Bar = self:GetBar()

	if not Bar then
		return
	end

	local Left = self:SecondsLeft()
	local Claim = Bar:FindFirstChild("ClaimButton")

	SetText(Claim, "Label", if Left > 0 then Clock(Left) else ReadyText)
	SetText(Bar, "ClaimAmountLabel", Format.Short(self:Preview()))

	local Next = self:_NextRung()

	for _, Name in RungParts do
		local Part = Bar:FindFirstChild(Name)

		if Part and Part:IsA("GuiObject") then
			Part.Visible = Next ~= nil
		end
	end

	if Next then
		SetText(Bar:FindFirstChild("DoubleCashButton"), "Label", `{Next.Multiplier}x cash`)
		SetText(Bar, "RobuxPriceLabel", tostring(Next.Price))
	end
end

function RewardBarController:Claim()
	if self.Claiming then
		return
	end

	--> turned down here as well as on the server, so an early press answers on the spot
	if self:SecondsLeft() > 0 or self:Preview() <= 0 then
		SoundController:Play("Error")
		return
	end

	self.Claiming = true

	NetworkingClient.Rewards.Claim
		.Invoke()
		:andThen(function(Amount: number)
			SoundController:Play(if Amount > 0 then "Purchase" else "Error")
		end)
		:catch(function(Problem)
			warn(`[RewardBar] {Problem}`)
		end)
		:finally(function()
			self.Claiming = false
			self:Refresh()
		end)
end

function RewardBarController:BuyRung()
	local Next = self:_NextRung()

	if not Next then
		SoundController:Play("Error")
		return
	end

	local Ladder = Store.Entry(LadderKey)

	SoundController:Play("ShopClick")

	PurchaseController:Show({
		Key = Next.Key,
		Kind = "Product",
		Id = Next.Id,
		Price = Next.Price,
		Title = `Cash x{Next.Multiplier}`,
		Description = "Every desk pays more, forever!",
		Icon = if Ladder and Ladder.Icon then Ladder.Icon else "",
	})
end

--> Once per copy of the hud: a ResetOnSpawn hud is a new bar after every respawn.
function RewardBarController:_Bind(Bar: Instance)
	for Name, Press in
		{
			ClaimButton = function()
				self:Claim()
			end,
			DoubleCashButton = function()
				self:BuyRung()
			end,
		}
	do
		local Button = Bar:FindFirstChild(Name)

		if Button and Button:IsA("GuiButton") then
			Button.Active = true
			Button.Activated:Connect(Press)
		end
	end
end

function RewardBarController:Start()
	--> once a second is all a clock that only shows whole seconds needs, and it keeps the claim's
	--> amount following the rate as desks and parts change
	task.spawn(function()
		while true do
			self:Refresh()
			task.wait(1)
		end
	end)
end

return RewardBarController
