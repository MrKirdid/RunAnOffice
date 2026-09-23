local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Renders = require(Shared.Configs.Renders)

--> PreloadAsync fetches an image. It does not decode one: that happens the first time the engine
--> actually has to draw it, and until then the first frame it appears on hitches however early the
--> fetch was. An ImageLabel sat in a Folder -- which is how the renders were being preloaded --
--> never draws at all, so it never decodes.

--> So every image is drawn once, deliberately, on a screen of its own: one pixel each, behind
--> everything, for a couple of frames. A pixel is enough because decoding is per image rather than
--> per pixel, and one pixel in the corner is not something anybody sees. Decals on a part in the
--> world would do the same job, but only while the camera happens to be pointed at them, and they
--> are visible when it is.

local GuiName = "UIPreload"

--> big enough to be drawn, small enough to be nothing
local PixelSize = UDim2.fromOffset(1, 1)

--> a couple of frames on screen, which is all a decode needs
local DrawFrames = 3

--> nothing sane reaches this. it is here so a config that grows by an order of magnitude cannot
--> quietly turn startup into a stall
local MaxImages = 400

--> how long new art is collected for before it is drawn, so a screen filling itself in one frame is
--> one batch rather than thirty
local Debounce = 0.3

local UIPreloadController = {
	Loaded = false,

	--> every id already drawn once. the shop restocks from data long after the first pass, and the
	--> only thing that separates art that has been decoded from art that has not is this
	Seen = {} :: { [string]: boolean },
	Queue = {} :: { string },
	Draining = false,
}

local function IsImage(Value: string?): boolean
	return Value ~= nil and Value ~= ""
end

--> Decals and Textures as well: the same picture used in the world and in a card decodes once.
local function ImageOf(Object: Instance): string?
	if Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
		return Object.Image
	end

	if Object:IsA("Decal") or Object:IsA("Texture") then
		return Object.Texture
	end

	return nil
end

--> Queued rather than drawn on the spot, so a screen that fills itself in one frame is one batch.
function UIPreloadController:Add(Image: string?)
	if not IsImage(Image) or self.Seen[Image :: string] then
		return
	end

	self.Seen[Image :: string] = true
	table.insert(self.Queue, Image :: string)
end

--> Everything the interface will ask for: what the place already holds, the templates it builds
--> screens out of, and the part renders, which are drawn into the roll and pickup cards rather than
--> into the world.
function UIPreloadController:Collect()
	local Roots = {
		Players.LocalPlayer:FindFirstChild("PlayerGui"),
		ReplicatedStorage:FindFirstChild("Assets"),
		game:GetService("StarterGui"),
	}

	for _, Root in Roots do
		if not Root then
			continue
		end

		for _, Descendant in (Root :: Instance):GetDescendants() do
			self:Add(ImageOf(Descendant))
		end
	end

	for _, Components in Renders.Components do
		for _, AssetId in Components do
			self:Add(AssetId)
		end
	end
end

--> A card keeps its instance and swaps the picture on it, which is how the shop fills its shelves.
--> Watching the property is the only way to hear about that.
function UIPreloadController:Watch(Object: Instance)
	local Property = if Object:IsA("ImageLabel") or Object:IsA("ImageButton")
		then "Image"
		elseif Object:IsA("Decal") or Object:IsA("Texture") then "Texture"
		else nil

	if not Property then
		return
	end

	Object:GetPropertyChangedSignal(Property):Connect(function()
		self:Add(ImageOf(Object))
		self:Drain()
	end)
end

function UIPreloadController:Draw(Images: { string }): ScreenGui
	local Gui = Instance.new("ScreenGui")
	Gui.Name = GuiName
	Gui.ResetOnSpawn = false
	Gui.IgnoreGuiInset = true

	--> under every real screen, so it can never be the thing a press lands on
	Gui.DisplayOrder = -1000

	for Index, Image in Images do
		local Label = Instance.new("ImageLabel")
		Label.Name = "Preload" .. Index
		Label.BackgroundTransparency = 1
		Label.Size = PixelSize
		Label.Position = UDim2.fromOffset(Index % 100, math.floor(Index / 100))
		Label.Image = Image
		Label.Parent = Gui
	end

	Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	return Gui
end

--> Everything queued, drawn once, thrown away. Anything queued while this is running is picked up
--> by the pass that follows it rather than starting a second one alongside.
function UIPreloadController:Drain()
	if self.Draining then
		return
	end

	self.Draining = true

	task.spawn(function()
		while #self.Queue > 0 do
			task.wait(Debounce)

			local Batch = self.Queue

			self.Queue = {}

			if #Batch > MaxImages then
				warn(`[UIPreload] {#Batch} images at once is more than the {MaxImages} expected`)
			end

			local Gui = self:Draw(Batch)

			--> the fetch, which is the part PreloadAsync is actually good for
			ContentProvider:PreloadAsync(Gui:GetChildren())

			for _ = 1, DrawFrames do
				RunService.RenderStepped:Wait()
			end

			Gui:Destroy()

			self.Loaded = true

			--> on the player rather than kept to this module, so anything that wants to hold a
			--> screen back until its art is ready can ask without requiring the controller
			local Total = 0

			for _ in self.Seen do
				Total += 1
			end

			Players.LocalPlayer:SetAttribute("UIPreloaded", Total)
		end

		self.Draining = false
	end)
end

--> Start rather than Init: by the time this runs the tree has built its nodes, so their art is in
--> the PlayerGui to be found along with everything the place shipped.
function UIPreloadController:Start()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	self:Collect()
	self:Drain()

	--> The first pass only sees what exists at startup. The shop restocks from saved data, screens
	--> are cloned again on respawn, and a card can swap its own picture -- all of it arrives later,
	--> and art that arrives later is exactly the art that hitches when it is first drawn.
	PlayerGui.DescendantAdded:Connect(function(Descendant: Instance)
		if ImageOf(Descendant) == nil then
			return
		end

		self:Add(ImageOf(Descendant))
		self:Watch(Descendant)
		self:Drain()
	end)

	for _, Descendant in PlayerGui:GetDescendants() do
		self:Watch(Descendant)
	end
end

return UIPreloadController
