--[[
{
  "module": "orlando.server",
  "role": "HTTP server for Orlando. Parses the request line, hands the path to orlando.route, then either renders a markdown file (orlando.page), serves a static file with the right Content-Type (orlando.content_type), or returns 404. No caching — every request re-reads source from disk and re-runs the pipeline.",
  "exports": {
    "serve": "starts the accept loop on the given port; never returns under normal operation"
  },
  "dependencies": ["luasocket", "orlando.page", "orlando.content_type", "orlando.route"]
}
]]
local socket       = require("socket")
local page         = require("orlando.page")
local content_type = require("orlando.content_type")
local route        = require("orlando.route")
local api          = require("orlando.api")

local M = {}

local DEFAULT_PORT = 8181
local DEFAULT_HOST = "127.0.0.1"  -- loopback by default; nginx fronts public traffic


local CSP = "img-src 'self'; style-src 'self'; script-src 'self'"

local function build_response(status_line, body, content_type_value, extra_headers)
    local parts = {
        "HTTP/1.1 ", status_line, "\r\n",
        "Content-Type: ", content_type_value, "\r\n",
        "Content-Length: ", tostring(#body), "\r\n",
        "Content-Security-Policy: ", CSP, "\r\n",
        "Connection: close\r\n",
    }
    if extra_headers then
        for _, h in ipairs(extra_headers) do
            parts[#parts + 1] = h
            parts[#parts + 1] = "\r\n"
        end
    end
    parts[#parts + 1] = "\r\n"
    parts[#parts + 1] = body
    return table.concat(parts)
end

local function read_file(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local data = f:read("*a")
    f:close()
    return data
end

local function parse_request_line(line)
    -- "GET /foo/bar?x=1 HTTP/1.1" → method, path
    if not line then return nil, nil end
    local method, path = line:match("^(%S+)%s+(%S+)")
    return method, path
end

local NOT_FOUND_BODY = "<!DOCTYPE html><html><body><h1>404 Not Found</h1></body></html>\n"

local function read_headers(client)
    local headers = {}
    while true do
        local line = client:receive("*l")
        if not line or line == "" then break end
        local k, v = line:match("^([^:]+):%s*(.+)$")
        if k then headers[k:lower()] = v end
    end
    return headers
end

local function respond(client, request_line)
    local method, path = parse_request_line(request_line)
    local headers = read_headers(client)

    local body = ""
    local clen = tonumber(headers["content-length"])
    if clen and clen > 0 then
        body = client:receive(clen) or ""
    end

    -- /api/* endpoints are side-effecting and bypass route.resolve.
    if path and path:sub(1, 5) == "/api/" then
        local resp = api.dispatch({ method = method, path = path, body = body })
        client:send(build_response(resp.status, resp.body, resp.content_type))
        return
    end

    if method ~= "GET" then
        client:send(build_response("405 Method Not Allowed", "Method Not Allowed\n", "text/plain; charset=utf-8"))
        return
    end

    local r = route.resolve(path or "/")

    if r.kind == "redirect" then
        local body = '<!DOCTYPE html><html><body>Moved to <a href="'
                  .. r.location .. '">' .. r.location .. '</a></body></html>\n'
        -- Cache-Control: no-store stops browsers from caching the 301.
        -- Without this, if a routing rule is later corrected, viewers
        -- can stay stuck on the old destination because their browser
        -- never re-asks the server. Orlando's no-caching design carries
        -- through to its 301s too.
        client:send(build_response("301 Moved Permanently", body,
            "text/html; charset=utf-8",
            {"Location: " .. r.location, "Cache-Control: no-store"}))
        return
    end

    if r.kind == "markdown" then
        local title = r.path == "README.md"
            and "Puck"
            or (r.path:match("([^/]+)%.md$") or r.path)
        local html = page.render_request({
            md_path = r.path,
            title   = title,
        })
        client:send(build_response("200 OK", html, content_type.for_ext("html")))
        return
    end

    if r.kind == "static" then
        local data, err = read_file(r.path)
        if not data then
            client:send(build_response("500 Internal Server Error",
                "Failed to read static file: " .. tostring(err) .. "\n",
                "text/plain; charset=utf-8"))
            return
        end
        client:send(build_response("200 OK", data, content_type.for_file(r.path)))
        return
    end

    -- not_found
    client:send(build_response("404 Not Found", NOT_FOUND_BODY, content_type.for_ext("html")))
end

--[[ {
    "in":  {"opts": "table? — { host = string?, port = number? }"},
    "out": "never returns under normal operation; loops forever",
    "note": "Synchronous accept loop. One connection handled at a time. No logging. Renders / serves per-request — no caching."
} ]]
function M.serve(opts)
    opts = opts or {}
    local host = opts.host or DEFAULT_HOST
    local port = opts.port or DEFAULT_PORT

    local listener, err = socket.bind(host, port)
    if not listener then
        error("orlando: could not bind " .. host .. ":" .. port .. " — " .. tostring(err))
    end
    listener:settimeout(nil)

    while true do
        local client = listener:accept()
        client:settimeout(5)
        local request_line = client:receive("*l")
        respond(client, request_line)
        client:close()
    end
end

return M
