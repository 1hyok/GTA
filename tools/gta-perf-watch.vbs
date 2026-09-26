' Launcher called by Task Scheduler ("GTA Perf Watch"). Runs PowerShell with no window (0)
' so it never takes focus from the game.
Set fso = CreateObject("Scripting.FileSystemObject")
ps1 = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "gta-perf-watch.ps1")
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False
