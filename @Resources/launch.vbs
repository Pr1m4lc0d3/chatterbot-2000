' ============================================================================
'  Starts the DeepSeek client for a new question.
'
'  Why this file exists: Rainmeter's ["prog" "params"] action accepts exactly
'  ONE parameter string, so a multi-flag PowerShell command line cannot be
'  passed through it reliably - it either arrives as a single argv element
'  (PowerShell then tries to run "-NoProfile" as a command) or is truncated
'  after the first token (PowerShell opens an interactive console and waits).
'  Rainmeter calls this file with no arguments at all, so there is nothing
'  left to misparse.
'
'  WScript.Shell.Run with window style 0 also hides the console completely.
'  "powershell -WindowStyle Hidden" still flashes one; this does not.
' ============================================================================
Dim fso, shell, scriptDir, st
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName) & "\"

' Mark the send the instant the key is pressed, before PowerShell is even
' started. The panel then shows SENDING immediately, so a keystroke is always
' visibly acknowledged. If it stays on SENDING, the client failed to launch -
' which is exactly the failure that previously looked like a dead panel.
Set st = fso.CreateTextFile(scriptDir & "state.txt", True)
st.Write "SENDING"
st.Close

Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "deepseek.ps1"" -FromQueryFile", 0, False
