# =============================================================================
#  Chatterbot 2000 - configuration
#
#  Owns exactly one thing: reading and writing config.json. It does not talk to
#  any API and does not touch the transcript.
#
#  Called from the settings view as:
#      config.ps1 -Set "ApiKey=sk-..."
#      config.ps1 -Set "Provider=Ollama"          (also fills BaseUrl + Model)
#
#  Provider presets exist so a new user picks a name and is done. The two local
#  options need no key at all, which is the whole point of shipping this: install
#  the skin, choose Ollama, start talking, nothing leaves the machine.
# =============================================================================
param(
    [string] $Set
)

$ErrorActionPreference = 'Stop'
$Res        = $PSScriptRoot
$ConfigFile = Join-Path $Res 'config.json'
$Utf8       = New-Object Text.UTF8Encoding($false)

$Presets = @{
    'DeepSeek'  = @{ BaseUrl = 'https://api.deepseek.com';   Model = 'deepseek-v4-flash'; NeedsKey = $true  }
    'OpenAI'    = @{ BaseUrl = 'https://api.openai.com/v1';  Model = 'gpt-4o-mini';       NeedsKey = $true  }
    'Ollama'    = @{ BaseUrl = 'http://localhost:11434/v1';  Model = 'llama3.1';          NeedsKey = $false }
    'LM Studio' = @{ BaseUrl = 'http://localhost:1234/v1';   Model = 'local-model';       NeedsKey = $false }
    'Custom'    = @{ BaseUrl = '';                           Model = '';                  NeedsKey = $false }
}

function Read-Config {
    if (-not (Test-Path $ConfigFile)) { return [PSCustomObject]@{} }
    try { return (Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return [PSCustomObject]@{} }
}

function Write-Config {
    param($Cfg)
    [IO.File]::WriteAllText($ConfigFile, ($Cfg | ConvertTo-Json), $Utf8)
}

function Set-Value {
    param($Cfg, [string]$Name, [string]$Value)
    $Cfg | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    return $Cfg
}

if ([string]::IsNullOrWhiteSpace($Set)) { exit 0 }

# One argument carrying "Name=Value", because a Rainmeter action can pass only a
# single parameter string. Split on the FIRST '=' so keys and URLs survive intact.
$ix = $Set.IndexOf('=')
if ($ix -lt 1) { exit 0 }
$name  = $Set.Substring(0, $ix).Trim()
$value = $Set.Substring($ix + 1).Trim()

$cfg = Read-Config

if ($name -eq 'Provider') {
    if (-not $Presets.ContainsKey($value)) { exit 0 }
    $p   = $Presets[$value]
    $cfg = Set-Value $cfg 'Provider' $value
    # Custom keeps whatever the user already typed rather than blanking it.
    if ($value -ne 'Custom') {
        $cfg = Set-Value $cfg 'BaseUrl' $p.BaseUrl
        $cfg = Set-Value $cfg 'Model'   $p.Model
    }
} else {
    $cfg = Set-Value $cfg $name $value
}

Write-Config $cfg

# Push the visible values back into the skin so the settings view updates without
# a refresh - a refresh would drop the conversation's scroll position.
$rm = @(
    'C:\Program Files\Rainmeter\Rainmeter.exe',
    'C:\Program Files (x86)\Rainmeter\Rainmeter.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $rm) { exit 0 }

# PowerShell drops an empty-string argument to a native exe, which would slide the
# config name into the value slot. "" survives the call.
function Arg { param([string]$v) if ([string]::IsNullOrEmpty($v)) { '""' } else { $v } }

function Mask {
    param([string]$k)
    if ([string]::IsNullOrWhiteSpace($k)) { return 'not set' }
    if ($k.Length -le 8) { return '********' }
    return ('*' * 12) + $k.Substring($k.Length - 4)
}

# Light the pill for the active provider and dim the rest. Rainmeter formulas
# cannot compare strings, so the comparison happens here and only the resulting
# style fragment is pushed.
$order = @('DeepSeek', 'OpenAI', 'Ollama', 'LM Studio', 'Custom')
$on    = 'FillColor 255,255,255,38 | StrokeColor 255,255,255,150'
$off   = 'FillColor 255,255,255,10 | StrokeColor 255,255,255,45'
for ($i = 0; $i -lt $order.Count; $i++) {
    $style = if ("$($cfg.Provider)" -eq $order[$i]) { $on } else { $off }
    & $rm !SetVariable "Prov$($i + 1)Style" $style 'Chatterbot 2000' 2>$null
}

& $rm !SetVariable 'CfgProvider'  (Arg "$($cfg.Provider)")        'Chatterbot 2000' 2>$null
& $rm !SetVariable 'CfgBaseUrl'   (Arg "$($cfg.BaseUrl)")         'Chatterbot 2000' 2>$null
& $rm !SetVariable 'CfgModel'     (Arg "$($cfg.Model)")           'Chatterbot 2000' 2>$null
& $rm !SetVariable 'CfgKey'       (Mask "$($cfg.ApiKey)")         'Chatterbot 2000' 2>$null
& $rm !SetVariable 'CfgSearchKey' (Mask "$($cfg.SearchApiKey)")   'Chatterbot 2000' 2>$null
& $rm !UpdateMeter '*' 'Chatterbot 2000' 2>$null
& $rm !Redraw 'Chatterbot 2000' 2>$null
