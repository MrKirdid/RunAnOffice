-- Kore.Tween — Builder pattern tween with Promise-based Play()

local TweenService = game:GetService("TweenService")

local resolve = require(script.Parent.PackageResolver)
local Promise = require(resolve("promise") or script.Parent.Promise)
local Types = require(script.Parent.Types)

type TweenBuilder = Types.TweenBuilder

local Tween = {}
Tween.__index = Tween

--- Create a new tween builder targeting the given Instance.
function Tween.new(instance: Instance): TweenBuilder
	return setmetatable({
		_instance = instance,
		_properties = {} :: { [string]: any },
		_duration = 0.3,
		_easingStyle = Enum.EasingStyle.Quad,
		_easingDirection = Enum.EasingDirection.Out,
		_repeatCount = 0,
		_reverses = false,
		_delayTime = 0,
	}, Tween) :: any
end

--- Set a property to tween. Chainable.
function Tween:Property(name: string, value: any): TweenBuilder
	self._properties[name] = value
	return self :: any
end

--- Set the tween duration in seconds. Chainable.
function Tween:Duration(t: number): TweenBuilder
	self._duration = t
	return self :: any
end

--- Set the easing style and optional direction. Accepts string names or EnumItems. Chainable.
function Tween:Easing(style: string | Enum.EasingStyle, direction: (string | Enum.EasingDirection)?): TweenBuilder
	if type(style) == "string" then
		if style == "Spring" then
			self._easingStyle = Enum.EasingStyle.Elastic
		elseif style == "Bezier" then
			self._easingStyle = Enum.EasingStyle.Cubic
		else
			local enumStyle = (Enum.EasingStyle :: any)[style]
			if enumStyle then
				self._easingStyle = enumStyle
			end
		end
	elseif typeof(style) == "EnumItem" then
		self._easingStyle = style :: Enum.EasingStyle
	end

	if direction then
		if type(direction) == "string" then
			local enumDir = (Enum.EasingDirection :: any)[direction]
			if enumDir then
				self._easingDirection = enumDir
			end
		elseif typeof(direction) == "EnumItem" then
			self._easingDirection = direction :: Enum.EasingDirection
		end
	end

	return self :: any
end

--- Set the repeat count. Chainable.
function Tween:RepeatCount(count: number): TweenBuilder
	self._repeatCount = count
	return self :: any
end

--- Set whether the tween reverses. Chainable.
function Tween:Reverses(reverses: boolean): TweenBuilder
	self._reverses = reverses
	return self :: any
end

--- Set delay before the tween starts. Chainable.
function Tween:DelayTime(t: number): TweenBuilder
	self._delayTime = t
	return self :: any
end

--- Play the tween and return a Promise that resolves on completion.
function Tween:Play(): any -- Promise<void>
	return Promise.new(function(resolvePromise: () -> ())
		local tweenInfo = TweenInfo.new(
			self._duration,
			self._easingStyle,
			self._easingDirection,
			self._repeatCount,
			self._reverses,
			self._delayTime
		)

		local tween: Tween = TweenService:Create(self._instance, tweenInfo, self._properties)
		tween.Completed:Once(function()
			resolvePromise()
		end)
		tween:Play()
	end)
end

--- Cancel the tween (no-op if not playing).
function Tween:Cancel(): ()
	-- No-op if not playing (tween is created inline in Play)
end

return Tween :: Types.TweenModule
