-- =============================================================================
--  Chatterbot 2000 - conversation renderer
--
--  Owns exactly one thing: turning transcript.txt into a stack of message
--  bubbles. It does not fetch anything and does not know what an API is.
--
--  WHY THIS EXISTS
--  The old design drew the whole conversation into ONE String meter. That
--  wraps and scrolls beautifully, but one meter means one alignment, one
--  colour and one block - so it structurally cannot put the user's messages on
--  the right, draw a bubble behind each one, or place a face beside a reply.
--  Those need one set of meters per message, which is what this drives.
--
--  It runs IN PROCESS via SKIN:Bang. Doing this from PowerShell would mean a
--  process launch per option per message, which is exactly the kind of thing
--  that once spawned eight processes a second in this skin.
--
--  SLOT POOL
--  There is a fixed pool of MsgSlots meters. Only the most recent messages that
--  fit in the pool are drawn; older turns stay in transcript.txt and history but
--  scroll out of the pool. A desktop panel this size is not a scrollback buffer.
-- =============================================================================

function Initialize()
    filePath = SELF:GetOption('File')
    slots    = tonumber(SELF:GetOption('Slots', '12'))
    lastSig  = nil
end

local function readAll(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

-- Split the transcript into {role, text} messages. A line that is exactly
-- "You" or "Chatty" opens a new message; everything after it is that message's
-- body until the next such line.
local function parse(body)
    local msgs = {}
    local cur  = nil
    for line in (body .. '\n'):gmatch('([^\n]*)\n') do
        line = line:gsub('\r$', '')
        if line == 'You' or line == 'Chatty' then
            if cur then table.insert(msgs, cur) end
            cur = { role = line, lines = {} }
        elseif cur then
            table.insert(cur.lines, line)
        end
    end
    if cur then table.insert(msgs, cur) end

    for _, m in ipairs(msgs) do
        local t = table.concat(m.lines, '\n')
        t = t:gsub('^%s+', ''):gsub('%s+$', '')
        m.text = t
    end
    return msgs
end

function Update()
    -- Publish how tall the drawn stack currently is, so the scroll clamp knows
    -- how far it may travel. Measured from the meters as they stand right now,
    -- which means it lags a rebuild by one tick (125ms) - invisible in use, and
    -- far safer than trying to read heights of meters we are mid-way through
    -- rewriting in this same call.
    SKIN:Bang('!SetVariable', 'StackH', tostring(StackHeight()))

    local body = readAll(filePath)
    if not body then body = '' end

    -- Re-laying out the stack on every tick would fight the user's scrolling
    -- and waste work. Only rebuild when the transcript actually changed.
    if body == lastSig then return 0 end
    lastSig = body

    local msgs = parse(body)

    -- Keep the newest messages that fit the pool.
    local first = 1
    if #msgs > slots then first = #msgs - slots + 1 end

    local shown = 0
    for i = first, #msgs do
        shown = shown + 1
        local m = msgs[i]
        if m.text ~= '' then
            local n    = tostring(shown)
            local mine = (m.role == 'You')

            -- Escape quotes so the bang does not terminate early on a reply
            -- containing a double quote.
            local safe = m.text:gsub('"', '\'')

            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Text', 'Text', safe)
            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Text', 'StringAlign',
                      mine and 'Right' or 'Left')
            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Text', 'X',
                      mine and '#MsgRightX#' or '#MsgLeftX#')
            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Text', 'FontColor',
                      mine and '#MsgUserText#' or '#MsgBotText#')
            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Text', 'Hidden', '0')

            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Bubble', 'Hidden', '0')
            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Bubble', 'Shape',
                      'Rectangle ' .. (mine and '#MsgBubbleUserX#' or '#MsgBubbleBotX#') ..
                      ',0,#MsgBubbleW#,([MeterMsg' .. n .. 'Text:H] + 12),9 | ' ..
                      (mine and '#MsgUserStyle#' or '#MsgBotStyle#'))

            -- Only Chatty gets a face. The user does not need to be reminded
            -- what they look like.
            SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Face', 'Hidden',
                      mine and '1' or '0')
        else
            shown = shown - 1
        end
    end

    -- Blank the rest of the pool. Unused slots sit at the END of the stack, so
    -- hiding them cannot break the relative positioning of the visible ones.
    for n = shown + 1, slots do
        SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Text', 'Text', '')
        SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Text', 'Hidden', '1')
        SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Bubble', 'Hidden', '1')
        SKIN:Bang('!SetOption', 'MeterMsg' .. n .. 'Face', 'Hidden', '1')
    end

    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
    return shown
end

-- Total pixel height of the drawn stack, so the scroll clamp knows how far it
-- may travel. Read by the skin AFTER the meters have been updated.
function StackHeight()
    local total = 0
    for n = 1, slots do
        local m = SKIN:GetMeter('MeterMsg' .. n .. 'Text')
        if m then
            local h = m:GetH()
            if h and h > 0 then total = total + h + 18 end
        end
    end
    return total
end
