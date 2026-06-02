#!/usr/bin/lua

-- MultiWAN QoS Agent Watchdog
-- Clears stale agent rules if the PC crashes or stops sending heartbeats
-- Runs as a background loop managed by /etc/init.d/multiwan-qos

local TIMESTAMP_FILE = "/tmp/multiwan_qos_agent_last_seen"
local STATE_FILE = "/tmp/multiwan_qos_agent_state.json"
local CHECK_INTERVAL = 60 -- seconds

local function get_timeout()
    local f = io.popen("uci -q get multiwan-qos.agent.timeout 2>/dev/null")
    if not f then
        return 300
    end

    local val = tonumber(f:read("*l"))
    f:close()
    return val or 300
end

while true do
    -- Sleep first to allow the system to boot up/settle
    os.execute("sleep " .. CHECK_INTERVAL)

    local f = io.open(TIMESTAMP_FILE, "r")
    if f then
        local ts_str = f:read("*l")
        f:close()
        
        local ts = tonumber(ts_str)
        if ts then
            local now = os.time()
            if (now - ts) > get_timeout() then
                -- Time out! Agent disconnected.
                os.execute("nft flush chain inet dscptag multiwan_qos_agent 2>/dev/null")
                os.execute("logger -t multiwan-qos-agent 'Watchdog: Cleared stale agent rules'")
                os.remove(TIMESTAMP_FILE)
                os.remove(STATE_FILE)
            end
        end
    end
end
