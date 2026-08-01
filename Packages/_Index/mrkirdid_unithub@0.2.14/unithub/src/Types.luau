--!strict

export type LifecycleState =
	"Discovered"
	| "Required"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "Failed"
	| "Skipped"
	| "Destroyed"

export type RuntimeKind = "Service" | "Controller"

export type Unit = {
	Name: string?,
	Priority: number?,
	Enabled: boolean?,
	Init: ((self: any, hub: any) -> any)?,
	Start: ((self: any, hub: any) -> any)?,
	Destroy: ((self: any) -> any)?,
	Prepare: ((self: any, hub: any) -> any)?,
	Activate: ((self: any, hub: any) -> any)?,
	[string]: any,
}

export type Service = Unit
export type Controller = Unit

export type Exclusion = string | Instance

export type FolderOptions = {
	Kind: RuntimeKind?,
	Watch: boolean?,
	Recursive: boolean?,
	StrictDuplicates: boolean?,
}

export type PreloadProgress = {
	phase: string,
	completed: number,
	total: number,
	alpha: number,
	assetId: string?,
	status: Enum.AssetFetchStatus?,
	successes: number,
	failures: number,
	message: string?,
}

export type PreloadResult = {
	total: number,
	completed: number,
	successes: number,
	failures: number,
	failedAssets: { [string]: string },
	duration: number,
	timedOut: boolean,
}

export type PreloadConfig = boolean | {
	CriticalRoots: { Instance }?,
	BackgroundRoots: { Instance }?,
	CriticalTags: { string }?,
	BackgroundTags: { string }?,
	IgnoreTags: { string }?,
	ExplicitCriticalAssets: { string }?,
	ExplicitBackgroundAssets: { string }?,
	ChunkSize: number?,
	BackgroundChunkSize: number?,
	YieldBetweenChunks: number?,
	CriticalTimeout: number?,
	UIImageWarmupTimeout: number?,
	WarmupUIImages: boolean?,
	Debug: boolean?,
	Aggressive: boolean?,
	OnProgress: ((PreloadProgress) -> ())?,
}

export type ParallelConfig = {
	Name: string?,
	Parent: Instance?,
	WorkerCount: number?,
	Timeout: number?,
	MaxInFlightPerWorker: number?,
}

export type ParallelDispatchOptions = {
	Timeout: number?,
}

export type ParallelWorkerContext = {
	TaskId: number,
	WorkerId: number,
	Actor: Actor,
	Synchronize: () -> (),
	Desynchronize: () -> (),
	GetSharedTable: (name: string, initial: any?) -> any,
}

export type ParallelStats = {
	Name: string,
	WorkerCount: number,
	ReadyWorkers: number,
	Queued: number,
	InFlight: number,
	Completed: number,
	Failed: number,
	TimedOut: number,
	Destroyed: boolean,
}

export type ParallelDispatcher = {
	Dispatch: (
		self: ParallelDispatcher,
		moduleScript: ModuleScript,
		methodName: string,
		payload: any?,
		options: ParallelDispatchOptions?
	) -> any,
	Run: (
		self: ParallelDispatcher,
		moduleScript: ModuleScript,
		payload: any?,
		options: ParallelDispatchOptions?
	) -> any,
	Map: (
		self: ParallelDispatcher,
		moduleScript: ModuleScript,
		methodName: string,
		payloads: { any },
		options: ParallelDispatchOptions?
	) -> any,
	GetStats: (self: ParallelDispatcher) -> ParallelStats,
	Destroy: (self: ParallelDispatcher) -> (),
}

export type InitConfig = {
	Services: { Instance }?,
	services: { Instance }?,
	Controllers: { Instance }?,
	controllers: { Instance }?,
	Preload: PreloadConfig?,
	preload: PreloadConfig?,
	ExcludedUnits: { Exclusion }?,
	excludedUnits: { Exclusion }?,
	ExcludedServices: { Exclusion }?,
	excludedServices: { Exclusion }?,
	ExcludedControllers: { Exclusion }?,
	excludedControllers: { Exclusion }?,
	Timeout: number?,
	timeout: number?,
	RequireTimeout: number?,
	LifecycleTimeout: number?,
	Watch: boolean?,
	Debug: boolean?,
	StrictDuplicates: boolean?,
}

export type UnitRecordStatus = {
	Name: string,
	Kind: RuntimeKind,
	State: LifecycleState,
	Module: ModuleScript?,
	Source: Instance?,
	Error: string?,
	TimedOut: boolean,
	Duration: number?,
	Priority: number,
}

