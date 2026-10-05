# 「GTA Temp Guard」 사용자 예약 작업을 등록하고 바로 띄운다. 관리자 권한 없이 현재 사용자로 돈다.
# 로그온 때 뜨고, 끝나거나 죽으면 1분 뒤 다시 띄우며, 실행 시간 제한이 없다. 이미 돌고 있으면 새로 띄우지 않는다.
$script = Join-Path $PSScriptRoot 'gta-temp-guard.ps1'
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$a = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument "--headless $ps -NoProfile -ExecutionPolicy Bypass -File `"$script`""
$t = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'GTA Temp Guard' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
Start-ScheduledTask -TaskName 'GTA Temp Guard'
'GTA Temp Guard 등록·시작'
