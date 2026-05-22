--[[
{
  "file": "orlando/tests/hello/test_hello.lua",
  "role": "Integration test for the Stage-1 hello-world server: fork the server in a subprocess, connect to it, verify the response, kill it.",
  "approach": "io.popen('lua orlando/lua/serve.lua <port> ...') to start the server in background, sleep briefly to let it bind, then connect via luasocket and read the response. Kills the subprocess on exit."
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local socket  = require("socket")

runner.suite("hello")

-- Pick a high random-ish port to avoid colliding with anything else.
-- math.random is fine for test-port selection — uniqueness, not security.
math.randomseed(os.time())
local TEST_PORT = 18000 + math.random(0, 999)

local function start_server(port)
    -- Background the server; redirect output so it doesn't pollute test output.
    local cmd = string.format(
        "lua orlando/lua/serve.lua %d >/tmp/orlando-test.log 2>&1 &  echo $!",
        port
    )
    local handle = io.popen(cmd)
    local pid = tonumber(handle:read("*l"))
    handle:close()
    -- Give it a moment to bind.
    socket.sleep(0.25)
    return pid
end

local function stop_server(pid)
    if pid then os.execute("kill " .. pid .. " 2>/dev/null") end
end

local function http_get(host, port, path)
    local sock = socket.tcp()
    sock:settimeout(2)
    local ok, err = sock:connect(host, port)
    if not ok then error("connect failed: " .. tostring(err)) end
    sock:send(string.format("GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", path, host))
    local response, err2 = sock:receive("*a")
    sock:close()
    if not response then error("receive failed: " .. tostring(err2)) end
    return response
end

runner.test("server returns the hand-edited index.html at /", function()
    local pid = start_server(TEST_PORT)
    local ok, response_or_err = pcall(http_get, "127.0.0.1", TEST_PORT, "/")
    stop_server(pid)
    assert_.is_true(ok, "http_get raised: " .. tostring(response_or_err))
    local response = response_or_err
    assert_.not_nil(response:match("^HTTP/1%.1 200 OK"),         "expected '200 OK' status line")
    assert_.not_nil(response:match("Content%-Type: text/html"),  "expected text/html content-type")
    assert_.not_nil(response:match("<!DOCTYPE html>"),           "expected HTML5 doctype")
    -- Initial index.html links to the documentation entry.
    assert_.not_nil(response:match('href="/documentation/"'),    "expected link to /documentation/")
end)

runner.test("server renders the README at /documentation/", function()
    local pid = start_server(TEST_PORT + 4)
    local ok, response = pcall(http_get, "127.0.0.1", TEST_PORT + 4, "/documentation/")
    stop_server(pid)
    assert_.is_true(ok, "http_get raised: " .. tostring(response))
    assert_.not_nil(response:match("^HTTP/1%.1 200 OK"))
    assert_.not_nil(response:match("<title>Puck</title>"),  "README title should be 'Puck'")
    assert_.not_nil(response:match("<h1>.-Puck.-</h1>"),    "expected <h1> containing 'Puck'")
    assert_.not_nil(response:match("The three packages"),   "expected the 'three packages' section header")
end)

runner.test("server renders a doc by path: /documentation/overview", function()
    local pid = start_server(TEST_PORT + 1)
    local ok, response = pcall(http_get, "127.0.0.1", TEST_PORT + 1, "/documentation/overview")
    stop_server(pid)
    assert_.is_true(ok, "http_get raised: " .. tostring(response))
    assert_.not_nil(response:match("^HTTP/1%.1 200 OK"))
    assert_.not_nil(response:match("Content%-Type: text/html"))
    -- Overview doc's first H1 says "Project Overview".
    assert_.not_nil(response:match("Project Overview"), "expected overview content")
end)

runner.test("server serves a file from /static/", function()
    local pid = start_server(TEST_PORT + 2)
    local ok, response = pcall(http_get, "127.0.0.1", TEST_PORT + 2, "/static/README.md")
    stop_server(pid)
    assert_.is_true(ok, "http_get raised: " .. tostring(response))
    assert_.not_nil(response:match("^HTTP/1%.1 200 OK"))
    -- .md served from /static/ goes through the static (verbatim) path,
    -- so Content-Type is text/markdown — not rendered to HTML.
    assert_.not_nil(response:match("Content%-Type: text/markdown"),
                    "expected text/markdown for verbatim static .md")
end)

runner.test("server returns 404 for a path that matches no source or static file", function()
    local pid = start_server(TEST_PORT + 3)
    local ok, response = pcall(http_get, "127.0.0.1", TEST_PORT + 3, "/this/does/not/exist")
    stop_server(pid)
    assert_.is_true(ok, "http_get raised: " .. tostring(response))
    assert_.not_nil(response:match("^HTTP/1%.1 404 Not Found"))
end)