export type Hub = {
	Init: (self: Hub, config: InitConfig?) -> Hub,
	init: (self: Hub, config: InitConfig?) -> Hub,
	Start: (self: Hub) -> Hub,
	start: (self: Hub) -> Hub,
	Destroy: (self: Hub) -> (),
	destroy: (self: Hub) -> (),
	AddFolder: (self: Hub, folder: Instance, options: FolderOptions?) -> Hub,
	addFolder: (self: Hub, folder: Instance, options: FolderOptions?) -> Hub,
	AddServiceFolder: (self: Hub, folder: Instance, options: FolderOptions?) -> Hub,
	addServiceFolder: (self: Hub, folder: Instance, options: FolderOptions?) -> Hub,
	AddControllerFolder: (self: Hub, folder: Instance, options: FolderOptions?) -> Hub,
	addControllerFolder: (self: Hub, folder: Instance, options: FolderOptions?) -> Hub,
	AddUnit: (self: Hub, moduleScript: ModuleScript, kind: RuntimeKind?) -> any,
	addUnit: (self: Hub, moduleScript: ModuleScript, kind: RuntimeKind?) -> any,
	Add: (self: Hub, moduleScript: ModuleScript, kind: RuntimeKind?) -> any,
	add: (self: Hub, moduleScript: ModuleScript, kind: RuntimeKind?) -> any,
	Get: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	get: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	GetUnit: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	getUnit: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	GetService: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	getService: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	GetController: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	getController: (self: Hub, nameOrModule: string | ModuleScript) -> any,
	WaitForService: (self: Hub, nameOrModule: string | ModuleScript, timeout: number?) -> any?,
	waitForService: (self: Hub, nameOrModule: string | ModuleScript, timeout: number?) -> any?,
	WaitForController: (self: Hub, nameOrModule: string | ModuleScript, timeout: number?) -> any?,
	waitForController: (self: Hub, nameOrModule: string | ModuleScript, timeout: number?) -> any?,
	CheckService: (self: Hub, nameOrModule: string | ModuleScript) -> boolean,
	checkService: (self: Hub, nameOrModule: string | ModuleScript) -> boolean,
	CheckController: (self: Hub, nameOrModule: string | ModuleScript) -> boolean,
	checkController: (self: Hub, nameOrModule: string | ModuleScript) -> boolean,
	GetStatus: (self: Hub, nameOrModule: string | ModuleScript) -> UnitRecordStatus?,
	getStatus: (self: Hub, nameOrModule: string | ModuleScript) -> UnitRecordStatus?,
	GetFailures: (self: Hub) -> { UnitRecordStatus },
	getFailures: (self: Hub) -> { UnitRecordStatus },
	CreateDispatcher: (self: Hub, config: ParallelConfig?) -> ParallelDispatcher,
	createDispatcher: (self: Hub, config: ParallelConfig?) -> ParallelDispatcher,
	GetDispatcher: (self: Hub, name: string?) -> ParallelDispatcher,
	getDispatcher: (self: Hub, name: string?) -> ParallelDispatcher,
	RunParallel: (
		self: Hub,
		moduleScript: ModuleScript,
		payload: any?,
		options: ParallelDispatchOptions?
	) -> any,
	runParallel: (
		self: Hub,
		moduleScript: ModuleScript,
		payload: any?,
		options: ParallelDispatchOptions?
	) -> any,
	DispatchParallel: (
		self: Hub,
		moduleScript: ModuleScript,
		methodName: string,
		payload: any?,
		options: ParallelDispatchOptions?
	) -> any,
	dispatchParallel: (
		self: Hub,
		moduleScript: ModuleScript,
		methodName: string,
		payload: any?,
		options: ParallelDispatchOptions?
	) -> any,
	MapParallel: (
		self: Hub,
		moduleScript: ModuleScript,
		methodName: string,
		payloads: { any },
		options: ParallelDispatchOptions?
	) -> any,
	mapParallel: (
		self: Hub,
		moduleScript: ModuleScript,
		methodName: string,
		payloads: { any },
		options: ParallelDispatchOptions?
	) -> any,
	GetSharedTable: (self: Hub, name: string, initial: any?) -> any,
	getSharedTable: (self: Hub, name: string, initial: any?) -> any,
	EngageUnits: (self: Hub) -> Hub,
	Prepare: (self: Hub, config: InitConfig?) -> Hub,
	Activate: (self: Hub) -> Hub,
}

return {}
