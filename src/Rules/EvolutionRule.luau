--!strict

local ReadRule = require(script.Parent.ReadRule)
local StateUpdateRule = require(script.Parent.StateUpdateRule)

local EvolutionRule = {}
EvolutionRule.__index = EvolutionRule

function EvolutionRule.new(matter, components, configuration)
	assert(configuration.phaseRule ~= nil and type(configuration.phaseRule.phases) == "function", "EvolutionRule requires a PhaseRule")
	assert(configuration.compositionRule ~= nil and type(configuration.compositionRule.compose) == "function", "EvolutionRule requires a CompositionRule")
	local world = matter.World.new()
	local updater = StateUpdateRule.new(world, components)
	updater:initialize(configuration.initial)

	return setmetatable({
		_world = world,
		_updater = updater,
		_phaseRule = configuration.phaseRule,
		_compositionRule = configuration.compositionRule,
		_running = false,
	}, EvolutionRule)
end

function EvolutionRule:view()
	return ReadRule.new(self._world)
end

function EvolutionRule:observe(kind: string, payload): number
	assert(not self._running, "An external observation cannot interrupt an evolution")
	return self._updater:observe(kind, payload)
end

function EvolutionRule:_evolvePhase(phase)
	local readMetrics = {}
	local view = ReadRule.new(self._world, readMetrics)
	local contributions = {}
	local sequence = 0
	local phaseStarted = os.clock()
	local systemProfiles = {}
	local function emit(contribution)
		assert(type(contribution) == "table", "System emitted a non-Contribution value")
		sequence += 1
		local normalized = table.clone(contribution)
		normalized.sequence = sequence
		normalized.phase = normalized.phase or 50
		normalized.priority = normalized.priority or 0
		normalized.orderKey = normalized.orderKey or ""
		table.insert(contributions, normalized)
	end

	for _, system in ipairs(phase.systems) do
		local before = {
			gets = readMetrics.gets,
			contains = readMetrics.contains,
			sizes = readMetrics.sizes,
			queries = readMetrics.queries,
			queryDriverRows = readMetrics.queryDriverRows,
			queryRows = readMetrics.queryRows,
			queryComponentReads = readMetrics.queryComponentReads,
		}
		local started = os.clock()
		debug.profilebegin("ECSR:System:" .. system.name)
		system.evaluate(view, emit)
		debug.profileend()
		systemProfiles[system.name] = {
			ms = (os.clock() - started) * 1000,
			gets = readMetrics.gets - before.gets,
			contains = readMetrics.contains - before.contains,
			sizes = readMetrics.sizes - before.sizes,
			queries = readMetrics.queries - before.queries,
			queryDriverRows = readMetrics.queryDriverRows - before.queryDriverRows,
			queryRows = readMetrics.queryRows - before.queryRows,
			queryComponentReads = readMetrics.queryComponentReads - before.queryComponentReads,
		}
	end

	local compositionStarted = os.clock()
	local totalContribution = self._compositionRule.compose(contributions)
	local compositionMs = (os.clock() - compositionStarted) * 1000
	local updateStarted = os.clock()
	local updateStats, traceRecord = self._updater:apply(totalContribution, phase.name, phase.advanceTick == true)
	local updateMs = (os.clock() - updateStarted) * 1000
	return {
		ms = (os.clock() - phaseStarted) * 1000,
		compositionMs = compositionMs,
		updateMs = updateMs,
		contributions = #contributions,
		resolvedContributions = #totalContribution,
		effects = updateStats.effects,
		stateWrites = updateStats.stateWrites,
		traceEntriesCloned = updateStats.traceEntriesCloned,
		traceEntriesShifted = updateStats.traceEntriesShifted,
		traceRecord = traceRecord,
		systems = systemProfiles,
	}
end

function EvolutionRule:step()
	assert(not self._running, "Evolution Rule cannot be re-entered")
	self._running = true
	local started = os.clock()
	local profile = {
		phases = {},
		systems = {},
		contributions = 0,
		resolvedContributions = 0,
		effects = 0,
		stateWrites = 0,
		queries = 0,
		queryRows = 0,
		traceEntriesCloned = 0,
		traceEntriesShifted = 0,
	}
	local ok, failure = xpcall(function()
		local tracePhases = {}
		for _, phase in ipairs(self._phaseRule.phases()) do
			debug.profilebegin("ECSR:Phase:" .. phase.name)
			local phaseProfile = self:_evolvePhase(phase)
			debug.profileend()
			profile.phases[phase.name] = phaseProfile
			profile.contributions += phaseProfile.contributions
			profile.resolvedContributions += phaseProfile.resolvedContributions
			profile.effects += phaseProfile.effects
			profile.stateWrites += phaseProfile.stateWrites
			profile.traceEntriesCloned += phaseProfile.traceEntriesCloned
			profile.traceEntriesShifted += phaseProfile.traceEntriesShifted
			table.insert(tracePhases, phaseProfile.traceRecord)
			for systemName, systemProfile in pairs(phaseProfile.systems) do
				profile.systems[systemName] = systemProfile
				profile.queries += systemProfile.queries
				profile.queryRows += systemProfile.queryRows
			end
		end
		local traceStats = self._updater:appendTrace(tracePhases)
		profile.stateWrites += traceStats.stateWrites
		profile.traceEntriesCloned += traceStats.traceEntriesCloned
		profile.traceEntriesShifted += traceStats.traceEntriesShifted
	end, debug.traceback)
	self._running = false
	if not ok then
		error(failure, 0)
	end
	profile.totalMs = (os.clock() - started) * 1000
	return profile
end

return table.freeze(EvolutionRule)
