param(
    [string]$FixtureDir = (Join-Path $env:TEMP ('gta-perf-tests-' + [guid]::NewGuid().ToString('N'))),
    [switch]$CheckLiveData,
    [string]$RealPerfCsv = (Join-Path $env:USERPROFILE 'gta-perf\perf.csv'),
    [string]$RealLadderJson = (Join-Path $env:USERPROFILE 'gta-perf\ladder.json')
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '..\frame-watch\frame-watch.tests.ps1')
$source = Join-Path $PSScriptRoot '..\gta-perf-watch.ps1'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count) { throw ($parseErrors | Out-String) }
# 정규 실행 본문은 실행하지 않는다. 테스트에 필요한 함수 정의만 읽는다.
$names = @('ConvertTo-Num', 'ConvertTo-Hashtable', 'Get-StageLabel', 'Get-MacroActivity', 'Invoke-Capture', 'Invoke-CaptureOnce', 'Get-LadderCaptures', 'Invoke-LadderJudge', 'Add-PerfRow', 'Flush-PerfRows', 'Write-JsonFile')
foreach ($name in $names) {
    $definition = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($definition.Count -ne 1) { throw "함수 정의 수 오류: $name" }
    Invoke-Expression $definition[0].Extent.Text
}
$null = New-Item -ItemType Directory -Path $FixtureDir -Force
$FixtureDir = (Resolve-Path -LiteralPath $FixtureDir).Path
$Inv = [Globalization.CultureInfo]::InvariantCulture
$PerfCsv = Join-Path $FixtureDir 'perf.csv'
$CrashCsv = Join-Path $FixtureDir 'absent-crashes.csv'
$LadderFile = Join-Path $FixtureDir 'ladder-output.json'
$CapDir = Join-Path $FixtureDir 'captures'
$null = New-Item -ItemType Directory -Path $CapDir -Force
$PresentMon = Join-Path $FixtureDir 'fake-presentmon.exe'
[IO.File]::WriteAllText($PresentMon, '')
$CaptureSec = 60; $SampleSec = 5; $ActiveIdleS = 10; $GameProc = 'GTA5_Enhanced'
$results = New-Object 'System.Collections.Generic.List[object]'
function Check([string]$name, [bool]$condition) {
    if (-not $condition) { throw "검증 실패: $name" }
    $results.Add([pscustomobject]@{ test = $name; result = '통과' })
}
function Clone($object) { return ($object | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
function Save-Rows($rows) { $rows | Export-Csv -LiteralPath $PerfCsv -NoTypeInformation -Encoding UTF8 }
$ladder = [pscustomobject]@{
    minCaptures = 6; fpsTarget = 60; vramLimitMiB = 7600
    stages = @(
        [pscustomobject]@{ id=0; set=@{dlssQuality='3'}; revert=@{dlssQuality='2'} },
        [pscustomobject]@{ id=1; set=@{Tessellation='3'}; revert=@{Tessellation='2'} },
        [pscustomobject]@{ id=2; set=@{ParticleQuality='3';ShadowQuality='3'}; revert=@{ParticleQuality='2';ShadowQuality='2'} }
    )
    state = [pscustomobject]@{
        phase = 'measure'; stage = 1; round = 0; since = '2026-09-26 20:11:07'
        expected = [pscustomobject]@{ dlssQuality='3'; Tessellation='3'; ParticleQuality='2'; ShadowQuality='2' }
        kept = @(0); reverted = @()
        history = @([pscustomobject]@{ time='2026-09-26 20:11:07'; label='S0'; stage=0; result='pass'; avgFps=80.1; captures=6; action='keep S0, apply S1' })
    }
}
# 실제 파일 없이도 실행되는, 수익 매크로가 user 로 기록된 당시 형태의 합성 표본.
$legacy = @(
    [pscustomobject]@{time='2026-09-27 00:40:02';status='capture';stage='S1';obs='no';play='user';fg_ratio='1';gpu_util_pct='95.3';span_s='59.93';disp_fps='90.2';vram_max_mib='6348';vram_used_mib='6300';note=''},
    [pscustomobject]@{time='2026-09-27 01:20:02';status='capture';stage='S1';obs='no';play='user';fg_ratio='1';gpu_util_pct='96.5';span_s='59.93';disp_fps='91.5';vram_max_mib='6348';vram_used_mib='6300';note=''},
    [pscustomobject]@{time='2026-09-27 01:40:02';status='capture';stage='S1';obs='no';play='user';fg_ratio='1';gpu_util_pct='96.6';span_s='59.93';disp_fps='85.5';vram_max_mib='6348';vram_used_mib='6300';note=''}
)
$importBranch = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq '$ImportPresentMonCsv'}, $true))
Check '수동 import 는 manual 로 기록하고 정규 캡처 경로를 호출하지 않음' ($importBranch.Count -eq 1 -and $importBranch[0].Extent.Text -match "status = 'manual'" -and $importBranch[0].Extent.Text -notmatch 'Invoke-Capture|activity-check=2')
$testLadder = Clone $ladder
$testLadder.state.phase = 'measure'; $testLadder.state.stage = 1; $testLadder.state.since = '2026-09-26 20:11:07'
Save-Rows $legacy
$oldHistory = $testLadder.state.history | ConvertTo-Json -Depth 12 -Compress
Check '무표식 기존 S1 캡처는 판정 0개' (@(Get-LadderCaptures $testLadder).Count -eq 0)
Invoke-LadderJudge $testLadder
Check '무표식만 있으면 S1 유지 및 완료된 S0 history 불변' ($testLadder.state.stage -eq 1 -and ($testLadder.state.history | ConvertTo-Json -Depth 12 -Compress) -ceq $oldHistory)

