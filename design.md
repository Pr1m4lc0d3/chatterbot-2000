# Chatterbot 2000 - design

Rebuild, 2026-08-01. Replaces the 2026-06-15 build.

## Why it was rebuilt

The previous version worked by popping a **WinForms modal** (`TopMost=$true`,
`StartPosition=CenterScreen`) to collect input. That is not a desktop widget; it
seizes the foreground. Alongside that:

- `deepseek.ps1` owned presentation â€” it word-wrapped to a fixed 40 characters and
  laid out the transcript, duplicating work Rainmeter already does better.
- Errors were truncated to 55 characters, hiding every real API failure.
- `Update=50` redrew the whole skin 20Ã—/sec, permanently, to animate scanlines.
- The model was declared twice (`config.json` and `[Variables] Model=`) and could drift.
- `Format-Display` indexed `$chat[0..-1]` when history was empty, walking backwards.

The visual identity was not the problem. The engineering was.

## Verified facts (probed 2026-08-01, not assumed)

- `GET /models` on this key returns exactly **`deepseek-v4-flash`** and **`deepseek-v4-pro`**.
- **`deepseek-chat` still works** â€” it is a live alias, not a dead ID. It routes to V4 with
  thinking disabled.
- **`deepseek-v4-flash` has reasoning ON by default.** With `max_tokens=5` it spent all 5
  tokens reasoning and returned **empty content with HTTP 200**. A small token budget
  therefore produces a *blank* answer, not an error. This is the single nastiest failure
  mode and the design handles it explicitly.
- `thinking={"type":"disabled"}` turns reasoning off.

## Shape

Three units, one job each.

| Unit | Owns | Must not |
|---|---|---|
| `Chatterbot 2000.ini` | layout, input, scrolling, state display | know about HTTP or JSON |
| `@Resources\deepseek.ps1` | POST, read SSE, append text, write state | format, wrap or lay out |
| `@Resources\reader.lua` | hand a file's contents to a measure | parse or transform |

### Files

```
Skins\Chatterbot 2000\
  design.md                 this document
  Chatterbot 2000.ini      UI only
  @Resources\
    Variables.inc           style, panel size, model â€” single source of truth
    config.json             ApiKey only
    deepseek.ps1            network only
    reader.lua              file -> measure
    launch.vbs              starts the client for a question â€” see below
    clear.vbs               starts the client to wipe history â€” see below
    Fonts\Quicksand.ttf     copied from Mergic
    transcript.txt          conversation as plain text
    state.txt               SENDING | STREAMING | READY | ERROR
    conversation.json       history, for context on the next turn
```

Removed as dead or superseded: `launch.bat`, `clear.bat`, `launcher.lua`,
`response-reader.lua`, `status-reader.lua`, `response.txt`, `status.txt`.

## Why the skin calls a .vbs and never powershell.exe directly

**Do not "simplify" this back into a direct `["powershell.exe" "..."]` action.** That was
tried and it fails in two different ways, neither of which is obvious:

Rainmeter's `["program" "params"]` action accepts **exactly one** parameter string.

- Wrap the whole flag list in one pair of quotes and it arrives as a *single* argv
  element. PowerShell tries to run `-NoProfile` as a command, prints a red error, and
  exits â€” a console window flashes and nothing else happens.
- Split it into separately quoted tokens and only the first survives. PowerShell starts
  with nothing but `-NoProfile`, which means an **interactive console that sits there
  waiting for input forever**. The panel looks dead; there is no error to find.

Both failures are silent from the skin's side: `query.ini` gets written, so the skin
believes it worked. `launch.vbs` and `clear.vbs` take **no arguments at all**, so there is
nothing left to misparse. They also run PowerShell through `WScript.Shell.Run` with window
style `0`, which hides the console completely â€” `-WindowStyle Hidden` does not, it always
flashes one.

`launch.vbs` writes `SENDING` to `state.txt` before starting PowerShell, so a keystroke is
acknowledged in the panel within ~200 ms whatever happens downstream. A panel stuck on
`SENDING` means the client never launched â€” the failure that previously presented as a
silently dead terminal.

## Tools â€” the model can reach the real world

`deepseek.ps1` decides **when** to call a tool; `tools.ps1` decides **how**. Verified
against the live API: DeepSeek streams `tool_calls` deltas and ends the turn with
`finish_reason: tool_calls`, so tool use and streaming coexist â€” one code path, no
degrading to a blocking request.

