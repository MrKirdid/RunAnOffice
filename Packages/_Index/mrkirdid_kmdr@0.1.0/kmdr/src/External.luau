--!strict
--[[
	External.luau — dependency resolution. Wally places dependency link
	modules as siblings of the package root in both layouts we care about:
	  - installed: Packages/_Index/mrkirdid_kmdr@x.y.z/{Kmdr, Fusion}
	  - dev place: ReplicatedStorage/Packages/{Kmdr, Fusion}
	so `script.Parent.Parent.Fusion` resolves in both.

	Types must be re-exported here explicitly — type namespaces do not flow
	through table fields.
]]

local Fusion = require(script.Parent.Parent.Fusion)

export type Scope = Fusion.Scope<typeof(Fusion)>
export type UsedAs<T> = Fusion.UsedAs<T>
export type Value<T> = Fusion.Value<T>
export type Computed<T> = Fusion.Computed<T>
export type Spring<T> = Fusion.Spring<T>
export type Tween<T> = Fusion.Tween<T>
export type Child = Fusion.Child

return {
	Fusion = Fusion,
}
