# Install a per-user logon shortcut. No game or macro restart.
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'frame-watch.ps1'
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptPath + '"'
$startup = [Environment]::GetFolderPath('Startup')
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $startup 'GTA Frame Evidence.lnk'))
$shortcut.TargetPath = $powershell
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = 'Read-only GTA frame-drop evidence recorder'
$shortcut.Save()
Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden
Write-Output ('Installed logon shortcut: ' + (Join-Path $startup 'GTA Frame Evidence.lnk'))
