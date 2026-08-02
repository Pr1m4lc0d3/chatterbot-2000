# =============================================================================
#  NEXUS // DeepSeek Terminal - tool layer
#
#  Owns exactly one thing: executing a tool the model asked for, and returning
#  plain text for it to read. It does not talk to DeepSeek and does not touch
#  the transcript - deepseek.ps1 does both.
#
#  Every source here is KEYLESS on purpose. No account, no API key to expire,
#  no monthly quota to run out of at the wrong moment.
#
#  Dot-sourced by deepseek.ps1:
#      . "$PSScriptRoot\tools.ps1"
#      $specs = Get-ToolSpecs
#      $text  = Invoke-SkinTool -Name 'web_search' -ArgumentsJson '{"query":"..."}'
# =============================================================================

$script:ToolUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

# Titles and URLs from the most recent search, for the clickable Sources strip.
# deepseek.ps1 reads this after a tool round and pushes it into the skin.
# The transcript itself cannot carry links: a Rainmeter String meter takes one
# mouse action for the whole meter, so a URL inside a paragraph can never be its
# own click target. Each source needs its own meter, hence this list.
$script:LastLinks = @()
$script:LastQuery = ''

# Search engines rank pages ABOUT a thing above the thing itself - ask for a
# link to YouTube and Wikipedia's article outranks youtube.com. When the query
# names a site, promote results actually hosted on it, shallowest path first,
# so "the link to X" leads with X's own page rather than an article about X.
function Get-LastLinks {
    if ($script:LastLinks.Count -le 1) { return $script:LastLinks }

    $words = @($script:LastQuery -split '[^A-Za-z0-9]+' |
               Where-Object { $_.Length -ge 4 } |
               ForEach-Object { $_.ToLower() })
    if ($words.Count -eq 0) { return $script:LastLinks }

    # NOTE: no Sort-Object -Stable here. That switch is PowerShell 6+, and this
    # runs under Windows PowerShell 5.1, where it throws and takes the whole
    # reply down with it. The explicit index keeps the original search order
    # among equally scored results.
    $ix = 0
    $scored = foreach ($l in $script:LastLinks) {
        $score = 0
        try {
            $u     = [Uri]$l.url
            $hostn = $u.Host -replace '^www\.', ''
            $stem  = ($hostn -split '\.')[0]
            foreach ($w in $words) {
                if ($stem -eq $w)        { $score += 5; break }
                if ($hostn -like "*$w*") { $score += 3; break }
            }
            # A homepage is a better "link to X" than a deep article on X.
            $depth = @($u.AbsolutePath -split '/' | Where-Object { $_ }).Count
            if ($depth -eq 0) { $score += 2 } elseif ($depth -eq 1) { $score += 1 }
        } catch { }
        [PSCustomObject]@{ link = $l; score = $score; ix = $ix }
        $ix++
    }
    return @($scored | Sort-Object -Property @{E='score';D=$true}, @{E='ix';D=$false} | ForEach-Object { $_.link })
}

# WMO weather codes. Open-Meteo returns a number; the model wants a word.
$script:WmoText = @{
    0='clear sky'; 1='mainly clear'; 2='partly cloudy'; 3='overcast'
    45='fog'; 48='depositing rime fog'
    51='light drizzle'; 53='moderate drizzle'; 55='dense drizzle'
    56='light freezing drizzle'; 57='dense freezing drizzle'
    61='light rain'; 63='moderate rain'; 65='heavy rain'
    66='light freezing rain'; 67='heavy freezing rain'
    71='light snow'; 73='moderate snow'; 75='heavy snow'; 77='snow grains'
    80='light rain showers'; 81='moderate rain showers'; 82='violent rain showers'
    85='light snow showers'; 86='heavy snow showers'
    95='thunderstorm'; 96='thunderstorm with light hail'; 99='thunderstorm with heavy hail'
}

# -- What the model is told it can call ---------------------------------------
function Get-ToolSpecs {
    @(
        @{ type = 'function'; function = @{
            name        = 'web_search'
            description = 'Search the web and return titles and snippets. Use for current events, facts you are unsure of, prices, people, products, or anything after your knowledge cutoff. Returns search result summaries, not full pages.'
            parameters  = @{ type='object'; properties=@{
                query = @{ type='string'; description='The search query, phrased as you would type it into a search engine.' }
            }; required=@('query') } } }

        @{ type = 'function'; function = @{
            name        = 'get_weather'
            description = 'Get real current weather and a 3-day forecast for a place, with actual measured numbers. Prefer this over web_search for any weather question.'
            parameters  = @{ type='object'; properties=@{
                location = @{ type='string'; description='City name, optionally with state or country, e.g. "Denver, Colorado".' }
            }; required=@('location') } } }
    )
}