The loop: stream â†’ if `finish_reason` is `tool_calls`, run them, append the assistant's
`tool_calls` message plus one `role:"tool"` reply per call, go round again. Bounded at
6 rounds, and **on the last round `tool_choice` flips to `none`** so a model that keeps
searching is forced to answer from what it has. Without that the user gets an error
message instead of the answer that was one step away â€” observed, not theorised.

| Tool | Backend | Key |
|---|---|---|
| `get_weather` | Open-Meteo geocoding + forecast | none, and none needed |
| `web_search` | Tavily if `config.json` has `SearchApiKey`, else DuckDuckGo scrape | Tavily key present |

**The system prompt carries today's date, and this is not cosmetic.** Without it the model
treats the last event in its training data as "the most recent" and reports a years-old
result as current *while holding fresh search results in context*. Observed: asked who won
the most recent Super Bowl it answered LVIII (Feb 2024); with the date injected, LX
(Feb 2026), correctly. The prompt also forbids referring to "result 3" and similar - the
user never sees the raw result list.

## Collapse to header

Clicking the **title** toggles `Collapsed`; clicking the **gear** toggles `View`. Each
click sets exactly ONE variable. A `Calc` measure folds them into a single number,
`(#Collapsed# * 2) + #View#`, and its IfConditions fire `!ShowMeterGroup` and
`!HideMeterGroup` for `ChatView` and `SettingsView`. Meters declare which view they
belong to and nothing else.

**Two earlier approaches failed and are worth not repeating.** Computing visibility
inside the toggle action does not work: Rainmeter resolves every `#Variable#` in an
action string ONCE, before any bang in it runs, so a bang reading `#Collapsed#` after
another bang had just changed it still saw the old value. Collapsing from the settings
view therefore left the settings meters drawn outside a panel that had already shrunk to
header height. Writing `(1 - #Collapsed#)` to fake the new value did not fix it either.
Putting a formula in `Hidden` is also unreliable: the chat meters honoured it while the
settings meters ignored the `Collapsed` half. Group membership plus a measure has no
ordering left to get wrong.

The window *rectangle* does not shrink when collapsed; only the drawn shape does.
Rainmeter will not recompute `DynamicWindowSize` without a refresh, and a refresh would
reset the scroll position. The leftover area is fully transparent and Rainmeter hit-tests
only non-transparent pixels, so it captures nothing.

`Collapsed` resets to 0 whenever Rainmeter reloads - it is runtime state, not a setting.

## Clickable sources

Three link slots sit between the transcript and the input box. `deepseek.ps1` pushes
`Link1Text`/`Link1Url` .. `Link3*` plus `SourcesLabel` in with `!SetVariable` bangs after
each turn, and skips the whole push when the slot contents are unchanged, so a plain chat
turn does not spawn eight processes. Bangs rather than `!Refresh` because a refresh resets
the scroll position mid-conversation.

Each source is a **full-width pill** (`Rectangle 0,0,(#PanelW# - 36),18,9`) with its caption
centred via `StringAlign=CenterCenter` at `X=(#PanelW# / 2)`. The pill and the caption both
carry the click action: the caption is drawn on top, so an action on the pill alone would
not reliably catch a click on the words themselves.

Empty slots are hidden by pushing a **transparent pill style**, not by `!HideMeter`. The
`Hidden` option is already driven by `#Collapsed#`, and a bang would be overwritten the
next time that option re-evaluated. `Pill1Style`..`Pill3Style` carry the whole
`FillColor ... | StrokeColor ...` fragment, so one variable per pill does the job, and the
colours are read from `Variables.inc` rather than duplicated in the script.

The panel carries a 1px `#BorderColor#` stroke to match the Mergic skins. Note this makes
the window one pixel wider and taller than `PanelW`/`PanelH` - 381x523, not 380x522 - which
matters when locating the window programmatically.

Note for future edits: **adding meters or changing `PanelH` needs `!DeactivateConfig` then
`!ActivateConfig`.** A plain `!Refresh` picked up option changes but did not resize the
window or register the new meters.

