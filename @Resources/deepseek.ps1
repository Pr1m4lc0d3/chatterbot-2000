# =============================================================================
#  Chatterbot 2000 - network client
#
#  Owns exactly one thing: talking to an OpenAI-compatible API and appending
#  to transcript.txt as it streams in.
#
#  It does NOT wrap, format or lay out text. Rainmeter does that, using real
#  glyph metrics. See design.md.
#
#  Runs standalone for testing, with no Rainmeter involved:
#      powershell -File deepseek.ps1 -Prompt "hello"
#      powershell -File deepseek.ps1 -ClearHistory
# =============================================================================
param(
    [string] $Prompt,
    [switch] $FromQueryFile,
    [switch] $ClearHistory
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Res            = $PSScriptRoot
$ConfigFile     = Join-Path $Res 'config.json'
$VarsFile       = Join-Path $Res 'Variables.inc'
$QueryFile      = Join-Path $Res 'query.ini'
$TranscriptFile = Join-Path $Res 'transcript.txt'
$StateFile      = Join-Path $Res 'state.txt'
$ConvFile       = Join-Path $Res 'conversation.json'

# Tool implementations live next door. This file decides WHEN to call one;
# tools.ps1 decides HOW. Both keyless - no API key beyond DeepSeek's own.
. (Join-Path $Res 'tools.ps1')

$Utf8 = New-Object Text.UTF8Encoding($false)   # no BOM - for JSON and state

# The transcript is the one file Rainmeter renders, and Rainmeter's Lua path
# reads it as Windows-1252, NOT UTF-8. Writing UTF-8 here puts a literal
# "don<a-circumflex><euro><tm>t" on the panel for every curly apostrophe the
# model emits. Verified visually side by side: same three characters written
# UTF-8 render as mojibake, written CP1252 render as don't - cafe correctly.
# CP1252 covers smart quotes, dashes and accented Latin, which is everything
# English prose needs. Anything outside it degrades to "?" rather than garbage.
$Panel = [Text.Encoding]::GetEncoding(1252)

function Write-State { param([string]$s) [IO.File]::WriteAllText($StateFile, $s, $Utf8) }
function Append      { param([string]$s) [IO.File]::AppendAllText($TranscriptFile, $s, $Panel) }
function Set-Transcript { param([string]$s) [IO.File]::WriteAllText($TranscriptFile, $s, $Panel) }

# -- Clickable sources --------------------------------------------------------
# The skin has three link slots. Their URLs must be Rainmeter variables, because
# a mouse action needs the address at click time - so they are pushed in with
# bangs rather than written to a file the skin reads. Bangs and not !Refresh: a
# refresh would reset the scroll position mid-conversation.
#
# This lives above the -ClearHistory branch on purpose: clearing the panel has
# to clear the links too, and PowerShell needs the function defined first.
$LinkSlots    = 3
$LinksFile    = Join-Path $Res 'links.txt'
$RainmeterExe = @(
    'C:\Program Files\Rainmeter\Rainmeter.exe',
    'C:\Program Files (x86)\Rainmeter\Rainmeter.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

function Push-Links {
    param([object[]]$Links)

    $slots = @()
    for ($i = 0; $i -lt $LinkSlots; $i++) {
        if ($i -lt $Links.Count -and $Links[$i].url) {
            # Titles travel through a command line before they reach Rainmeter,
            # which mangles anything non-ASCII - a page titled with a
            # non-breaking space arrived as "YouTube <A-circumflex>|". Fold the
            # common offenders to their plain equivalents and drop the rest.
            $t = "$($Links[$i].title)" -replace '"', "'"
            #
            # Written with CHAR CODES, not literal characters. This file is read by
            # Windows PowerShell 5.1, which decodes a .ps1 as ANSI unless it has a
            # BOM. Literal curly quotes here were silently re-encoded into mojibake
            # by a later rewrite and broke the whole script's syntax - which meant
            # the skin stopped answering entirely, not just this one function.
            $nbsp   = [string][char]0x00A0 + [char]0x2007 + [char]0x202F
            $sQuote = [string][char]0x2018 + [char]0x2019 + [char]0x201B
            $dQuote = [string][char]0x201C + [char]0x201D
            $dashes = [string][char]0x2010 + [char]0x2011 + [char]0x2012 + [char]0x2013 + [char]0x2014 + [char]0x2015
            $t = $t -replace "[$nbsp]", " "
            $t = $t -replace "[$sQuote]", "'"
            $t = $t -replace "[$dQuote]", "'"
            $t = $t -replace "[$dashes]", "-"
            $t = $t -replace ([string][char]0x2026), "..."
            $t = ($t -replace '[^\x20-\x7E]', '') -replace '\s+', ' '
            $t = $t.Trim()
            if (-not $t) { $t = $Links[$i].url }
            if ($t.Length -gt 46) { $t = $t.Substring(0, 45) + '...' }
            $slots += [PSCustomObject]@{ text = $t; url = "$($Links[$i].url)" }
        } else {
            $slots += [PSCustomObject]@{ text = ''; url = '' }
        }
    }

    # Skip entirely when nothing changed - a plain chat turn should not pay for
    # eight process launches just to rewrite the same empty slots.
    $sig = ($slots | ForEach-Object { "$($_.text)|$($_.url)" }) -join "`n"
    $old = ''
    if (Test-Path $LinksFile) { try { $old = [IO.File]::ReadAllText($LinksFile, $Utf8) } catch { } }
    if ($sig -eq $old) { return }
    [IO.File]::WriteAllText($LinksFile, $sig, $Utf8)

    if (-not $RainmeterExe) { return }

    # PowerShell DROPS an empty-string argument when calling a native exe, so
    #   & rainmeter.exe !SetVariable Link1Url '' Chatterbot 2000
    # arrives as  !SetVariable Link1Url Chatterbot 2000  - the config name
    # slides into the value slot and every empty link becomes the literal text
    # "Chatterbot 2000", complete with a hand cursor that opens nothing.
    # Passing the two characters "" instead survives the call and Rainmeter
    # reads it as an empty value.
    function Arg { param([string]$v) if ([string]::IsNullOrEmpty($v)) { '""' } else { $v } }

    # The heading only exists when there is something under it, otherwise the
    # panel carries a bare "SOURCES" over empty space on every non-search turn.
    $label = if ($slots[0].url) { 'SOURCES' } else { '' }
    & $RainmeterExe !SetVariable 'SourcesLabel' (Arg $label) 'Chatterbot 2000' 2>$null

    # Pill colours come from Variables.inc so the styling stays in the style
    # file rather than being duplicated here.
    $fill = '255,255,255,20'; $stroke = '255,255,255,70'
    if (Test-Path $VarsFile) {
        $vt = Get-Content $VarsFile -Raw
        $m1 = [regex]::Match($vt, '(?m)^\s*PillColor\s*=\s*(.+?)\s*$')
        $m2 = [regex]::Match($vt, '(?m)^\s*PillStroke\s*=\s*(.+?)\s*$')
        if ($m1.Success) { $fill   = $m1.Groups[1].Value }
        if ($m2.Success) { $stroke = $m2.Groups[1].Value }
    }
    $shown  = "FillColor $fill | StrokeColor $stroke"
    $hidden = 'FillColor 0,0,0,0 | StrokeColor 0,0,0,0'

    for ($i = 0; $i -lt $LinkSlots; $i++) {
        $n = $i + 1
        $style = if ($slots[$i].url) { $shown } else { $hidden }
        & $RainmeterExe !SetVariable "Link${n}Text"  (Arg $slots[$i].text) 'Chatterbot 2000' 2>$null
        & $RainmeterExe !SetVariable "Link${n}Url"   (Arg $slots[$i].url)  'Chatterbot 2000' 2>$null
        & $RainmeterExe !SetVariable "Pill${n}Style" $style                'Chatterbot 2000' 2>$null
    }
    & $RainmeterExe !UpdateMeter '*' 'Chatterbot 2000' 2>$null
    & $RainmeterExe !Redraw 'Chatterbot 2000' 2>$null
}

# -- Clear -------------------------------------------------------------------
if ($ClearHistory) {
    [IO.File]::WriteAllText($ConvFile, '[]', $Utf8)
    Set-Transcript ''
    Push-Links @()          # empty the Sources strip along with the conversation
    Write-State 'READY'
    exit 0
}

# -- Where is the question? --------------------------------------------------
if ($FromQueryFile) {
    if (Test-Path $QueryFile) {
        $line = Get-Content $QueryFile -Encoding UTF8 | Where-Object { $_ -match '^\s*Query\s*=' } | Select-Object -First 1
        if ($line) { $Prompt = ($line -replace '^\s*Query\s*=\s*', '').Trim().Trim('"') }
    }
}
if ([string]::IsNullOrWhiteSpace($Prompt)) { exit 0 }

# -- Don't let two queries interleave into the same file ---------------------
if (Test-Path $StateFile) {
    $st = (Get-Content $StateFile -Raw -EA SilentlyContinue)
    # SEARCHING counts too - a tool round is still an in-flight answer. SENDING
    # must NOT count: launch.vbs writes it moments before starting this script.
    if (($st -eq 'STREAMING' -or $st -eq 'SEARCHING') -and
        ((Get-Date) - (Get-Item $StateFile).LastWriteTime).TotalSeconds -lt 180) {
        exit 0
    }
}

# -- Config ------------------------------------------------------------------
if (-not (Test-Path $ConfigFile)) {
    Append "`r`nChatty`r`nNo config.json found. Create @Resources\config.json containing:`r`n{ `"ApiKey`": `"sk-...`" }`r`n`r`n"
    Write-State 'ERROR'; exit 1
}
$cfg     = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
$ApiKey  = "$($cfg.ApiKey)"
$BaseUrl = "$($cfg.BaseUrl)"
if ([string]::IsNullOrWhiteSpace($BaseUrl)) { $BaseUrl = 'https://api.deepseek.com' }
$BaseUrl = $BaseUrl.TrimEnd('/')

# Local providers (Ollama, LM Studio) authenticate nothing, so a key is only
# required when we are talking to something off this machine. Nor is the key
# checked for an "sk-" prefix any more - that is DeepSeek and OpenAI's format,
# and this now speaks to anything OpenAI-compatible.
$IsLocal = $BaseUrl -match '://(localhost|127\.0\.0\.1|\[::1\])'
if (-not $IsLocal -and [string]::IsNullOrWhiteSpace($ApiKey)) {
    Append "`r`nChatty`r`nNo API key. Put your DeepSeek key in @Resources\config.json under `"ApiKey`".`r`n`r`n"
    Write-State 'ERROR'; exit 1
}

# -- Model mode, read from the single source of truth ------------------------
$mode = 0
if (Test-Path $VarsFile) {
    $m = [regex]::Match((Get-Content $VarsFile -Raw), '(?m)^\s*ModelMode\s*=\s*(\d+)')
    if ($m.Success) { $mode = [int]$m.Groups[1].Value }
}
$Model = "$($cfg.Model)"
if ([string]::IsNullOrWhiteSpace($Model)) { $Model = 'deepseek-v4-flash' }

# "thinking" is a DeepSeek extension. Sending it to OpenAI or a local model is
# at best ignored and at worst a 400, so it only goes out to DeepSeek.
$IsDeepSeek = $BaseUrl -match 'deepseek'
$Thinking   = $IsDeepSeek -and ($mode -ge 1)

# -- Conversation history ----------------------------------------------------
# WHO is speaking is swappable; HOW the panel works is not. A persona supplies
# the identity line only, and still inherits the rendering and tool rules below,
# because those describe the surface it is speaking through - a persona that
# forgot them would emit markdown into a panel that cannot render it.
#
# Note the transcript still labels replies "Chatty". That is a protocol token
# chat.lua parses on, not a display name: the bubbles show a face, never a
# label. Renaming it would break the renderer for no visible gain.
$identity = "$($cfg.BotPrompt)"
if ([string]::IsNullOrWhiteSpace($identity)) {
    $identity = 'You are Chatty, the assistant inside a small desktop panel called Chatterbot 2000. If you are asked who or what you are, you are Chatty.'
}

$sysMsg = [PSCustomObject]@{
    role    = 'system'
    # The date matters more than it looks. Without it the model treats the last
    # event in its training data as "the most recent", and confidently reports a
    # years-old result as current even while holding fresh search results.
    content = ("Today's date is " + (Get-Date -Format 'dddd, d MMMM yyyy') + ". " +
        $identity + ' Answer in plain prose. ' +
        'Never use markdown, asterisks, backticks or headers - they cannot be rendered. ' +
        'Keep answers tight unless asked to expand. ' +
        'You have live tools: web_search for anything current or beyond your training data, and ' +
        'get_weather for real measured conditions. Use them rather than saying you cannot know something. ' +
        'Never claim you lack internet access - you can search. ' +
        'Name the source in prose when you use a search result, e.g. "according to ESPN". ' +
        'Never refer to "result 3" or similar numbering - the user cannot see the raw results. ' +
        'Check dates in search results against today''s date before calling anything the latest or most recent. ' +
        'If the user asks for a link, a URL, or where to find something, ALWAYS call web_search even if you ' +
        'think you know the address - the panel turns search results into clickable links beneath your answer, ' +
        'and a URL you merely type out is not clickable.')
}
$messages = @($sysMsg)
if (Test-Path $ConvFile) {
    try {
        # Two Windows PowerShell 5.1 traps live in these three lines:
        #  1. @($text | ConvertFrom-Json) wraps the WHOLE array as one element,
        #     so history silently vanishes. Assign first, then wrap.
        #  2. Set-Content -Encoding UTF8 emits a BOM, which can survive into
        #     the string. Strip it before parsing.
        $raw    = [IO.File]::ReadAllText($ConvFile, $Utf8).TrimStart([char]0xFEFF)
        $parsed = ConvertFrom-Json -InputObject $raw
        $loaded = @($parsed)
        # Windows PowerShell 5.1 does not return an empty array for '[]' - it
        # returns a wrapper object with .value/.Count and no 'role' property.
        # Sending that to the API yields: messages[1]: missing field `role`.
        # So keep only entries that really are chat messages.
        $chat = @($loaded | Where-Object {
            $_ -and
            ($_.PSObject.Properties.Name -contains 'role') -and
            $_.role -and $_.role -ne 'system' -and $_.content
        })
        if ($chat.Count -gt 0) { $messages = @($sysMsg) + $chat }
    } catch { $messages = @($sysMsg) }
}
$messages += [PSCustomObject]@{ role = 'user'; content = $Prompt }

# -- Echo the question, then stream the answer in beneath it -----------------
if ((Test-Path $TranscriptFile) -and (Get-Item $TranscriptFile).Length -gt 0) { Append "`r`n" }
Append "You`r`n$Prompt`r`n`r`nChatty`r`n"
Write-State 'STREAMING'

Add-Type -AssemblyName System.Net.Http

$answer    = New-Object Text.StringBuilder
$pending   = New-Object Text.StringBuilder
$reasonTok = 0
$client    = $null
$reader    = $null

# What gets saved at the end. The live $messages list also accumulates the
# assistant's tool_calls and the tool results, and those must NOT be persisted:
# a tool_calls message is only valid immediately before its matching tool
# replies, so replaying a half of that pair on the next turn is an API error.
$baseMessages = @($messages)

function Flush-Pending {
    if ($pending.Length -gt 0) { Append $pending.ToString(); [void]$pending.Clear() }
}


try {
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(180)

    # Each pass is one call to the API. A pass that ends in tool_calls runs the
    # tools, feeds the results back, and goes round again. Bounded so a model
    # that keeps asking for tools can never spin forever.
    $maxRounds = 6
    $round     = 0
    $finish    = ''

    while ($true) {
        $round++
        if ($round -gt $maxRounds) {
            Append "`r`n[stopped after $maxRounds tool rounds without a final answer]`r`n`r`n"
            Write-State 'ERROR'; exit 1
        }

        $body = @{
            model          = $Model
            messages       = @($messages)
            stream         = $true
            stream_options = @{ include_usage = $true }
            max_tokens     = 2000
            tools          = @(Get-ToolSpecs)
            # On the last permitted round, take the tools away. A model that
            # keeps searching without committing then has no choice but to
            # answer from what it already gathered. Without this the user gets
            # an error message instead of the answer that was one step away.
            tool_choice    = $(if ($round -ge $maxRounds) { 'none' } else { 'auto' })
        }
        if ($IsDeepSeek) { $body.thinking = @{ type = $(if ($Thinking) { 'enabled' } else { 'disabled' }) } }
        $json = $body | ConvertTo-Json -Depth 12 -Compress

        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, "$BaseUrl/chat/completions")
        if ($ApiKey) { [void]$req.Headers.TryAddWithoutValidation('Authorization', "Bearer $ApiKey") }
        $req.Content = New-Object System.Net.Http.StringContent($json, [Text.Encoding]::UTF8, 'application/json')

        $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()

        if (-not $resp.IsSuccessStatusCode) {
            # Report the API's own words, in full. No truncation.
            $detail = ''
            try { $detail = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch { }
            Append "Request failed - HTTP $([int]$resp.StatusCode) $($resp.ReasonPhrase)`r`n$detail`r`n`r`n"
            Write-State 'ERROR'
            exit 1
        }

        $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
        $sw     = [Diagnostics.Stopwatch]::StartNew()

        # Tool calls arrive in fragments, keyed by index: the name lands in one
        # chunk and the JSON arguments are spread across many more.
        $calls  = @{}
        $finish = ''
        $roundHadContent = $false

        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not $line.StartsWith('data:')) { continue }
            $payload = $line.Substring(5).Trim()
            if ($payload -eq '[DONE]' -or $payload -eq '') { continue }

            try { $chunk = $payload | ConvertFrom-Json } catch { continue }

            if ($chunk.usage -and $chunk.usage.completion_tokens_details) {
                $reasonTok = [int]$chunk.usage.completion_tokens_details.reasoning_tokens
            }
            if ($chunk.choices -and $chunk.choices.Count -gt 0) {
                $delta = $chunk.choices[0].delta

                $piece = $delta.content
                if ($piece) {
                    $roundHadContent = $true
                    [void]$answer.Append($piece)
                    [void]$pending.Append($piece)
                }

                if ($delta.tool_calls) {
                    foreach ($tc in $delta.tool_calls) {
                        $ix = 0; if ($null -ne $tc.index) { $ix = [int]$tc.index }
                        if (-not $calls.ContainsKey($ix)) { $calls[$ix] = @{ id=''; name=''; args='' } }
                        if ($tc.id)                 { $calls[$ix].id   = $tc.id }
                        if ($tc.function.name)      { $calls[$ix].name = $tc.function.name }
                        if ($tc.function.arguments) { $calls[$ix].args += $tc.function.arguments }
                    }
                }

                if ($chunk.choices[0].finish_reason) { $finish = $chunk.choices[0].finish_reason }
            }

            # Throttle disk writes so the skin redraws smoothly without thrashing.
            if ($sw.ElapsedMilliseconds -ge 100) { Flush-Pending; $sw.Restart() }
        }
        Flush-Pending
        $reader.Dispose(); $reader = $null

        if ($finish -ne 'tool_calls' -or $calls.Count -eq 0) { break }

        # -- Run what the model asked for, then go round again ----------------
        # Models often narrate ("Let me search for that.") before calling a tool.
        # Without this break, that sentence and the real answer collide into one
        # run-on line when the next round's text streams in behind it.
        if ($roundHadContent) { [void]$answer.Append("`r`n"); Append "`r`n" }

        Write-State 'SEARCHING'

        $tcList = @()
        foreach ($ix in ($calls.Keys | Sort-Object)) {
            $c = $calls[$ix]
            if (-not $c.id) { $c.id = "call_$ix" }
            $tcList += [PSCustomObject]@{
                id       = $c.id
                type     = 'function'
                function = [PSCustomObject]@{ name = $c.name; arguments = $c.args }
            }
        }
        $messages += [PSCustomObject]@{ role = 'assistant'; content = ''; tool_calls = $tcList }

        foreach ($ix in ($calls.Keys | Sort-Object)) {
            $c = $calls[$ix]
            $result = Invoke-SkinTool -Name $c.name -ArgumentsJson $c.args
            $messages += [PSCustomObject]@{ role = 'tool'; tool_call_id = $c.id; content = "$result" }
        }

        Write-State 'STREAMING'
    }

    $text = $answer.ToString().Trim()

    if ($text -eq '') {
        # The trap: HTTP 200, no error, but reasoning ate the whole token budget.
        if ($reasonTok -gt 0) {
            Append "[no answer returned - reasoning used all $reasonTok tokens of the budget. Click the model line to switch off thinking, or raise max_tokens in deepseek.ps1.]`r`n`r`n"
        } else {
            Append "[no answer returned]`r`n`r`n"
        }
        Write-State 'ERROR'
        exit 1
    }

    Append "`r`n`r`n"

    # Persist history from the CLEAN list - system, prior turns, this question,
    # this answer. Tool plumbing is deliberately dropped: it was scaffolding for
    # this one reply and is invalid to replay on the next.
    $baseMessages += [PSCustomObject]@{ role = 'assistant'; content = $text }
    if ($baseMessages.Count -gt 21) {
        $baseMessages = @($baseMessages[0]) + @($baseMessages[($baseMessages.Count - 20)..($baseMessages.Count - 1)])
    }
    [IO.File]::WriteAllText($ConvFile, ($baseMessages | ConvertTo-Json -Depth 10), $Utf8)

    # Sources for whatever was just answered. Empty list clears the strip, so
    # last question's links never sit under this question's answer.
    Push-Links (Get-LastLinks)

    Write-State 'READY'
}
catch {
    Flush-Pending
    Append "`r`n[connection error] $($_.Exception.Message)`r`n`r`n"
    Write-State 'ERROR'
    exit 1
}
finally {
    if ($reader) { $reader.Dispose() }
    if ($client) { $client.Dispose() }
}