# -- web_search ---------------------------------------------------------------
# Two backends. Tavily is used whenever config.json carries a "SearchApiKey";
# otherwise this falls back to scraping DuckDuckGo, which is free but is bot-
# detected under any sustained use - measured 6 of 6 queries served a CAPTCHA
# once it noticed us. Treat the fallback as best-effort, not as the product.
function Get-SearchKey {
    $cfg = Join-Path $PSScriptRoot 'config.json'
    if (-not (Test-Path $cfg)) { return '' }
    try { $k = (Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json).SearchApiKey } catch { return '' }
    if ([string]::IsNullOrWhiteSpace($k)) { return '' }
    return $k
}

function Invoke-WebSearch {
    param([string]$Query)
    if ([string]::IsNullOrWhiteSpace($Query)) { return 'No search query was supplied.' }
    $script:LastQuery = $Query      # used to rank the Sources strip, see Get-LastLinks

    $key = Get-SearchKey
    if ($key) { return Invoke-TavilySearch -Query $Query -Key $key }

    $url = 'https://html.duckduckgo.com/html/?q=' + [Uri]::EscapeDataString($Query)
    # -UseBasicParsing is mandatory: this runs under Windows PowerShell 5.1, where
    # Invoke-WebRequest otherwise tries to drive the Internet Explorer engine and
    # throws on any machine where IE has been removed.
    $resp = Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = $script:ToolUA } -TimeoutSec 25 -UseBasicParsing -ErrorAction Stop
    $html = $resp.Content

    # Say plainly that the channel is blocked. "No results found" reads as "that
    # thing does not exist", and the model burns every remaining round rephrasing
    # a query that was never going to be answered.
    if ($html -match 'Unfortunately, bots use DuckDuckGo too' -or $html -match 'confirm this search was made by a human') {
        return "WEB SEARCH UNAVAILABLE: the free search backend is currently blocking automated requests. Do not retry or rephrase - it will fail again. Answer from your own knowledge instead and tell the user plainly that you could not search and that your information may be out of date."
    }

    # Capture the whole anchor so the href comes with the title. DuckDuckGo wraps
    # every result in a redirector - //duckduckgo.com/l/?uddg=<encoded real url>
    # - so the real destination has to be pulled out and decoded.
    $anchors = [regex]::Matches($html, '(?s)(<a[^>]*class="result__a"[^>]*>)(.*?)</a>')
    $snips   = [regex]::Matches($html, '(?s)class="result__snippet"[^>]*>(.*?)</a>')
    if ($anchors.Count -eq 0) {
        return "WEB SEARCH UNAVAILABLE: the free search backend returned nothing for '$Query', which usually means it is throttling us rather than that no pages exist. Do not retry. Answer from your own knowledge and say your information may be out of date."
    }

    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("Search results for '$Query':")
    $take = [Math]::Min(6, $anchors.Count)
    for ($i = 0; $i -lt $take; $i++) {
        $t = Convert-HtmlToText $anchors[$i].Groups[2].Value
        $s = if ($i -lt $snips.Count) { Convert-HtmlToText $snips[$i].Groups[1].Value } else { '' }
        if ($s.Length -gt 300) { $s = $s.Substring(0, 300) + '...' }
        [void]$sb.AppendLine("$($i + 1). $t")
        if ($s) { [void]$sb.AppendLine("   $s") }

        $url = Resolve-DdgUrl $anchors[$i].Groups[1].Value
        if ($url) { $script:LastLinks += [PSCustomObject]@{ title = $t; url = $url } }
    }
    return $sb.ToString()
}

# DuckDuckGo hands back its own redirector. Unwrap it to the real destination,
# otherwise every "source" link would just bounce through duckduckgo.com.
function Resolve-DdgUrl {
    param([string]$AnchorTag)
    $m = [regex]::Match($AnchorTag, 'href="([^"]+)"')
    if (-not $m.Success) { return '' }
    $href = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
    $u = [regex]::Match($href, '[?&]uddg=([^&]+)')
    if ($u.Success) { return [Uri]::UnescapeDataString($u.Groups[1].Value) }
    if ($href -like '//*') { return 'https:' + $href }
    if ($href -like 'http*') { return $href }
    return ''
}

