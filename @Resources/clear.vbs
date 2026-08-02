' ============================================================================
'  Clears the conversation and its history. See launch.vbs for why the skin
'  calls a .vbs instead of powershell.exe directly.
' ============================================================================
Dim fso, shell, scriptDir
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "deepseek.ps1"" -ClearHistory", 0, False
