--!strict

-- Contribution is not a fourth architecture object. It is the component-shaped
-- value emitted by Systems and consumed by Rules during one evolution.
local Contribution = {}

export type Data = { [string]: any }

export type Effect = {
	kind: string,
	entity: number?,
	entityToken: string?,
	components: { any }?,
	componentTypes: { any }?,
	componentType: any?,
	field: string?,
	key: any?,
	value: any?,
	valueToken: string?,
	token: string?,
}

export type Value = {
	kind: string,
	source: string,
	phase: number,
	priority: number,
	orderKey: string,
	sequence: number?,
	channel: any?,
	label: string?,
	accepted: boolean?,
	claims: { string }?,
	effects: { Effect }?,
	conflictEffects: { Effect }?,
	[string]: any,
}

local function normalize(kind: string, source: string, data: Data?): Value
	assert(type(kind) == "string" and kind ~= "", "Contribution kind must be a non-empty string")
	assert(type(source) == "string" and source ~= "", "Contribution source must be a non-empty string")
	local value: Data = table.clone(data or {})
	value.kind = kind
	value.source = source
	value.phase = value.phase or 50
	value.priority = value.priority or 0
	value.orderKey = value.orderKey or ""
	return value :: Value
end

-- Custom algebraic effects remain Contribution values. Applications register
-- a pure Rule for every custom kind before a world can evolve.
function Contribution.of(kind: string, source: string, data: Data?): any
	assert(kind ~= "Transaction", "Use Contribution.transaction for Transaction Contributions")
	return normalize(kind, source, data)
end

function Contribution.transaction(source: string, data: Data?): any
	local value = normalize("Transaction", source, data)
	value.claims = value.claims or {}
	value.effects = value.effects or {}
	value.conflictEffects = value.conflictEffects or {}
	return value
end

function Contribution.numeric(source: string, data: Data?): any
	return normalize("Numeric", source, data)
end

function Contribution.performance(source: string, data: Data?): any
	return normalize("Performance", source, data)
end

function Contribution.insert(entity: number, componentInstances: { any }): Effect
	return { kind = "Insert", entity = entity, components = componentInstances }
end

function Contribution.remove(entity: number, componentTypes: { any }): Effect
	return { kind = "Remove", entity = entity, componentTypes = componentTypes }
end

function Contribution.despawn(entity: number): Effect
	return { kind = "Despawn", entity = entity }
end

function Contribution.spawn(componentInstances: { any }, token: string?): Effect
	return { kind = "Spawn", components = componentInstances, token = token }
end

function Contribution.mapSet(entity: number, componentType: any, field: string, key: any, value: any, valueToken: string?): Effect
	return {
		kind = "MapSet",
		entity = entity,
		componentType = componentType,
		field = field,
		key = key,
		value = value,
		valueToken = valueToken,
	}
end

function Contribution.mapRemove(entity: number, componentType: any, field: string, key: any): Effect
	return { kind = "MapRemove", entity = entity, componentType = componentType, field = field, key = key }
end

function Contribution.collectionAdd(entity: number, componentType: any, field: string, value: any, valueToken: string?): Effect
	return {
		kind = "CollectionAdd",
		entity = entity,
		componentType = componentType,
		field = field,
		value = value,
		valueToken = valueToken,
	}
end

function Contribution.collectionRemove(entity: number, componentType: any, field: string, value: any): Effect
	return { kind = "CollectionRemove", entity = entity, componentType = componentType, field = field, value = value }
end

return table.freeze(Contribution)
