local M = {}

local screens = {}

local stack = {}


local function screen_from_proxy(proxy)
	for id,screen in pairs(screens) do
		if screen.proxy == proxy then
			return screen
		end
	end
end

local function screen_from_script()
	local url = msg.url()
	for id,screen in pairs(screens) do
		if screen.script == url then
			return screen
		end
	end
end

local function in_stack(id)
	for i=1,#stack do
		if stack[i].id == id then
			return true
		end
	end
	return false
end

function M.register(id, proxy, popup, transitions)
	assert(not screens[id], ("There is already a screen registered with id %s"):format(tostring(id)))
	screens[id] = { id = id, proxy = proxy, script = msg.url(), popup = popup, transitions = transitions }
end

function M.unregister(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	screens[id] = nil
end

local function show_out(screen, next_screen)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, "release_input_focus")
		msg.post(screen.script, "monarch_context")
		coroutine.yield()
		if not next_screen.popup then
			msg.post(screen.transitions.show_out, "transition_show_out")
			coroutine.yield()
			msg.post(screen.proxy, "unload")
			coroutine.yield()
		end
		screen.co = nil
	end)
	coroutine.resume(co)
end

local function show_in(screen)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, "monarch_context")
		coroutine.yield()
		msg.post(screen.proxy, "async_load")
		coroutine.yield()
		msg.post(screen.proxy, "enable")
		stack[#stack + 1] = screen
		msg.post(screen.transitions.show_in, "transition_show_in")
		coroutine.yield()
		msg.post(screen.script, "acquire_input_focus")
		screen.co = nil
	end)
	coroutine.resume(co)
end

local function back_in(screen, previous_screen)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, "monarch_context")
		coroutine.yield()
		if not previous_screen.popup then
			msg.post(screen.proxy, "async_load")
			coroutine.yield()
			msg.post(screen.proxy, "enable")
			msg.post(screen.transitions.back_in, "transition_back_in")
			coroutine.yield()
		end
		msg.post(screen.script, "acquire_input_focus")
		screen.co = nil
	end)
	coroutine.resume(co)
end

local function back_out(screen)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, "release_input_focus")
		msg.post(screen.script, "monarch_context")
		coroutine.yield()
		msg.post(screen.transitions.back_out, "transition_back_out")
		coroutine.yield()
		msg.post(screen.proxy, "unload")
		screen.co = nil
	end)
	coroutine.resume(co)
end


--- Show a new screen
-- @param id Id of the screen to show
-- @param clear Set to true if the stack should be cleared down to an existing instance of the screen. Optional
function M.show(id, clear)
	assert(id, "You must provide a screen id")
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	local screen = screens[id]
	
	-- manipulate the current top
	-- close popup if needed
	-- transition out
	local top = stack[#stack]
	if top then
		-- if top is popup then close it
		if top.popup then
			stack[#stack] = nil
			show_out(top, screen)
			top = stack[#stack]
		end
		-- unload and transition out from top
		if top then
			show_out(top, screen)
		end
	end

	-- if the screen we want to show is in the stack
	-- already and the clear flag is set then we need
	-- to remove every screen on the stack up until and
	-- including the screen itself
	if clear and in_stack(id) then
		while true do
			if table.remove(stack).id == id then
				break
			end
			
		end
	end

	-- show screen
	show_in(screen)
end


-- Go back to the previous screen in the stack
function M.back()
	local screen = table.remove(stack)
	if screen then
		back_out(screen)
		local top = stack[#stack]
		if top then
			back_in(top, screen)
		end
	end
end


function M.on_message(message_id, message, sender)
	if message_id == hash("proxy_loaded") then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for loaded proxy")
		coroutine.resume(screen.co)
	elseif message_id == hash("proxy_unloaded") then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for unloaded proxy")
	elseif message_id == hash("monarch_context") then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		coroutine.resume(screen.co)
	elseif message_id == hash("transition_done") then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		coroutine.resume(screen.co)
	end
end

function M.dump_stack()
	local s = ""
	for i,screen in ipairs(stack) do
		s = s .. ("%d = %s\n"):format(i, tostring(screen.id))
	end
	return s
end

return M