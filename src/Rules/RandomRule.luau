--!strict

local RandomRule = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271

function RandomRule.seed(value: number): number
	local seed = math.floor(math.abs(value) * MULTIPLIER + 1) % MODULUS
	return if seed == 0 then 1 else seed
end

function RandomRule.next(seed: number): (number, number)
	local nextSeed = (seed * MULTIPLIER) % MODULUS
	if nextSeed == 0 then
		nextSeed = 1
	end
	return nextSeed, nextSeed / MODULUS
end

function RandomRule.integer(seed: number, minimum: number, maximum: number): (number, number)
	local nextSeed, unit = RandomRule.next(seed)
	local width = maximum - minimum + 1
	return nextSeed, minimum + math.min(width - 1, math.floor(unit * width))
end

function RandomRule.chance(seed: number, probability: number): (number, boolean)
	local nextSeed, unit = RandomRule.next(seed)
	return nextSeed, unit < math.clamp(probability, 0, 1)
end

function RandomRule.weighted(seed: number, weights, order): (number, string)
	local total = 0
	for _, key in ipairs(order) do
		total += math.max(0, weights[key] or 0)
	end
	assert(total > 0, "Weighted random Rule needs a positive weight")

	local nextSeed, unit = RandomRule.next(seed)
	local cursor = unit * total
	for _, key in ipairs(order) do
		cursor -= math.max(0, weights[key] or 0)
		if cursor <= 0 then
			return nextSeed, key
		end
	end
	return nextSeed, order[#order]
end

return table.freeze(RandomRule)
