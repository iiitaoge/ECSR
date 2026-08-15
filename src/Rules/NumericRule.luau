--!strict

local Contribution = require(script.Parent.Parent.Components.Contribution)
local StableRule = require(script.Parent.StableRule)

local NumericRule = {}
NumericRule.kind = "Numeric"

function NumericRule.resolve(contributions)
	local channels = {}
	for _, contribution in ipairs(contributions) do
		local channel = assert(contribution.channel, "Numeric Contribution needs a channel")
		local state = channels[channel]
		if state == nil then
			state = {
				base = nil,
				initial = contribution.initial or 0,
				add = 0,
				multiply = 1,
				minimum = nil,
				maximum = nil,
				materializer = nil,
			}
			channels[channel] = state
		end

		if contribution.mode == "base" and state.base == nil then
			state.base = contribution.value
		elseif contribution.mode == "add" then
			state.add += contribution.value
		elseif contribution.mode == "multiply" then
			state.multiply *= contribution.value
		else
			assert(contribution.mode == "base", "Unknown Numeric composition mode")
		end

		if contribution.minimum ~= nil then
			state.minimum = if state.minimum == nil then contribution.minimum else math.max(state.minimum, contribution.minimum)
		end
		if contribution.maximum ~= nil then
			state.maximum = if state.maximum == nil then contribution.maximum else math.min(state.maximum, contribution.maximum)
		end
		if state.materializer == nil and contribution.materialize ~= nil then
			state.materializer = contribution
		end
	end

	local transactions = {}
	for _, channel in ipairs(StableRule.sortedKeys(channels)) do
		local state = channels[channel]
		local value = ((if state.base ~= nil then state.base else state.initial) + state.add) * state.multiply
		if state.minimum ~= nil then
			value = math.max(state.minimum, value)
		end
		if state.maximum ~= nil then
			value = math.min(state.maximum, value)
		end

		local materializer = assert(state.materializer, "Numeric channel needs a System materializer")
		local transactionData = materializer.materialize(value)
		if transactionData ~= nil then
			transactionData.phase = transactionData.phase or materializer.phase
			transactionData.priority = transactionData.priority or materializer.priority
			transactionData.orderKey = transactionData.orderKey or materializer.orderKey
			transactionData.channel = channel
			table.insert(transactions, Contribution.transaction("NumericRule<" .. materializer.source .. ">", transactionData))
		end
	end

	return transactions
end

return table.freeze(NumericRule)
