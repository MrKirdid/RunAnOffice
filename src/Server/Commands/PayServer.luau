local Server = script.Parent.Parent

local RevenueService = require(Server.Services.RevenueService)

local Maximum = 3600

return function(_Context, Ticks: number): string
	if Ticks < 1 or Ticks > Maximum then
		return `Ticks have to be between 1 and {Maximum}.`
	end

	for _ = 1, Ticks do
		RevenueService:Pay()
	end

	return `Paid out {Ticks} tick` .. (if Ticks == 1 then "." else "s.")
end
