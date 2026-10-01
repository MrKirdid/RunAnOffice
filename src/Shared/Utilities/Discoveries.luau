--> Which parts a player has ever rolled, for the Index. One entry per part, keyed off the component
--> and the variant together, since a Tree Keyboard and a Tree Computer are two different finds.

local Discoveries = {}

function Discoveries.Key(Component: string, Variant: string): string
	return `{Component}/{Variant}`
end

--> Server only: writes the find into the save. Read first, because most rolls land on something
--> already found and a write that changes nothing still replicates.
function Discoveries.Mark(Data: any, Component: string, Variant: string)
	local Key = Discoveries.Key(Component, Variant)

	if Data.Discovered()[Key] then
		return
	end

	Data.Discovered[Key](true)
end

return Discoveries
