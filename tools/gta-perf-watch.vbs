' Launcher called by Task Scheduler ("GTA Perf Watch"). Runs PowerShell with no window (0)
' so it never takes focus from the game. Each start is logged to %USERPROFILE%\gta-perf\launch.log,
' and PowerShell's own console output goes to launch-out.txt for diagnosis.
' The data folder is outside AppData on purpose: processes started from the Claude app (MSIX)
' get AppData writes virtualized into the package folder, so Task Scheduler would see other files.
On Error Resume Next
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
ps1 = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "gta-perf-watch.ps1")
logDir = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\gta-perf"
If Not fso.FolderExists(logDir) Then fso.CreateFolder(logDir)
Set f = fso.OpenTextFile(logDir & "\launch.log", 8, True)
f.WriteLine Now & " launch"
f.Close
cmd = "cmd.exe /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ > """ & logDir & "\launch-out.txt"" 2>&1"
sh.Run cmd, 0, False