$template = Clone $legacy[0]
$template.note = 'activity-check=2'; $template.span_s = '60'; $template.disp_fps = '90'
$template.play = 'user'; $template.status = 'capture'; $template.obs = 'no'; $template.fg_ratio = '1'; $template.gpu_util_pct = '95'
$newRows = @(0..5 | ForEach-Object { $r = Clone $template; $r.time = ([datetime]'2026-09-27 12:00:00').AddMinutes(10 * $_).ToString('yyyy-MM-dd HH:mm:ss'); $r })
Save-Rows $newRows
Check '새 정상 사용자 캡처 여섯 개 판정 가능' (@(Get-LadderCaptures $testLadder).Count -eq 6)
$mutations = @(
    @{ name='낮은 전경 비율 제외'; field='fg_ratio'; value='0.89' },
    @{ name='다른 단계 제외'; field='stage'; value='S0' },
    @{ name='기준 시각 이전 제외'; field='time'; value='2026-09-26 20:11:06' },
    @{ name='매크로 제외'; field='play'; value='macro' },
    @{ name='무입력 제외'; field='play'; value='idle' },
    @{ name='수동 import 는 표식이 있어도 제외'; field='status'; value='manual' },
    @{ name='백그라운드 기록 제외'; field='status'; value='background' },
    @{ name='다른 버전 표식 제외'; field='note'; value='activity-check=20' },
    @{ name='문장 속 유사 표식 제외'; field='note'; value='not-activity-check=2' }
)
foreach ($mutation in $mutations) {
    $rows = @(Clone $newRows)
    $rows[0].($mutation.field) = $mutation.value
    Save-Rows $rows
    Check $mutation.name (@(Get-LadderCaptures $testLadder).Count -eq 5)
}
foreach ($field in @('obs', 'gpu_util_pct')) {
    $rows = @(Clone $newRows)
    $rows[0].($field) = $(if ($field -eq 'obs') { 'yes' } else { '70' })
    Save-Rows $rows
    Check "현행 기준 $field 제한 없음" (@(Get-LadderCaptures $testLadder).Count -eq 6)
}
$boundary = Clone $template
$boundary.gpu_util_pct = '90'; $boundary.fg_ratio = '0.9'; $boundary.time = $testLadder.state.since
$boundary.note = '  activity-check=2 | pending waiting'
Save-Rows @($boundary)
Check 'GPU·전경·시각 경계와 note 분리 토큰 허용' (@(Get-LadderCaptures $testLadder).Count -eq 1)
Save-Rows @($legacy + $newRows[0..2])
Check '기존 세 개와 새 세 개를 합쳐 조기 판정하지 않음' (@(Get-LadderCaptures $testLadder).Count -eq 3)

