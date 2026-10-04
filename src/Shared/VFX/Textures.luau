--> Texture ids out of the ZonitoVisuals library, each named for what it actually looks like rather
--> than for what the library calls it. Picked by looking at every one in the VFX lab.

local function Id(Number: number): string
	return "rbxassetid://" .. Number
end

return {
	--> radial light rays
	Rays = Id(14049988179),
	--> a four point star with a hot core
	StarGlint = Id(107194701758339),
	--> a soft four point star
	StarSoft = Id(17062453173),
	--> a soft round glow
	Glow = Id(13816054573),
	--> a soft thin ring
	SoftRing = Id(118691169285755),
	--> a crisp glowing ring
	HardRing = Id(16878151803),
	--> a white crescent, 4x4 flipbook
	Slash = Id(132395520838872),
	--> radial spark streaks
	SparkBurst = Id(16892244417),
	--> a thin horizontal streak, for VelocityParallel
	Streak = Id(14197943648),
	--> cloud like smoke
	Smoke = Id(11037787560),
	--> a radial burst crack on the ground
	GroundCrack = Id(87233255893145),
}
