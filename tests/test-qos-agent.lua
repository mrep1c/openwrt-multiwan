-- Exercise the actual endpoint with private state and an in-memory nft kernel.
local file = assert(io.open("multiwan-qos/www/cgi-bin/multiwan-qos-agent", "r"))
local source = file:read("*a"):match("^(.-)%-%- Main CGI handler")
file:close()
assert(source, "endpoint function boundary missing")
source = source:gsub("^#![^\n]*\n", "")
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local pc = "192.168.1.4"
local flow = { game = "Valorant", proto = "udp", remote_ip = "162.249.75.1", remote_port = 7272, local_port = 54144 }
local other = { game = "CS2", proto = "udp", remote_ip = "8.8.8.8", remote_port = 27015, local_port = 50000 }
local function conntrack(conn)
    return string.format("ipv4 2 udp 17 120 src=%s dst=%s sport=%d dport=%d packets=10 bytes=2000 src=%s dst=203.0.113.4 sport=%d dport=%d packets=10 bytes=2000 [ASSURED]",
        pc, conn.remote_ip, conn.local_port, conn.remote_port, conn.remote_ip, conn.remote_port, conn.local_port)
end
local function fixture()
    local mock = { now = 1000, state = nil, lines = {}, primary = {}, mirror = {}, writes = 0 }
    local env = setmetatable({}, { __index = _G })
    env.require = function(name) assert(name == "luci.jsonc"); return {} end
    env.os = { time = function() return mock.now end, remove = function() mock.state = nil end }
    env.io = { open = function(path, mode)
        assert(path == "/tmp/multiwan_qos_agent_rules.nft" and mode == "w", "unexpected file access")
        mock.batch = ""
        return { write = function(_, text) mock.batch = mock.batch .. text end, close = function() end }
    end }
    local export = [[
return {
    apply = apply_connection_rules,
    flush = flush_agent_chain,
    clear = clear_agent_state,
    inject = function(deps)
        read_agent_state = deps.read_state
        read_conntrack_lines = deps.read_conntrack
        read_command = deps.read_command
        command_ok = deps.command_ok
        agent_chain_exists = function() return true end
    end
}
]]
    local chunk = assert(loadstring(source .. export, "endpoint-under-test"))
    setfenv(chunk, env)
    local endpoint = chunk()
    endpoint.inject({
        read_state = function() return copy(mock.state) end,
        read_conntrack = function() return copy(mock.lines) end,
        read_command = function(command)
            local rules = command:find("multiwan_qos_agent_reapply", 1, true) and mock.mirror or mock.primary
            return "table inet dscptag {\nchain multiwan_qos_agent {\n" .. table.concat(rules, "\n") .. "\n}\n}", true
        end,
        command_ok = function(command)
            if command:find("nft flush chain", 1, true) then
                mock.primary = {}; mock.mirror = {}; return true
            end
            if command:match("^nft %-c %-f ") then return true end
            assert(command:match("^nft %-f "), "unexpected kernel command: " .. command)
            mock.writes = mock.writes + 1
            mock.primary = {}; mock.mirror = {}
            for line in mock.batch:gmatch("[^\n]+") do
                local chain, rule = line:match("^add rule inet dscptag (%S+) (.+)$")
                if chain then
                    local rules = chain == "multiwan_qos_agent" and mock.primary or mock.mirror
                    rules[#rules + 1] = rule
                end
            end
            return true
        end
    })
    function mock:update(connections, dscp)
        dscp = dscp or 46
        local class = dscp == 46 and "ef" or "cs5"
        local count, err, verification, rules, ignored, resolved, unmatched, reused = endpoint.apply(pc, connections, class, dscp)
        assert(count, err)
        assert(verification and verification.ok, "nft verification failed")
        if count > 0 then
            self.state = { pc_ip = pc, dscp = dscp, dscp_class = class, rule_count = count, rules = copy(rules) }
        else
            self.state = nil
        end
        return count, resolved, unmatched, reused
    end
    mock.endpoint = endpoint
    return mock
end

local mock = fixture()
mock.lines = { conntrack(flow) }
assert(mock:update({flow}) == 2)
local writes = mock.writes
mock.now = 1060; mock.lines = {}
local count, resolved, unmatched, reused = mock:update({flow})
assert(count == 2 and resolved == 0 and unmatched == 1 and reused, "transient lookup miss deleted an unchanged live flow")
assert(mock.writes == writes, "unchanged retained rules were rewritten")
mock.now = 1068
assert(mock:update({flow}) == 2, "retry lost the retained flow before grace expired")
mock.now = 1071
assert(mock:update({flow}) == 0, "lookup retries renewed retention indefinitely")
print("PASS: unchanged exact rules survive transient misses for a bounded, nonrenewing grace.")

mock = fixture()
mock.lines = { conntrack(flow), conntrack(other) }
assert(mock:update({flow, other}) == 4)
mock.now = 1060; mock.lines = { conntrack(other) }
assert(mock:update({flow, other}) == 4, "partial lookup failure discarded one live flow")
mock.now = 1065; mock.lines = { conntrack(flow), conntrack(other) }
assert(mock:update({flow, other}) == 4)
mock.now = 1125; mock.lines = { conntrack(other) }
assert(mock:update({flow, other}) == 4, "successful lookup did not reset the miss grace")
assert(mock:update({other}) == 2, "removed flow retained its rules")
print("PASS: partial misses, recovery, and explicit flow removal preserve exact scope.")

for _, field in ipairs({"remote_ip", "remote_port", "local_port", "proto", "game"}) do
    mock = fixture(); mock.lines = { conntrack(flow) }; assert(mock:update({flow}) == 2)
    local changed = copy(flow)
    if field == "remote_ip" then changed[field] = "1.1.1.1"
    elseif field == "proto" then changed[field] = "tcp"
    elseif field == "game" then changed[field] = "Other Game"
    else changed[field] = changed[field] + 1 end
    mock.now = 1060; mock.lines = {}
    assert(mock:update({changed}) == 0, "retention ignored changed " .. field)
end
mock = fixture(); mock.lines = { conntrack(flow) }; assert(mock:update({flow}) == 2)
mock.now = 1060; mock.lines = {}
assert(mock:update({flow}, 40) == 0, "retention ignored a DSCP change")
print("PASS: changed endpoints, owner labels, protocol, and DSCP never reuse old rules.")

for _, field in ipairs({"remote_port", "local_port"}) do
    local unrelated = copy(flow); unrelated[field] = unrelated[field] + 1
    mock = fixture(); mock.lines = { conntrack(flow) }; assert(mock:update({flow}) == 2)
    mock.now = 1060; mock.lines = { conntrack(unrelated) }
    local kept, _, missing = mock:update({flow})
    assert(kept == 2 and missing == 1 and mock.state.rules[1][field] == flow[field],
        "lookup silently redirected a selected flow to another " .. field)
    mock = fixture(); mock.lines = { conntrack(unrelated) }
    assert(mock:update({flow}) == 0, "unrelated socket was accepted as a new exact flow")
end
print("PASS: conntrack resolution cannot retarget a reported endpoint to another socket.")

for _, chain in ipairs({"primary", "mirror"}) do
    mock = fixture(); mock.lines = { conntrack(flow) }; assert(mock:update({flow}) == 2)
    for index, rule in ipairs(mock[chain]) do mock[chain][index] = rule:gsub("54144", "54145") end
    mock.now = 1060; mock.lines = {}
    assert(mock:update({flow}) == 0, "retention trusted changed " .. chain .. " tuples")
end
mock = fixture(); mock.lines = { conntrack(flow) }; assert(mock:update({flow}) == 2)
mock.endpoint.flush(); mock.endpoint.clear()
mock.now = 1060; mock.lines = {}
assert(mock:update({flow}) == 0, "cleared state resurrected cached rules")
print("PASS: kernel tuple verification and explicit clear prevent stale-rule resurrection.")
print("Agent endpoint regression tests passed. No real networking commands ran.")
