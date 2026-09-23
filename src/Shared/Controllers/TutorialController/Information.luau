local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local SoundController = require(Shared.Controllers.SoundController)

--> The bar at the top that says what to do next, typed out a letter at a time, with the reason
--> under it. It doubles as the place a refusal is explained: a notice takes the bar over for a
--> moment and the step's own line comes back after.

--> How far above its place the bar starts from and leaves to, as a fraction of the screen.
local Drop = 0.025

--> Seconds per letter, how long a line that ends itself stays up once it is all there, and how
--> long a notice holds the bar before the step's line is put back.
local TypeRate = 0.02
local LingerTime = 1.5
local NoticeTime = 2.2

local FadeTween = TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local SlideTween = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local Information = {
	Group = nil :: CanvasGroup?,
	Title = nil :: TextLabel?,
	Detail = nil :: TextLabel?,

	Home = UDim2.fromScale(0.5, 0.075),
	Away = UDim2.fromScale(0.5, 0.05),

	--> Bumped every Display, so a line still being typed when the next arrives stops where it is
	--> rather than the two typing over each other.
	Serial = 0,

	--> the step's own line, kept so a notice can hand the bar back to it
	Text = "",
	DetailText = "",
}

function Information:Attach(Group: CanvasGroup)
	self.Group = Group
	self.Title = Group:FindFirstChild("Title", true) :: TextLabel
	self.Detail = Group:FindFirstChild("Detail", true) :: TextLabel

	self.Home = Group.Position
	self.Away = UDim2.fromScale(Group.Position.X.Scale, Group.Position.Y.Scale - Drop)
end

function Information:_Typewrite(Text: string, Detail: string, Serial: number, HideAfter: boolean?)
	local Title, DetailLabel = self.Title, self.Detail

	if not Title or not DetailLabel then
		return
	end

	for Length = 1, #Text do
		if self.Serial ~= Serial then
			return
		end

		SoundController:Play("TutorialType")
		Title.Text = string.sub(Text, 1, Length)

		task.wait(TypeRate)
	end

	--> the reason arrives whole once the instruction is down: it is read, not watched
	if self.Serial == Serial then
		DetailLabel.Text = Detail
	end

	if not HideAfter then
		return
	end

	task.delay(LingerTime, function()
		if self.Serial == Serial then
			self:Hide()
		end
	end)
end

function Information:_Show(Text: string, Detail: string, HideAfter: boolean?)
	local Group, Title, DetailLabel = self.Group, self.Title, self.Detail

	if not Group or not Title or not DetailLabel then
		return
	end

	self.Serial += 1

	local Serial = self.Serial

	if not Group.Visible then
		Group.GroupTransparency = 1
		Group.Position = self.Away
	end

	Title.Text = ""
	DetailLabel.Text = ""
	Group.Visible = true

	task.spawn(function()
		self:_Typewrite(Text, Detail, Serial, HideAfter)
	end)

	TweenService:Create(Group, FadeTween, { GroupTransparency = 0 }):Play()
	TweenService:Create(Group, SlideTween, { Position = self.Home }):Play()
end

--> Brings the bar in and types a step's line onto it, with its reason under. HideAfter takes it
--> away again on its own once the line has been up for a moment, for a line that is the end of
--> something.
function Information:Display(Text: string, Detail: string?, HideAfter: boolean?)
	--> a line that takes itself away is not one a notice should bring back: kept only while it
	--> is meant to stay, or the finish line would come back with every notice after the tutorial
	self.Text = if HideAfter then "" else Text
	self.DetailText = if HideAfter then "" else Detail or ""

	SoundController:Play("TutorialNotify")

	self:_Show(Text, Detail or "", HideAfter)
end

--> A refusal explained in the bar for a moment, then the step's own line back. Off its own sound,
--> so a purchase being turned down is heard as that and not as the next step arriving.
function Information:Notice(Text: string)
	local Held, HeldDetail = self.Text, self.DetailText

	SoundController:Play("Warning")

	self:_Show(Text, "")

	local Serial = self.Serial

	task.delay(NoticeTime, function()
		if self.Serial ~= Serial then
			return
		end

		if Held == "" then
			self:Hide()
			return
		end

		self:_Show(Held, HeldDetail)
	end)
end

function Information:Hide()
	local Group = self.Group

	if not Group then
		return
	end

	self.Serial += 1
	self.Text = ""
	self.DetailText = ""

	local Serial = self.Serial

	TweenService:Create(Group, FadeTween, { GroupTransparency = 1 }):Play()

	local Slide = TweenService:Create(Group, SlideTween, { Position = self.Away })

	Slide.Completed:Once(function()
		if self.Serial == Serial then
			Group.Visible = false
		end
	end)

	Slide:Play()
end

return Information
