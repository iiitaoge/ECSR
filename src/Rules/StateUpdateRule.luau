--!strict

local ROOT_ENTITY = 1
local REMOVED = table.freeze({})

local StateUpdateRule = {}
StateUpdateRule.__index = StateUpdateRule

local function snapshot(value, seen)
	if type(value) ~= "table" then return value end
	if getmetatable(value) ~= nil then return value end
	seen = seen or {}
	if seen[value] ~= nil then return seen[value] end
	local result = {}
	seen[value] = result
	for key, item in pairs(value) do
		result[snapshot(key, seen)] = snapshot(item, seen)
	end
	return table.freeze(result)
end

local function sortedInsert(values, value)
	for _, existing in ipairs(values) do
		if existing == value then return end
	end
	table.insert(values, value)
	table.sort(values, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
end

function StateUpdateRule.new(world, components)
	for _, name in ipairs({ "StateRoot", "EvolutionTrace", "ObservationJournal", "Observation" }) do
		assert(components[name] ~= nil, string.format("ECSR protocol Component %s is missing", name))
	end
	local knownComponentTypes = {}
	for _, componentType in pairs(components) do
		knownComponentTypes[componentType] = true
	end
	return setmetatable({
		world = world,
		components = components,
		knownComponentTypes = knownComponentTypes,
	}, StateUpdateRule)
end

function StateUpdateRule:_assertComponentType(componentType, context: string)
	assert(self.knownComponentTypes[componentType] == true, string.format("%s references an unknown Component type", context))
	assert(componentType ~= self.components.StateRoot, "StateRoot is owned exclusively by StateUpdateRule")
end

function StateUpdateRule:_validateInstances(componentInstances, context: string, allowStateRoot: boolean?)
	assert(type(componentInstances) == "table" and #componentInstances > 0, string.format("%s needs Component instances", context))
	local seen = {}
	for index, componentInstance in ipairs(componentInstances) do
		local componentType = getmetatable(componentInstance)
		assert(self.knownComponentTypes[componentType] == true, string.format("%s Component %d is not registered", context, index))
		if not allowStateRoot then
			assert(componentType ~= self.components.StateRoot, "StateRoot is owned exclusively by StateUpdateRule")
		end
		assert(not seen[componentType], string.format("%s contains a duplicate Component type", context))
		seen[componentType] = true
	end
end

function StateUpdateRule:initialize(initial)
	assert(type(initial) == "table", "Initial world must be Component data")
	local initialEntities = initial.entities or {}
	local rootComponents = {
		self.components.StateRoot({ nextEntityId = ROOT_ENTITY + 1 + #initialEntities, tick = 0 }),
	}
	for _, componentInstance in ipairs(initial.root or {}) do
		table.insert(rootComponents, componentInstance)
	end

	-- Validate the complete genesis state before the first Matter write.
	self:_validateInstances(rootComponents, "Initial root", true)
	for entityIndex, entityComponents in ipairs(initialEntities) do
		self:_validateInstances(entityComponents, string.format("Initial entity %d", entityIndex), false)
	end

	self.world:spawnAt(ROOT_ENTITY, table.unpack(rootComponents))
	for entityIndex, entityComponents in ipairs(initialEntities) do
		self.world:spawnAt(ROOT_ENTITY + entityIndex, table.unpack(entityComponents))
	end
	self.world:optimizeQueries()
end

local function traceRecord(resolved)
	local effectKinds = {}
	for _, effect in ipairs(resolved.effects or {}) do
		table.insert(effectKinds, effect.kind)
	end
	return {
		source = resolved.source,
		label = resolved.label,
		accepted = resolved.accepted,
		conflict = resolved.conflict,
		claims = table.clone(resolved.claims or {}),
		effects = effectKinds,
	}
end

-- Preflight simulates every effect against an overlay. No Matter write occurs
-- until all targets, Components, tokens and sequential dependencies are valid.
function StateUpdateRule:_preflight(resolvedContributions)
	assert(type(resolvedContributions) == "table", "State Update needs resolved Contributions")
	local root = assert(self.world:get(ROOT_ENTITY, self.components.StateRoot), "StateRoot Component is missing")
	local nextEntityId = root.nextEntityId
	local tokens = {}
	local alive = {}
	local overlay = {}
	local prepared = {}

	local function isAlive(entityId: number): boolean
		if alive[entityId] ~= nil then return alive[entityId] end
		return self.world:contains(entityId)
	end

	local function setComponent(entityId: number, componentType, value)
		local entityOverlay = overlay[entityId]
		if entityOverlay == nil then
			entityOverlay = {}
			overlay[entityId] = entityOverlay
		end
		entityOverlay[componentType] = value
	end

	local function getComponent(entityId: number, componentType)
		local entityOverlay = overlay[entityId]
		if entityOverlay ~= nil and entityOverlay[componentType] ~= nil then
			local value = entityOverlay[componentType]
			return if value == REMOVED then nil else value
		end
		return self.world:get(entityId, componentType)
	end

	local function resolveEntity(effect): number
		if effect.entityToken ~= nil then
			local tokenEntity = tokens[effect.entityToken]
			assert(tokenEntity ~= nil, string.format("Unknown State Update entity token %s", tostring(effect.entityToken)))
			return tokenEntity
		end
		assert(type(effect.entity) == "number", string.format("Effect %s needs an Entity ID", tostring(effect.kind)))
		return effect.entity
	end

	local function resolveValue(effect)
		if effect.valueToken ~= nil then
			local tokenValue = tokens[effect.valueToken]
			assert(tokenValue ~= nil, string.format("Unknown State Update value token %s", tostring(effect.valueToken)))
			return tokenValue
		end
		return effect.value
	end

	for _, resolved in ipairs(resolvedContributions) do
		assert(type(resolved) == "table" and resolved.kind == "Resolved", "State Update accepts only Rule-resolved Contributions")
		for _, effect in ipairs(resolved.effects or {}) do
			assert(type(effect) == "table" and type(effect.kind) == "string", "Resolved Contribution contains an invalid Effect")
			local kind = effect.kind
			if kind == "Spawn" then
				self:_validateInstances(effect.components, "Spawn Effect", false)
				local entityId = nextEntityId
				nextEntityId += 1
				assert(not isAlive(entityId), string.format("Allocated Entity ID %d already exists", entityId))
				alive[entityId] = true
				for _, componentInstance in ipairs(effect.components) do
					setComponent(entityId, getmetatable(componentInstance), componentInstance)
				end
				if effect.token ~= nil then
					assert(type(effect.token) == "string" and effect.token ~= "", "Spawn token must be a non-empty string")
					assert(tokens[effect.token] == nil, string.format("Duplicate State Update token %s", effect.token))
					tokens[effect.token] = entityId
				end
				table.insert(prepared, { kind = kind, entity = entityId, components = effect.components })
			elseif kind == "Insert" then
				local entityId = resolveEntity(effect)
				assert(isAlive(entityId), string.format("Insert target Entity %d does not exist", entityId))
				self:_validateInstances(effect.components, "Insert Effect", false)
				for _, componentInstance in ipairs(effect.components) do
					setComponent(entityId, getmetatable(componentInstance), componentInstance)
				end
				table.insert(prepared, { kind = kind, entity = entityId, components = effect.components })
			elseif kind == "Remove" then
				local entityId = resolveEntity(effect)
				assert(isAlive(entityId), string.format("Remove target Entity %d does not exist", entityId))
				assert(type(effect.componentTypes) == "table" and #effect.componentTypes > 0, "Remove Effect needs Component types")
				for _, componentType in ipairs(effect.componentTypes) do
					self:_assertComponentType(componentType, "Remove Effect")
					setComponent(entityId, componentType, REMOVED)
				end
				table.insert(prepared, { kind = kind, entity = entityId, componentTypes = effect.componentTypes })
			elseif kind == "Despawn" then
				local entityId = resolveEntity(effect)
				assert(entityId ~= ROOT_ENTITY, "StateRoot Entity cannot be despawned")
				assert(isAlive(entityId), string.format("Despawn target Entity %d does not exist", entityId))
				alive[entityId] = false
				table.insert(prepared, { kind = kind, entity = entityId })
			elseif kind == "MapSet" or kind == "MapRemove" or kind == "CollectionAdd" or kind == "CollectionRemove" then
				local entityId = resolveEntity(effect)
				assert(isAlive(entityId), string.format("%s target Entity %d does not exist", kind, entityId))
				self:_assertComponentType(effect.componentType, kind .. " Effect")
				assert(type(effect.field) == "string" and effect.field ~= "", kind .. " Effect needs a field")
				local componentInstance = getComponent(entityId, effect.componentType)
				assert(componentInstance ~= nil, string.format("%s target Component is missing on Entity %d", kind, entityId))
				local values = table.clone(componentInstance[effect.field] or {})
				if kind == "MapSet" then
					assert(effect.key ~= nil, "MapSet Effect needs a key")
					values[effect.key] = resolveValue(effect)
				elseif kind == "MapRemove" then
					assert(effect.key ~= nil, "MapRemove Effect needs a key")
					values[effect.key] = nil
				else
					local value = resolveValue(effect)
					assert(value ~= nil, kind .. " Effect needs a value")
					if kind == "CollectionAdd" then
						sortedInsert(values, value)
					else
						local position = table.find(values, value)
						if position ~= nil then table.remove(values, position) end
					end
				end
				local componentPatch = {}
				componentPatch[effect.field] = values
				local nextComponent = componentInstance:patch(componentPatch)
				setComponent(entityId, effect.componentType, nextComponent)
				table.insert(prepared, { kind = kind, entity = entityId, component = nextComponent })
			else
				error(string.format("State Update Rule cannot apply Effect %s", tostring(kind)))
			end
		end
	end

	return prepared, tokens, nextEntityId
end

function StateUpdateRule:apply(resolvedContributions, phaseName: string, advanceTick: boolean, optimizeStorage: boolean?)
	local prepared, tokens, nextEntityId = self:_preflight(resolvedContributions)
	local stats = {
		effects = #prepared,
		inserts = 0,
		removes = 0,
		spawns = 0,
		despawns = 0,
		stateWrites = 0,
		traceEntriesCloned = 0,
		traceEntriesShifted = 0,
	}
	local records = {}

	-- All fallible semantic validation is complete. This is the sole commit path.
	for _, effect in ipairs(prepared) do
		if effect.kind == "Spawn" then
			self.world:spawnAt(effect.entity, table.unpack(effect.components))
			stats.spawns += 1
			stats.stateWrites += 1
		elseif effect.kind == "Insert" then
			self.world:insert(effect.entity, table.unpack(effect.components))
			stats.inserts += 1
			stats.stateWrites += 1
		elseif effect.kind == "Remove" then
			self.world:remove(effect.entity, table.unpack(effect.componentTypes))
			stats.removes += 1
			stats.stateWrites += 1
		elseif effect.kind == "Despawn" then
			self.world:despawn(effect.entity)
			stats.despawns += 1
			stats.stateWrites += 1
		else
			self.world:insert(effect.entity, effect.component)
			stats.inserts += 1
			stats.stateWrites += 1
		end
	end

	local root = assert(self.world:get(ROOT_ENTITY, self.components.StateRoot), "StateRoot Component is missing after State Update")
	local nextTick = if advanceTick then root.tick + 1 else root.tick
	if nextEntityId ~= root.nextEntityId or nextTick ~= root.tick then
		self.world:insert(ROOT_ENTITY, root:patch({ nextEntityId = nextEntityId, tick = nextTick }))
		stats.inserts += 1
		stats.stateWrites += 1
	end
	for _, resolved in ipairs(resolvedContributions) do
		table.insert(records, traceRecord(resolved))
	end
	if optimizeStorage ~= false then self.world:optimizeQueries() end
	return stats, { phase = phaseName, resolved = records }, tokens
end

function StateUpdateRule:observe(kind: string, payload): number
	assert(type(kind) == "string" and kind ~= "", "Observation kind must be a non-empty string")
	local journal = self.world:get(ROOT_ENTITY, self.components.ObservationJournal)
	local sequence = if journal ~= nil then journal.nextSequence else 1
	local maxEntries = if journal ~= nil then journal.maxEntries or 128 else 128
	local entries = table.clone(if journal ~= nil then journal.entries else {})
	local root = assert(self.world:get(ROOT_ENTITY, self.components.StateRoot), "StateRoot Component is missing")
	local frozenPayload = snapshot(payload or {})
	table.insert(entries, table.freeze({
		sequence = sequence,
		entity = root.nextEntityId,
		kind = kind,
		payload = frozenPayload,
	}))
	while #entries > maxEntries do table.remove(entries, 1) end

	local token = "observation:" .. tostring(sequence)
	local _, _, tokens = self:apply({
		{
			kind = "Resolved",
			source = "ObservationIngressRule",
			label = "Observe<" .. kind .. ">",
			accepted = true,
			conflict = false,
			claims = {},
			effects = {
				{ kind = "Insert", entity = ROOT_ENTITY, components = {
					self.components.ObservationJournal({
						nextSequence = sequence + 1,
						entries = entries,
						maxEntries = maxEntries,
					}),
				} },
				{ kind = "Spawn", token = token, components = {
					self.components.Observation({ sequence = sequence, kind = kind, payload = frozenPayload }),
				} },
			},
		},
	}, "observation", false, false)
	return assert(tokens[token], "Observation Entity was not allocated")
end

function StateUpdateRule:appendTrace(phases)
	local oldTrace = self.world:get(ROOT_ENTITY, self.components.EvolutionTrace)
	local entries = table.clone(if oldTrace ~= nil then oldTrace.entries else {})
	local cloned = #entries
	local root = assert(self.world:get(ROOT_ENTITY, self.components.StateRoot), "StateRoot Component is missing")
	table.insert(entries, { tick = root.tick, phases = phases })
	local maxEntries = if oldTrace ~= nil then oldTrace.maxEntries or 64 else 64
	local shifted = 0
	while #entries > maxEntries do
		table.remove(entries, 1)
		shifted += 1
	end
	local applyStats = self:apply({
		{
			kind = "Resolved",
			source = "EvolutionTraceRule",
			label = "AppendEvolutionTrace",
			accepted = true,
			conflict = false,
			claims = {},
			effects = {
				{ kind = "Insert", entity = ROOT_ENTITY, components = {
					self.components.EvolutionTrace({ entries = entries, maxEntries = maxEntries }),
				} },
			},
		},
	}, "trace", false, false)
	return {
		stateWrites = applyStats.stateWrites,
		traceEntriesCloned = cloned,
		traceEntriesShifted = shifted,
	}
end

return table.freeze(StateUpdateRule)