# -- Tavily: the real search backend, used when a key is present --------------
# Contract taken from docs.tavily.com: POST https://api.tavily.com/search with a
# Bearer token; body needs "query"; "include_answer" asks Tavily to synthesise a
# direct answer, which is far more useful to a model than six raw snippets.
function Invoke-TavilySearch {
    param([string]$Query, [string]$Key)

    $body = @{
        query          = $Query
        max_results    = 6
        search_depth   = 'basic'
        include_answer = $true
    } | ConvertTo-Json -Compress

    $resp = Invoke-RestMethod -Uri 'https://api.tavily.com/search' -Method Post `
            -Headers @{ 'Authorization' = "Bearer $Key"; 'Content-Type' = 'application/json' } `
            -Body $body -TimeoutSec 30 -ErrorAction Stop

    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("Search results for '$Query':")
    if ($resp.answer) { [void]$sb.AppendLine("Summary: $($resp.answer)") }
    $i = 0
    foreach ($r in $resp.results) {
        $i++
        $c = "$($r.content)"
        if ($c.Length -gt 300) { $c = $c.Substring(0, 300) + '...' }
        [void]$sb.AppendLine("$i. $($r.title)")
        if ($c) { [void]$sb.AppendLine("   $c") }
        if ($r.url) { $script:LastLinks += [PSCustomObject]@{ title = "$($r.title)"; url = "$($r.url)" } }
        if ($i -ge 6) { break }
    }
    if ($i -eq 0 -and -not $resp.answer) { return "No results found for '$Query'." }
    return $sb.ToString()
}

# -- get_weather: Open-Meteo, no key ------------------------------------------
function Invoke-GetWeather {
    param([string]$Location)
    if ([string]::IsNullOrWhiteSpace($Location)) { return 'No location was supplied. Ask the user which place they mean.' }

    $geo = Invoke-RestMethod ('https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=' +
           [Uri]::EscapeDataString($Location)) -TimeoutSec 20 -ErrorAction Stop
    if (-not $geo.results -or $geo.results.Count -eq 0) { return "Could not find a place called '$Location'." }
    $p = $geo.results[0]

    $w = Invoke-RestMethod ("https://api.open-meteo.com/v1/forecast?latitude=$($p.latitude)&longitude=$($p.longitude)" +
         '&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m' +
         '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max' +
         '&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=3') -TimeoutSec 20 -ErrorAction Stop

    $where = @($p.name, $p.admin1, $p.country) | Where-Object { $_ }
    $cond  = Get-WmoText $w.current.weather_code

    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("Live weather for $($where -join ', ') (observed $($w.current.time) local time):")
    [void]$sb.AppendLine("  Now: $($w.current.temperature_2m)F, feels like $($w.current.apparent_temperature)F, $cond")
    [void]$sb.AppendLine("  Humidity $($w.current.relative_humidity_2m)%, wind $($w.current.wind_speed_10m) mph, precipitation $($w.current.precipitation) in")
    for ($d = 0; $d -lt $w.daily.time.Count; $d++) {
        $dc = Get-WmoText $w.daily.weather_code[$d]
        [void]$sb.AppendLine("  $($w.daily.time[$d]): high $($w.daily.temperature_2m_max[$d])F, low $($w.daily.temperature_2m_min[$d])F, $dc, $($w.daily.precipitation_probability_max[$d])% chance of precipitation")
    }
    return $sb.ToString()
}

# -- helpers ------------------------------------------------------------------
function Convert-HtmlToText {
    param([string]$Html)
    $t = [regex]::Replace($Html, '<[^>]+>', '')
    return ([Net.WebUtility]::HtmlDecode($t) -replace '\s+', ' ').Trim()
}

function Get-WmoText {
    param($Code)
    $k = [string][int]$Code
    if ($script:WmoText.ContainsKey([int]$Code)) { return $script:WmoText[[int]$Code] }
    return "weather code $k"
}

# -- dispatch -----------------------------------------------------------------
# A failing tool must never take the whole reply down with it. On error this
# returns the problem as plain text, and the model explains it to the user
# instead of the panel going silent.
function Invoke-SkinTool {
    param([string]$Name, [string]$ArgumentsJson)

    $a = $null
    if (-not [string]::IsNullOrWhiteSpace($ArgumentsJson)) {
        try { $a = $ArgumentsJson | ConvertFrom-Json } catch { return "Tool arguments were not valid JSON: $ArgumentsJson" }
    }

    try {
        switch ($Name) {
            'web_search'  { return Invoke-WebSearch  -Query    $a.query }
            'get_weather' { return Invoke-GetWeather -Location $a.location }
            default       { return "Unknown tool '$Name'." }
        }
    }
    catch { return "The '$Name' tool failed: $($_.Exception.Message)" }
}