**The DuckDuckGo fallback is best-effort and will fail.** It works for a handful of
queries and then serves a CAPTCHA â€” measured 6 of 6 blocked once it noticed us. When
blocked, `web_search` returns an explicit *"WEB SEARCH UNAVAILABLE, do not retry"*, which
matters: the earlier wording "No results found" read to the model as "that thing doesn't
exist" and it burnt every round rephrasing. Adding a `SearchApiKey` to `config.json`
switches to Tavily silently â€” no other change needed.

Tool results are **never persisted** to `conversation.json`. A `tool_calls` message is
only valid immediately before its matching replies, so replaying half that pair on the
next turn is an API error. `$baseMessages` keeps the clean user/assistant history.

## File encodings â€” transcript.txt is NOT UTF-8

| File | Encoding | Why |
|---|---|---|
| `transcript.txt` | **Windows-1252** | Rainmeter's Lua path reads it as CP1252 |
| `conversation.json` | UTF-8 no BOM | goes to the API as JSON |
| `state.txt` | ASCII | one word |

**Do not "standardise" the transcript to UTF-8.** It was UTF-8 and it was wrong.
Every curly apostrophe the model emits (`'`, U+2019 = `E2 80 99`) rendered on the panel as
`Ã¢â‚¬â„¢`, and every em dash as `Ã¢â‚¬"`. Verified by writing the same three characters both ways
and photographing the panel: the UTF-8 line reads `donÃ¢â‚¬â„¢t Ã¢â‚¬" cafÃƒÂ©`, the CP1252 line
reads `don't â€” cafÃ©`.

CP1252 covers smart quotes, dashes and accented Latin â€” everything English prose needs.
Characters outside it degrade to `?`, which is a fair trade against mojibake on every reply.

## Rendering and scrolling

Rainmeter does the typography. `MeterTranscript` sets **only `W`**, so Rainmeter wraps
using real glyph metrics and the meter grows to whatever height the text needs.

This matters because the chosen font, **Quicksand, is proportional**. Character-count
wrapping â€” what the old build did â€” assumes fixed glyph width. It is correct for Consolas
and wrong for Quicksand. No wrapping code exists anywhere in this design.

`Container=MeterViewport` clips the transcript to the visible panel. Scrolling is
`Y=(0-#Scroll#)`, clamped to `max(0, [MeterTranscript:H] - viewport height + #BottomPad#)`
via `DynamicVariables=1`. Both `Container` and `[MeterName:H]` were confirmed against the
Rainmeter 4.5 manual before being designed in.

`OnChangeAction` must run `!UpdateMeter *` **before** it reads `[MeterTranscript:H]`:

```
OnChangeAction=[!UpdateMeter *][!SetVariable Scroll "(...)"][!UpdateMeter *][!Redraw]
```

Read the height first and it is the height of the *previous* render, so the follow-the-
stream scroll lands one chunk short and the tail of every reply sits just below the mask.
That presents as the model truncating its answer, which it is not â€” the full text is in
`transcript.txt`. `BottomPad` then buys a few pixels so the last line cannot lose a row to
rounding.

While a reply streams the view pins to the bottom, **unless** the user has scrolled up,
in which case position is left alone.

**The mouse wheel scrolls history**, so this skin deliberately does not adopt Mergic's
wheel-to-resize gesture. Panel size is `#PanelW#` / `#PanelH#` in `Variables.inc`.

## Data flow

1. User types in the inline `InputText` box and presses Enter.
2. Rainmeter launches `deepseek.ps1` hidden, passing the query.
3. Script appends the user line to `transcript.txt`, writes `STREAMING` to `state.txt`.
4. Script POSTs with `stream:true`, reads SSE deltas, appends content to `transcript.txt`
   throttled to ~10 writes/sec.
5. `reader.lua` re-reads the file 8Ã—/sec; the String meter redraws.
6. On completion the script writes `conversation.json` and sets `state.txt` to `READY`.

History sent back for context is bounded to the system message plus the last 20 messages.

## Error handling

Failures are written into the transcript **in full** â€” HTTP status and response body.
No truncation. Three cases are named explicitly rather than surfacing as silence:

- **Blank reply** â€” detected as empty content with `reasoning_tokens > 0`, and reported
  as a token-budget problem. `max_tokens` defaults to 2000 so reasoning cannot starve
  the answer.
- **Missing or rejected key** â€” names `@Resources\config.json` as the file to fix.
- **Network / timeout** â€” the question is left in the input box so it needn't be retyped.

