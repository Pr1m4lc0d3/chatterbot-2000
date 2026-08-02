-- Hands the contents of a small text file to a Rainmeter measure.
-- The only thing this file does. It does not parse, wrap or transform.
--
-- The conversation is NOT read through here any more - chat.lua renders that
-- into message bubbles. This now serves state.txt for the header label.
--
-- Usage from the skin:
--   [MeasureX]
--   Measure=Script
--   ScriptFile=#@#reader.lua
--   File=#@#state.txt

function Initialize()
    filePath = SELF:GetOption('File')
    cached   = ''
end

function Update()
    local f = io.open(filePath, 'rb')
    if not f then
        cached = ''
        return 0
    end

    -- Compare CONTENT, not size. Size was a tempting shortcut and it was wrong:
    -- "STREAMING" and "SEARCHING" are both nine bytes, so a search turning into
    -- a reply never changed the size and the header kept showing the stale
    -- state indefinitely. These files are tiny; re-reading each tick costs
    -- nothing next to being silently wrong.
    cached = f:read('*a') or ''
    f:close()

    -- Returning the string directly is the current contract. GetStringValue()
    -- still works but Rainmeter logs it as deprecated.
    return cached
end
