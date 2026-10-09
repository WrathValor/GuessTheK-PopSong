export type UIMode = "Gameplay" | "Menu"

export type ControllerState = "Inactive" | "Activating" | "Active" | "Deactivating"

export type Controller = {
	Name: string,
	Exclusive: boolean,
	State: ControllerState,
	Initialize: (self: Controller, interface: any) -> (),
	Activate: (self: Controller, ...any) -> any,
	Deactivate: (self: Controller) -> any,
	Destroy: ((self: Controller) -> ())?,
	[any]: any,
}

export type ControllerConfig = {
	Name: string,
	ScreenGui: string,
	Frame: string,
	Exclusive: boolean?,
}

return {}
