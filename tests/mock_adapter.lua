-- Minimal debug adapter, meant to be run as `nvim -l tests/mock_adapter.lua`.
--
-- It speaks just enough of the Debug Adapter Protocol to get a session with a terminal going:
-- it asks the client to run `arguments.command` (from the launch request) in an integrated
-- terminal and, like a real adapter would, keeps the session alive until the debuggee is done.
-- That's enough to exercise the console view without depending on a real debug adapter.
--
-- Since the command runs on the client, the adapter can't watch the process: instead, the
-- command is expected to create the `arguments.done` file on its way out.

local uv = vim.uv

local stdin = assert(uv.new_pipe(false))
local stdout = assert(uv.new_pipe(false))

stdin:open(0)
stdout:open(1)

local seq = 0

---@param message table
local function send(message)
    seq = seq + 1
    message.seq = seq

    local payload = vim.json.encode(message)

    stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#payload, payload))
end

---@param request table
---@param body table?
local function respond(request, body)
    send({
        type = "response",
        request_seq = request.seq,
        success = true,
        command = request.command,
        body = body or vim.empty_dict(),
    })
end

---@param name string
---@param body table?
local function event(name, body)
    send({ type = "event", event = name, body = body or vim.empty_dict() })
end

---Requests we only have to acknowledge
local NOOP_REQUESTS = {
    setBreakpoints = { breakpoints = {} },
    setExceptionBreakpoints = nil,
    setFunctionBreakpoints = { breakpoints = {} },
    threads = { threads = {} },
}

local finished = false

---@type table?
local pending_launch

---@type table?
local launch_arguments

---@param request table
local function on_request(request)
    local command = request.command

    if command == "initialize" then
        respond(request, { supportsConfigurationDoneRequest = true })
    elseif command == "launch" then
        -- Respond to the launch request only after the terminal is up, mimicking real adapters
        pending_launch = request
        launch_arguments = request.arguments

        send({
            type = "request",
            command = "runInTerminal",
            arguments = {
                kind = "integrated",
                title = "Mock",
                cwd = "",
                args = request.arguments.command,
            },
        })
    elseif command == "configurationDone" then
        respond(request)

        local done = launch_arguments and launch_arguments.done

        if not done then
            event("terminated")
            return
        end

        -- Can't block here: this runs from a callback, and the debuggee's output has to be
        -- streamed to the client while we wait
        local timer = assert(uv.new_timer())

        timer:start(10, 10, function()
            if uv.fs_stat(done) then
                timer:stop()
                timer:close()

                event("terminated")
            end
        end)
    elseif command == "disconnect" then
        respond(request)

        finished = true
    else
        respond(request, NOOP_REQUESTS[command])
    end
end

---@param response table
local function on_response(response)
    if response.command == "runInTerminal" and pending_launch then
        respond(pending_launch)

        pending_launch = nil

        event("initialized")
    end
end

local buffer = ""

stdin:read_start(function(err, chunk)
    assert(not err, err)

    if not chunk then
        finished = true
        return
    end

    buffer = buffer .. chunk

    while true do
        local header_end = buffer:find("\r\n\r\n", 1, true)

        if not header_end then
            return
        end

        local length = tonumber(buffer:sub(1, header_end):match("Content%-Length: (%d+)"))
        local body_start = header_end + 4

        if not length or #buffer < body_start + length - 1 then
            return
        end

        local message = vim.json.decode(buffer:sub(body_start, body_start + length - 1))

        buffer = buffer:sub(body_start + length)

        if message.type == "request" then
            on_request(message)
        elseif message.type == "response" then
            on_response(message)
        end
    end
end)

-- Don't hang around forever if the client goes away without disconnecting
vim.wait(60000, function()
    return finished
end, 10)
