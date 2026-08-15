--!strict

local Contribution = require(script.Parent.Parent.Components.Contribution)
local StableRule = require(script.Parent.StableRule)

local PerformanceRule = {}
PerformanceRule.kind = "Performance"

local function cloneMap(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end

local function cloneNestedStats(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = cloneMap(value) end
	return result
end

local function emptyHistogram(bounds)
	local result = {}
	for index = 1, #bounds do result[index] = 0 end
	return result
end

local function cloneHistogram(source, bounds)
	local result = emptyHistogram(bounds)
	for index = 1, #result do result[index] = source and source[index] or 0 end
	return result
end

local function emptyAccumulator(definition, carry)
	carry = carry or {}
	return {
		elapsedSeconds = 0,
		frameSamples = 0,
		frameTotalMs = 0,
		frameMaxMs = 0,
		frameHistogram = emptyHistogram(definition.histogramBounds),
		hitchCount = 0,
		severeHitchCount = 0,
		freezeCount = 0,
		workSamples = 0,
		workTotalMs = 0,
		workMaxMs = 0,
		workHistogram = emptyHistogram(definition.histogramBounds),
		evolutionTotalMs = 0,
		actuationTotalMs = 0,
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
		heapFirstKb = carry.heapLastKb,
		heapLastKb = carry.heapLastKb,
		heapMinKb = carry.heapLastKb,
		heapMaxKb = carry.heapLastKb,
		gcSuspectCount = 0,
		gcFreedKb = 0,
		gcAssociatedHitches = 0,
		cardinality = cloneMap(carry.cardinality),
		cardinalityCountdown = carry.cardinalityCountdown or 0,
	}
end

local function normalizeAccumulator(definition, source)
	local result = emptyAccumulator(definition, source or {})
	for key, value in pairs(source or {}) do result[key] = value end
	result.frameHistogram = cloneHistogram(source and source.frameHistogram, definition.histogramBounds)
	result.workHistogram = cloneHistogram(source and source.workHistogram, definition.histogramBounds)
	result.phases = cloneNestedStats(source and source.phases)
	result.systems = cloneNestedStats(source and source.systems)
	result.cardinality = cloneMap(source and source.cardinality)
	return result
end

local function addHistogram(histogram, bounds, value)
	for index, upperBound in ipairs(bounds) do
		if value <= upperBound or index == #bounds then
			histogram[index] += 1
			return
		end
	end
end

local function percentile(histogram, bounds, samples, ratio): number
	if samples <= 0 then return 0 end
	local target = math.max(1, math.ceil(samples * ratio))
	local cumulative = 0
	for index, amount in ipairs(histogram) do
		cumulative += amount
		if cumulative >= target then return bounds[index] end
	end
	return bounds[#bounds]
end

local function accumulateNamed(target, name, sample)
	local current = target[name]
	if current == nil then
		current = { samples = 0, totalMs = 0, maxMs = 0, queries = 0, queryRows = 0, gets = 0 }
		target[name] = current
	end
	current.samples += 1
	current.totalMs += sample.ms or 0
	current.maxMs = math.max(current.maxMs, sample.ms or 0)
	current.queries += sample.queries or 0
	current.queryRows += sample.queryRows or 0
	current.gets += sample.gets or 0
end

local function accumulate(definition, accumulator, sample)
	accumulator.elapsedSeconds += sample.elapsedSeconds or 0

	if sample.frameMs ~= nil then
		local frameMs = math.max(0, sample.frameMs)
		accumulator.frameSamples += 1
		accumulator.frameTotalMs += frameMs
		accumulator.frameMaxMs = math.max(accumulator.frameMaxMs, frameMs)
		addHistogram(accumulator.frameHistogram, definition.histogramBounds, frameMs)
		if frameMs >= definition.hitchFrameMs then accumulator.hitchCount += 1 end
		if frameMs >= definition.severeFrameMs then accumulator.severeHitchCount += 1 end
		if frameMs >= definition.freezeFrameMs then accumulator.freezeCount += 1 end
	end

	if sample.workMs ~= nil then
		local workMs = math.max(0, sample.workMs)
		accumulator.workSamples += 1
		accumulator.workTotalMs += workMs
		accumulator.workMaxMs = math.max(accumulator.workMaxMs, workMs)
		addHistogram(accumulator.workHistogram, definition.histogramBounds, workMs)
		accumulator.cardinalityCountdown = math.max(0, accumulator.cardinalityCountdown - 1)
	end

	accumulator.evolutionTotalMs += sample.evolutionMs or 0
	accumulator.actuationTotalMs += sample.actuationMs or 0

	local profile = sample.profile
	if profile ~= nil then
		accumulator.contributions += profile.contributions or 0
		accumulator.resolvedContributions += profile.resolvedContributions or 0
		accumulator.effects += profile.effects or 0
		accumulator.stateWrites += profile.stateWrites or 0
		accumulator.queries += profile.queries or 0
		accumulator.queryRows += profile.queryRows or 0
		accumulator.traceEntriesCloned += profile.traceEntriesCloned or 0
		accumulator.traceEntriesShifted += profile.traceEntriesShifted or 0
		for phaseName, phase in pairs(profile.phases or {}) do
			accumulateNamed(accumulator.phases, phaseName, phase)
		end
		for systemName, system in pairs(profile.systems or {}) do
			accumulateNamed(accumulator.systems, systemName, system)
		end
	end

	if sample.heapKb ~= nil then
		local heapKb = sample.heapKb
		if accumulator.heapFirstKb == nil then accumulator.heapFirstKb = heapKb end
		if accumulator.heapLastKb ~= nil and heapKb <= accumulator.heapLastKb - definition.gcDropKb then
			accumulator.gcSuspectCount += 1
			accumulator.gcFreedKb += accumulator.heapLastKb - heapKb
			if (sample.cadenceMs or 0) >= definition.hitchFrameMs then
				accumulator.gcAssociatedHitches += 1
			end
		end
		accumulator.heapLastKb = heapKb
		accumulator.heapMinKb = if accumulator.heapMinKb == nil then heapKb else math.min(accumulator.heapMinKb, heapKb)
		accumulator.heapMaxKb = if accumulator.heapMaxKb == nil then heapKb else math.max(accumulator.heapMaxKb, heapKb)
	end

	if sample.cardinality ~= nil then
		accumulator.cardinality = cloneMap(sample.cardinality)
		accumulator.cardinalityCountdown = definition.cardinalityEverySamples
	end
end

local function summarizeNamed(source)
	local result = {}
	local hotName = "-"
	local hotAverage = -1
	for name, stats in pairs(source) do
		local samples = math.max(1, stats.samples)
		local average = stats.totalMs / samples
		result[name] = {
			averageMs = average,
			maxMs = stats.maxMs,
			queriesPerSample = stats.queries / samples,
			queryRowsPerSample = stats.queryRows / samples,
			getsPerSample = stats.gets / samples,
		}
		if average > hotAverage or (average == hotAverage and tostring(name) < tostring(hotName)) then
			hotName = name
			hotAverage = average
		end
	end
	return result, hotName, math.max(0, hotAverage)
end

local function makeSnapshot(definition, accumulator, previous)
	local frames = math.max(1, accumulator.frameSamples)
	local works = math.max(1, accumulator.workSamples)
	local phaseStats, hotPhase, hotPhaseMs = summarizeNamed(accumulator.phases)
	local systemStats, hotSystem, hotSystemMs = summarizeNamed(accumulator.systems)
	local heapDeltaKb = if accumulator.heapFirstKb ~= nil and accumulator.heapLastKb ~= nil
		then accumulator.heapLastKb - accumulator.heapFirstKb else 0
	return {
		revision = (previous and previous.revision or 0) + 1,
		ready = true,
		realm = definition.realm,
		windowSeconds = accumulator.elapsedSeconds,
		frameSamples = accumulator.frameSamples,
		averageFrameMs = accumulator.frameTotalMs / frames,
		p50FrameMs = percentile(accumulator.frameHistogram, definition.histogramBounds, accumulator.frameSamples, 0.50),
		p95FrameMs = percentile(accumulator.frameHistogram, definition.histogramBounds, accumulator.frameSamples, 0.95),
		p99FrameMs = percentile(accumulator.frameHistogram, definition.histogramBounds, accumulator.frameSamples, 0.99),
		maxFrameMs = accumulator.frameMaxMs,
		hitchRate = accumulator.hitchCount / frames,
		severeHitchRate = accumulator.severeHitchCount / frames,
		freezeCount = accumulator.freezeCount,
		averageWorkMs = accumulator.workTotalMs / works,
		p95WorkMs = percentile(accumulator.workHistogram, definition.histogramBounds, accumulator.workSamples, 0.95),
		maxWorkMs = accumulator.workMaxMs,
		averageEvolutionMs = accumulator.evolutionTotalMs / works,
		averageActuationMs = accumulator.actuationTotalMs / works,
		contributionsPerWork = accumulator.contributions / works,
		resolvedContributionsPerWork = accumulator.resolvedContributions / works,
		effectsPerWork = accumulator.effects / works,
		stateWritesPerWork = accumulator.stateWrites / works,
		queriesPerWork = accumulator.queries / works,
		queryRowsPerWork = accumulator.queryRows / works,
		traceEntriesClonedPerWork = accumulator.traceEntriesCloned / works,
		traceEntriesShiftedPerWork = accumulator.traceEntriesShifted / works,
		heapKb = accumulator.heapLastKb or 0,
		heapDeltaKb = heapDeltaKb,
		heapGrowthKbPerSecond = heapDeltaKb / math.max(0.001, accumulator.elapsedSeconds),
		heapRangeKb = (accumulator.heapMaxKb or 0) - (accumulator.heapMinKb or 0),
		gcSuspectCount = accumulator.gcSuspectCount,
		gcFreedKb = accumulator.gcFreedKb,
		gcAssociatedHitches = accumulator.gcAssociatedHitches,
		cardinality = cloneMap(accumulator.cardinality),
		phaseStats = phaseStats,
		systemStats = systemStats,
		hotPhase = hotPhase,
		hotPhaseMs = hotPhaseMs,
		hotSystem = hotSystem,
		hotSystemMs = hotSystemMs,
	}
end

local function addCause(causes, condition, message)
	if condition then table.insert(causes, message) end
end

local function classify(definition, snapshot)
	local critical = snapshot.freezeCount > 0
		or snapshot.severeHitchRate >= definition.warningHitchRate
		or snapshot.hitchRate >= definition.criticalHitchRate
	local warning = snapshot.p95FrameMs > definition.targetFrameMs
		or snapshot.hitchRate >= definition.warningHitchRate
		or snapshot.p95WorkMs > definition.workBudgetMs
		or snapshot.heapGrowthKbPerSecond >= definition.heapGrowthWarningKbPerSecond

	local causes = {}
	addCause(causes, snapshot.p95FrameMs > definition.targetFrameMs, string.format("p95 %.1fms 超过帧预算", snapshot.p95FrameMs))
	addCause(causes, snapshot.hitchRate >= definition.warningHitchRate, string.format("卡顿帧 %.1f%%", snapshot.hitchRate * 100))
	addCause(causes, snapshot.freezeCount > 0, string.format("冻结帧 %d", snapshot.freezeCount))
	addCause(causes, snapshot.p95WorkMs > definition.workBudgetMs, string.format("ECS 工作 p95 %.1fms", snapshot.p95WorkMs))
	addCause(causes, snapshot.gcAssociatedHitches > 0, string.format("疑似 GC 关联卡顿 %d 次", snapshot.gcAssociatedHitches))
	addCause(causes, snapshot.heapGrowthKbPerSecond >= definition.heapGrowthWarningKbPerSecond, string.format("堆增长 %.0fKB/s", snapshot.heapGrowthKbPerSecond))

	local level = if critical then "Critical" elseif warning then "Warning" else "Healthy"
	local message = if #causes == 0 then "帧时间与状态演化均在预算内" else table.concat(causes, "；")
	return {
		revision = snapshot.revision,
		level = level,
		causes = causes,
		message = message,
	}
end

function PerformanceRule.resolve(contributions)
	local channels = {}
	for _, contribution in ipairs(contributions) do
		local channel = assert(contribution.channel, "Performance Contribution needs a channel")
		local group = channels[channel]
		if group == nil then
			group = {}
			channels[channel] = group
		end
		table.insert(group, contribution)
	end

	local transactions = {}
	for _, channel in ipairs(StableRule.sortedKeys(channels)) do
		local group = channels[channel]
		local materializer = group[1]
		assert(materializer.materialize, "Performance channel needs a System materializer")
		local definition = group[1].definition
		local accumulator = normalizeAccumulator(definition, group[1].accumulator)
		local currentSnapshot = group[1].snapshot
		local completedSnapshot = nil
		local completedAlert = nil

		for _, contribution in ipairs(group) do
			accumulate(definition, accumulator, contribution.sample)
			if accumulator.elapsedSeconds >= definition.windowSeconds
				and (accumulator.frameSamples > 0 or accumulator.workSamples > 0) then
				completedSnapshot = makeSnapshot(definition, accumulator, currentSnapshot)
				completedAlert = classify(definition, completedSnapshot)
				currentSnapshot = completedSnapshot
				accumulator = emptyAccumulator(definition, accumulator)
			end
		end

		local transactionData = materializer.materialize({
			accumulator = accumulator,
			snapshot = completedSnapshot,
			alert = completedAlert,
		})
		transactionData.phase = transactionData.phase or materializer.phase
		transactionData.priority = transactionData.priority or materializer.priority
		transactionData.orderKey = transactionData.orderKey or materializer.orderKey
		transactionData.channel = channel
		table.insert(transactions, Contribution.transaction("PerformanceRule<" .. materializer.source .. ">", transactionData))
	end
	return transactions
end

return table.freeze(PerformanceRule)