# 캡처의 프로세스·GPU·입력 조회는 전부 모킹한다. 게임·OBS·스케줄러를 실행하거나 제어하지 않는다.
Add-Type -TypeDefinition 'public static class GtaPerfNative { public static double IdleSeconds() { return 0.0; } }'
function Start-Process { [pscustomobject]@{ HasExited = $true; Id = -1 } }
function Test-ObsRunning { return $false }
function Write-Log { param($message) $script:lastLog = $message }
function Test-Path([string]$LiteralPath) {
    if ([IO.Path]::GetFileName($LiteralPath) -like 'cap-*.csv') { return $true }
    return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath)
}
function Get-PresentMonStats { return @{ span_s = 60; disp_fps = 90 } }
function Get-GpuStats { return @{ gpu_util_pct = 95; gpu_samples = 60 } }
$oldTemp = $env:TEMP
try {
    $env:TEMP = $FixtureDir
    $earnLog = Join-Path $FixtureDir 'gta-earn.log'
    [IO.File]::WriteAllText($earnLog, '테스트 수익 매크로 활동')
    (Get-Item -LiteralPath $earnLog).LastWriteTime = (Get-Date).AddMinutes(1)
    Check '수익 로그가 매크로 감지 대상' ((Get-MacroActivity (Get-Date)) -eq 'gta-earn')
    $capture = Invoke-Capture
    Check '수익 매크로 캡처를 macro 로 분류' ($capture.play -eq 'macro' -and $capture.macro_activity -eq 'gta-earn')
    Check '정규 캡처에 새 분류 표식 기록' ($capture.note -eq 'activity-check=2')
    (Get-Item -LiteralPath $earnLog).LastWriteTime = (Get-Date).AddMinutes(-1)
    $capture = Invoke-Capture
    Check '오래된 로그는 신규 사용자 캡처를 막지 않음' ($capture.play -eq 'user' -and $capture.macro_activity -eq '' -and $capture.note -eq 'activity-check=2')
} finally { $env:TEMP = $oldTemp }

# 판정 후의 파일 쓰기도 메모리 대역으로 막아 이미 완료된 S0 history 보존을 확인한다.
$Keys = @($testLadder.state.expected.PSObject.Properties.Name)
$script:testCurrent = ConvertTo-Hashtable $testLadder.state.expected
function Get-SettingValues { return $script:testCurrent }
function Set-Pending { param($set, $reason) $script:pendingSeen = $true }
function Write-JsonFile { param($object, $path) $script:writeSeen = Clone $object }
function Write-LadderLog { param($message) $script:ladderMessage = $message }
$judgeLadder = Clone $testLadder
$s0Before = $judgeLadder.state.history[0] | ConvertTo-Json -Depth 12 -Compress
Save-Rows $newRows
Invoke-LadderJudge $judgeLadder
Check '새 여섯 표본으로 S1 정상 판정' ($judgeLadder.state.stage -eq 2 -and $judgeLadder.state.history[-1].captures -eq 6 -and $judgeLadder.state.history[-1].result -eq 'pass')
Check '새 판정 뒤에도 기존 S0 history 보존' (($judgeLadder.state.history[0] | ConvertTo-Json -Depth 12 -Compress) -ceq $s0Before)
Check '상태 출력은 테스트 대역으로만 전달' ($script:writeSeen.state.stage -eq 2 -and -not (Test-Path -LiteralPath $LadderFile))

