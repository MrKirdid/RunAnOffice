local Maximum = 3600

return {
	Name = "pay",
	Description = "Runs the revenue tick by hand instead of waiting for it, for everyone on the "
		.. "server. Ticks is how many seconds of payout to hand out at once, so 'pay 60' is a minute "
		.. "of idle income without idling.",
	Group = "Admin",
	Args = {
		{
			Type = "integer",
			Name = "Ticks",
			Description = `How many payouts to run, 1 to {Maximum}`,
			Default = 1,
		},
	},
}
