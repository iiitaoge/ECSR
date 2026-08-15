--!strict

-- Contribution is not a fourth architecture object. It is the component-shaped
-- value emitted by Systems and consumed by Rules during one evolution.
local Contribution = {}

local function normalize(kind: string, source: string, data)
	assert(type(kind) == "string" and kind ~= "", "Contribution kind must be a non-empty string")
	assert(type(source) == "string" and source ~= "", "Contribution source must be a non-empty string")
	local value = table.clone(data or {})
	value.kind = kind
	value.source = source
	value.phase = value.phase or 50
	value.priority = value.priority or 0
	value.orderKey = value.orderKey or ""
	return value
end

-- Custom algebraic effects remain Contribution values. Applications register
-- a pure Rule for every custom kind before a world can evolve.
function Contribution.of(kind: string, source: string, data)
	assert(kind ~= "Transaction", "Use Contribution.transaction for Transaction Contributions")
	return normalize(kind, source, data)
end

function Contribution.transaction(source: string, data)
	local value = normalize("Transaction", source, data)
	value.claims = value.claims or {}
	value.effects = value.effects or {}
	value.conflictEffects = value.conflictEffects or {}
	return value
end

function Contribution.numeric(source: string, data)
	return normalize("Numeric", source, data)
end

function Contribution.performance(source: string, data)
	return normalize("Performance", source, data)
end

function Contribution.insert(entity: number, componentInstances)
	return { kind = "Insert", entity = entity, components = componentInstances }
end

function Contribution.remove(entity: number, componentTypes)
	return { kind = "Remove", entity = entity, componentTypes = componentTypes }
end

function Contribution.despawn(entity: number)
	return { kind = "Despawn", entity = entity }
end

function Contribution.spawn(componentInstances, token: string?)
	return { kind = "Spawn", components = componentInstances, token = token }
end

function Contribution.mapSet(entity: number, componentType, field: string, key, value, valueToken: string?)
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

function Contribution.mapRemove(entity: number, componentType, field: string, key)
	return { kind = "MapRemove", entity = entity, componentType = componentType, field = field, key = key }
end

function Contribution.collectionAdd(entity: number, componentType, field: string, value, valueToken: string?)
	return {
		kind = "CollectionAdd",
		entity = entity,
		componentType = componentType,
		field = field,
		value = value,
		valueToken = valueToken,
	}
end

function Contribution.collectionRemove(entity: number, componentType, field: string, value)
	return { kind = "CollectionRemove", entity = entity, componentType = componentType, field = field, value = value }
end

return table.freeze(Contribution)
