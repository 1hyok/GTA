# 과열 보호. 사용자 예약 작업 「GTA Temp Guard」가 로그온 때 띄우고 시간 제한 없이 돈다(관리자 권한 없음).
# 10초마다 GPU·CPU 온도를 %TEMP%\gta-temps3.csv 에 남기고, GPU 핫스팟 105°C 이상이나 CPU Tctl 97°C 이상이
# 세 번 연속이면 60초 뒤 시스템을 끈다(취소: shutdown /a). 전에는 Claude 세션의 백그라운드 감시 안에 있어
# 2시간 제한으로 끝날 때마다 다시 걸 때까지 보호가 비었다(1005).
# Tctl 은 관리자 권한으로 띄운 LibreHardwareMonitor 웹 서버(:8085)에서만 읽힌다. 서버가 없으면 GPU 핫스팟만 본다.
$ErrorActionPreference = 'Continue'
$csv = "$env:TEMP\gta-temps3.csv"
$header = 'time,gpu_core,gpu_hotspot,gpu_mem,gpu_w,igpu_soc,cpu_tctl,cpu_w,cpu_load,gta_cpu,steam_cpu,igpu_w'
$guardLog = "$env:TEMP\gta-temp-guard.log"
function GuardLog($text) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $text" | Out-File $guardLog -Append -Encoding utf8 }
Add-Type -Path "$env:USERPROFILE\Tools\LibreHardwareMonitor\LibreHardwareMonitorLib.dll"
$c = New-Object LibreHardwareMonitor.Hardware.Computer
$c.IsCpuEnabled = $true; $c.IsGpuEnabled = $true; $c.Open()
function V($hw, $type, $name) {
    if (-not $hw) { return '' }
    $s = $hw.Sensors | Where-Object { $_.SensorType -eq $type -and $_.Name -eq $name } | Select-Object -First 1
    if ($s -and $s.Value) { [math]::Round($s.Value, 1) } else { '' }
}
function WebTctl {
    try {
        $j = Invoke-RestMethod http://localhost:8085/data.json -TimeoutSec 2
        $stack = New-Object System.Collections.Stack; $stack.Push($j); $t = ''; $w = ''
        while ($stack.Count) {
            $n = $stack.Pop()
            if ($n.Text -match 'Tctl' -and $n.Value) { $t = ($n.Value -replace '[^0-9.,]', '') -replace ',', '.' }
            if ($n.Text -eq 'Package' -and $n.Value -match 'W') { $w = ($n.Value -replace '[^0-9.,]', '') -replace ',', '.' }
            foreach ($k in $n.Children) { $stack.Push($k) }
        }
        return @($t, $w)
    } catch { return @('', '') }
}
$cpuHw = $c.Hardware | Where-Object HardwareType -eq 'Cpu' | Select-Object -First 1
$nv = $c.Hardware | Where-Object HardwareType -eq 'GpuNvidia' | Select-Object -First 1
$am = $c.Hardware | Where-Object HardwareType -eq 'GpuAmd' | Select-Object -First 1
$cores = [Environment]::ProcessorCount
$prev = @{}; $prevT = Get-Date
function ProcPct($names) {
    $now = Get-Date; $sum = 0
    foreach ($pr in (Get-Process $names -ErrorAction SilentlyContinue)) {
        $k = $pr.Id
        if ($script:prev.ContainsKey($k) -and $pr.CPU) { $sum += $pr.CPU - $script:prev[$k] }
        if ($pr.CPU) { $script:prev[$k] = $pr.CPU }
    }
    $sec = ($now - $script:prevT).TotalSeconds
    if ($sec -le 0) { return '' }
    [math]::Round($sum / $sec / $cores * 100, 1)
}
GuardLog "시작 PID $PID"
$hot = 0
while ($true) {
    if ((Test-Path $csv) -and (Get-Item $csv).Length -gt 20MB) { Move-Item $csv "$csv.old" -Force }
    if (-not (Test-Path $csv)) { $header | Out-File $csv -Encoding utf8 }
    if ($nv) { $nv.Update() }; if ($am) { $am.Update() }; if ($cpuHw) { $cpuHw.Update() }
    $core = V $nv 'Temperature' 'GPU Core'; $hs = V $nv 'Temperature' 'GPU Hot Spot'; $mem = V $nv 'Temperature' 'GPU Memory Junction'
    $pw = V $nv 'Power' 'GPU Package'; $soc = V $am 'Temperature' 'GPU VR SoC'; $igw = V $am 'Power' 'GPU Core'
    $tc, $cw = WebTctl
    $load = V $cpuHw 'Load' 'CPU Total'
    $gta = ProcPct @('GTA5_Enhanced', 'GTA5'); $stm = ProcPct @('steam', 'steamwebhelper'); $script:prevT = Get-Date
    "$(Get-Date -Format 'HH:mm:ss'),$core,$hs,$mem,$pw,$soc,$tc,$cw,$load,$gta,$stm,$igw" | Out-File $csv -Append -Encoding utf8
    if (($hs -ne '' -and $hs -ge 105) -or ($tc -ne '' -and [double]$tc -ge 97)) { $hot++ } else { $hot = 0 }
    if ($hot -ge 3) {
        GuardLog "과열 종료: 핫스팟 $hs, Tctl $tc (세 번 연속)"
        shutdown.exe /s /t 60 /c "GTA overheat: shutting down in 60s (cancel: shutdown /a)"
        exit 0
    }
    Start-Sleep 10
}
