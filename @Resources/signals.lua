-- Exposes a NUMBER describing current status, so the skin can drive colours and
-- images with IfConditions. Rainmeter cannot branch on a string measure, and the
-- transcript reader deliberately only returns text - hence this separate file.
--
-- Two modes, chosen per measure:
--
--   Mode=provider   ConfigFile=#@#config.json
--       1 = an API key is configured, 0 = not configured yet
--
--   Mode=state      StateFile=#@#state.txt
--       0 = idle/ready, 1 = working, 2 = something went wrong
--
-- IMPORTANT: measures using this must leave IfConditionMode at its default of 0,
-- so actions fire only when the value CHANGES. A previous version of this skin
-- shipped an IfConditionMode=1 probe that launched a process on every single
-- update - roughly eight per second, forever. See design.md.

function Initialize()
    mode     = SELF:GetOption('Mode', 'state')
    filePath = SELF:GetOption(mode == 'provider' and 'ConfigFile' or 'StateFile', '')
end

local function readAll(path)
    if not path or path == '' then return nil end
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

function Update()
    local body = readAll(filePath)

    if mode == 'provider' then
        if not body then return 0 end
        -- Any non-empty ApiKey counts. Deliberately does NOT verify the key
        -- works: proving that means a live request on every skin load.
        local key = body:match('"ApiKey"%s*:%s*"([^"]*)"')
        if key and key ~= '' then return 1 end
        return 0
    end

    if not body then return 0 end
    local s = body:gsub('%s', '')
    if s == 'ERROR' then return 2 end
    if s == 'SENDING' or s == 'STREAMING' or s == 'SEARCHING' then return 1 end
    return 0
end
