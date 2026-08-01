-- Kore.Promise — Re-export of evaera/promise

local resolve: (packageName: string) -> Instance? = require(script.Parent.PackageResolver)
return require(resolve("promise") or error("[Kore] Promise package not found in Packages"))