# 저장 오류 복구: 실 데이터와 분리된 파일에서 실제 파일 잠금·스키마 변경을 재현한다.
$jsonDefinition = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-JsonFile' }, $true)
Invoke-Expression $jsonDefinition[0].Extent.Text
$PerfCsv = Join-Path $FixtureDir 'persistence.csv'
$Columns = @('time', 'status', 'stage', 'play', 'note')
[pscustomobject]@{time='old';status='capture';stage='S0';legacy='preserved'} | Export-Csv -LiteralPath $PerfCsv -NoTypeInformation -Encoding UTF8
Add-PerfRow @{time='new';status='capture';stage='S4';play='user';note='activity-check=2'}
$saved = @(Import-Csv -LiteralPath $PerfCsv)
Check '열 변경 뒤 과거 열과 신규 행 모두 보존' ($saved.Count -eq 2 -and $saved[0].legacy -eq 'preserved' -and $saved[1].play -eq 'user')
$lock = [IO.File]::Open($PerfCsv, 'Open', 'ReadWrite', 'None')
try { Add-PerfRow @{time='locked';status='capture';stage='S4';play='user'} }
finally { $lock.Dispose() }
Check '잠긴 CSV 저장 실패 시 원본 대기 행 보존' (@(Get-ChildItem -LiteralPath "$PerfCsv.pending" -Filter '*.json').Count -eq 1)
$pendingCopy = Get-Content -LiteralPath (Get-ChildItem -LiteralPath "$PerfCsv.pending" -Filter '*.json')[0].FullName -Raw
Flush-PerfRows
Check '잠금 해제 후 다음 flush로 복구' (@(Import-Csv -LiteralPath $PerfCsv).Count -eq 3 -and @(Get-ChildItem -LiteralPath "$PerfCsv.pending" -Filter '*.json').Count -eq 0)
$pendingCopy | Set-Content -LiteralPath (Join-Path "$PerfCsv.pending" 'replay.json') -Encoding UTF8
Flush-PerfRows
Check 'CSV 교체 후 대기 파일 재처리 시 중복 없음' (@(Import-Csv -LiteralPath $PerfCsv).Count -eq 3)

# 실패 재시도와 예외를 실행해서 검증한다.
$script:processStarts=0; $script:stoppedPid=0
function Start-Process {
    $script:processStarts++
    if ($script:processStarts -eq 2) { throw 'fixture GPU sampler start failure' }
    return [pscustomobject]@{HasExited=$false;Id=123456}
}
function Stop-Process { param($Id, [switch]$Force, $ErrorAction) $script:stoppedPid=$Id }
try { $null=Invoke-CaptureOnce } catch { }
Check 'GPU 수집 시작 예외에도 먼저 띄운 PresentMon 정리' ($script:stoppedPid -eq 123456)
$script:attempts = 0
function Invoke-CaptureOnce { $script:attempts++; if ($script:attempts -eq 1) { return @{status='capture-empty';note='activity-check=2'} }; return @{status='capture';note='activity-check=2'} }
$recovered = Invoke-Capture
Check '빈 캡처는 두 번째 측정으로 복구하며 실패 흔적 보존' ($script:attempts -eq 2 -and $recovered.status -eq 'capture' -and $recovered.note -match 'recovered-after=capture-empty')
function Invoke-CaptureOnce { throw 'fixture capture failure' }
$failed = Invoke-Capture
Check '캡처 예외도 최종 실패 행으로 반환' ($failed.status -eq 'capture-failed' -and $failed.note -match 'capture-attempts=2')

$route = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq '-not $g' -and $node.Extent.Text -match 'expired-skip'}, $true))
Check '실행 상태 라우팅 한 곳' ($route.Count -eq 1)
function Invoke-Capture { return @{status='capture';fg_ratio=0;play='idle';note='activity-check=2'} }
function Get-ForegroundName { return 'other-app' }
$g = [pscustomobject]@{Id=123}; $expired=$false; $base=@{}; $note=@()
Invoke-Expression $route[0].Extent.Text
Check '백그라운드 게임도 캡처 경로 실행' ($base.status -eq 'capture' -and $base.fg_ratio -eq 0)
$g=$null; $base=@{}
Invoke-Expression $route[0].Extent.Text
Check '꺼진 게임은 캡처하지 않음' ($base.status -eq 'not_running')
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $FixtureDir 'results.json') -Encoding UTF8
$liveResult = $null
if ($CheckLiveData) {
    $savedPerfCsv = $PerfCsv
    try {
        $PerfCsv = $RealPerfCsv
        $liveLadder = Get-Content -LiteralPath $RealLadderJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $liveResult = [pscustomobject]@{
            phase = $liveLadder.state.phase; stage = $liveLadder.state.stage
            eligible = @(Get-LadderCaptures $liveLadder).Count; required = $liveLadder.minCaptures
        }
    } finally { $PerfCsv = $savedPerfCsv }
}
[pscustomobject]@{ tests = $results.Count; passed = $results.Count; source = (Resolve-Path -LiteralPath $source).Path; fixture = $FixtureDir; live = $liveResult } | ConvertTo-Json
