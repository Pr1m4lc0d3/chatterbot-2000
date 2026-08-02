' ============================================================================
'  Applies one settings change, then exits.
'
'  Called as:  ["#@#settings.vbs" "ApiKey=sk-..."]
'              ["#@#settings.vbs" "Provider=Ollama"]
'
'  Same reason launch.vbs exists: a Rainmeter action passes exactly ONE
'  parameter string, and driving powershell.exe directly from an action either
'  collapses the flags into one argv element or truncates after the first token.
'  Handing a .vbs a single argument sidesteps both, and WScript.Shell.Run with
'  window style 0 means no console flash while you are typing settings.
' ============================================================================
Option Explicit

Dim fso, shell, scriptDir, arg

If WScript.Arguments.Count < 1 Then WScript.Quit
arg = WScript.Arguments(0)
If Len(arg) = 0 Then WScript.Quit

Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName) & "\"

Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & _
          scriptDir & "config.ps1"" -Set """ & arg & """", 0, False
