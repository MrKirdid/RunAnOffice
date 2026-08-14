return {
	Desk = {
		Monitor = CFrame.new(0.389, 2.561, 0.229),
		Computer = CFrame.new(-0.357, 2.584, -2.758),
		Keyboard = CFrame.new(-0.95, 1.291, 0.275) * CFrame.Angles(0, math.rad(180), 0),
	},

	--> Seated in the desk's chair, facing the monitor. Lands on the rig's root, which is the
	--> model pivot only because the rigs have their PivotOffset cleared.
	Employee = CFrame.new(-3.432, 1.5223, 0.2117) * CFrame.Angles(0, math.rad(-90), 0),
}