## Model switching

The footer line already displays the model. It becomes the control: clicking it cycles
`v4-flash` â†’ `v4-flash + thinking` â†’ `v4-pro + thinking` and writes the choice to
`Variables.inc`. No new buttons; an existing element is made useful.

Model is declared in `Variables.inc` only. `config.json` holds the API key and nothing else.

## Verification

`deepseek.ps1` accepts `-Prompt "..."` and runs standalone in a terminal, so streaming,
the error paths and the blank-reply path are all testable without Rainmeter. Then:
Rainmeter refresh with logging enabled, confirm zero errors, and capture the live window
via `PrintWindow` (flag 2) rather than disturbing the desktop.

Each query spawns exactly one PowerShell process, which exits on completion. Verified
that none are left behind.

## Deliberately not built

- No streaming of *reasoning* text â€” only the answer is shown.
- No markdown rendering. Rainmeter has no rich text; the system prompt asks for plain prose.
- No multi-conversation management. One transcript, cleared on demand.

## Persona - the skin is a shell

Nothing identifying the terminal is hardcoded any more. `BotName`, `BotAsk`,
`BotFace` and `BotPrompt` in `config.json` let a different character inhabit the
same skin: the header reads `Apothecary 2000`, the input reads
`Ask the Apothecary...`, the face changes, and it answers as the Apothecary.

`config.ps1` pushes them with the same `!SetVariable` mechanism that already
feeds the provider row. **Empty fields are not pushed**, so a half-configured
persona falls back to the Chatty defaults in `Variables.inc` rather than
blanking the header.

Two things deliberately do NOT change with the persona:

- **The transcript still labels replies `Chatty`.** That is a protocol token
  `chat.lua` parses on, not a display name - bubbles show a face, never a label.
  Renaming it would break the renderer for no visible gain.
- **`BotPrompt` replaces the identity sentence only.** The rendering and tool
  rules are always appended, because they describe the surface the persona is
  speaking through. A persona that "forgot" them would emit markdown into a
  panel that cannot draw it.

The footer keeps showing `provider - model`, so the platform stays visible even
when the header carries a borrowed name.

Changing `BotFace` or the branding needs the skin reloaded once, since the
variables are read at load; after that, pushes apply live.

## Message bubbles

The conversation is NOT one String meter any more. One meter carries one alignment, one
colour and one block of text, so it structurally cannot put the user on the right, draw
a bubble behind each message, or place a face beside a reply.

`chat.lua` reads `transcript.txt`, splits it on the `You` / `Chatty` speaker lines, and
drives a fixed pool of 12 message slots via `SKIN:Bang` with `!SetOption`. That runs
**in process** - doing it from PowerShell would mean a process launch per option per
message.

Each slot is Bubble, Face, Text in that order, because Rainmeter draws in file order and
the bubble must sit behind its own text. Slots stack with `Y=14R` so each grows with its
own wrapped text; only slot 1 is absolute and carries the scroll offset for the whole
stack. Unused slots are hidden at the END of the stack, where hiding them cannot break
the relative positioning of the visible ones.

Bubbles are fixed max-width. A String meter with `W` set reports that `W`, so a shape
cannot measure the real ink in order to hug it.

`StackHeight()` publishes the drawn height into `#StackH#` for the scroll clamp. It lags
a rebuild by one tick, which is invisible in use and far safer than reading heights of
meters being rewritten in the same call.

## Reading a file for changes

`reader.lua` compares CONTENT, not size. Size was the original shortcut and it was
wrong: `STREAMING` and `SEARCHING` are both nine bytes, so a search turning into a reply
never changed the size and the header sat on the stale label indefinitely.

## Packaging

A `.rmskin` is a **ZIP** - not 7-Zip, whatever the web claims - with a 16-byte footer:

```c
struct PackageFooter { __int64 size; BYTE flags; char key[7]; };  // "RMSKIN\0"
```

Confirmed in Rainmeter's own Library/DialogPackage.cpp and DialogInstall.h.

Two traps: entry paths must use **forward slashes** (.NET Framework
`ZipFile.CreateFromDirectory` writes backslashes, and the package then fails to install),
and `RMSKIN.bmp` must be **exactly 400x60**.

`config.json` is excluded from the package and from git. It holds live API keys.
