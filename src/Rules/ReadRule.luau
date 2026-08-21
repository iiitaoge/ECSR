--!strict

local ReadRule = {}

export type Metrics = {
	gets: number,
	contains: number,
	sizes: number,
	queries: number,
	queryDriverRows: number,
	queryRows: number,
	queryComponentReads: number,
}

export type View = {
	get: (self: View, entityId: number, ...any) -> ...any,
	contains: (self: View, entityId: number) -> boolean,
	size: (self: View) -> number,
	query: (self: View, ...any) -> { { any } },
}

function ReadRule.new(world: any, metrics: Metrics?): View
	local view: any = {}
	local activeMetrics: any = metrics or {}
	activeMetrics.gets = activeMetrics.gets or 0
	activeMetrics.contains = activeMetrics.contains or 0
	activeMetrics.sizes = activeMetrics.sizes or 0
	activeMetrics.queries = activeMetrics.queries or 0
	activeMetrics.queryDriverRows = activeMetrics.queryDriverRows or 0
	activeMetrics.queryRows = activeMetrics.queryRows or 0
	activeMetrics.queryComponentReads = activeMetrics.queryComponentReads or 0

	function view:get(entityId: number, ...)
		activeMetrics.gets += select("#", ...)
		return world:get(entityId, ...)
	end

	function view:contains(entityId: number): boolean
		activeMetrics.contains += 1
		return world:contains(entityId)
	end

	function view:size(): number
		activeMetrics.sizes += 1
		return world:size()
	end

	-- Query one stable driver and fetch an arbitrary number M of Components.
	function view:query(...)
		local componentTypes = table.pack(...)
		assert(componentTypes.n > 0, "A System query needs at least one Component")
		activeMetrics.queries += 1
		local rows = {}

		for entityId in world:query(componentTypes[1]) do
			activeMetrics.queryDriverRows += 1
			activeMetrics.queryComponentReads += componentTypes.n
			local values = table.pack(world:get(entityId, table.unpack(componentTypes, 1, componentTypes.n)))
			local complete = true
			for index = 1, componentTypes.n do
				if values[index] == nil then
					complete = false
					break
				end
			end
			if complete then
				local row = { entityId }
				for index = 1, componentTypes.n do
					table.insert(row, values[index])
				end
				table.insert(rows, row)
				activeMetrics.queryRows += 1
			end
		end

		table.sort(rows, function(a, b)
			return a[1] < b[1]
		end)
		return rows
	end

	return table.freeze(view)
end

return table.freeze(ReadRule)
