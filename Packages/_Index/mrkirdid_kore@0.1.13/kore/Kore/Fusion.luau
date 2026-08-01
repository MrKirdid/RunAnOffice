-- Kore.Fusion — Re-export of elttob/fusion

local resolve: (packageName: string) -> Instance? = require(script.Parent.PackageResolver)

local ok: boolean, Fusion: any = pcall(function(): any
	return require(resolve("fusion") or error("not found"))
end)

if ok then
	return Fusion
end

warn("[Kore] Fusion package not found in Packages — Kore.Fusion will not be available")
return nil
