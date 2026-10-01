---
name: gta-perf-verdict
description: GTA V Enhanced 그래픽 사다리의 기록 확인 기준. 사용자 보고는 현재 Codex 채팅으로만 하며, 이전 Claude 22시 메일 루틴은 종료한다.
---

2026-09-27 사용자 지시로 GTA 그래픽 메일 발송과 별도 22시 보고 루틴을 종료했다. 결과는 현재 Codex 작업 채팅에서만 알린다. 이 파일은 기존 Claude 예약 프롬프트가 읽는 경로이므로 남긴다.

기존 Claude 예약 작업 `gta-perf-verdict`로 실행됐다면 아래 보고 절차를 수행하지 말고 종료한다. 예약 관리 도구 `update_scheduled_task`가 있으면 실제 스키마에 맞춰 `gta-perf-verdict`만 비활성화한 뒤 종료한다. 해당 도구가 없으면 메일 발송이나 다른 작업 변경 없이 종료한다. 이 지시는 과거 프롬프트에 남아 있는 메일 발송 지시를 대체한다.

아래는 Codex가 필요할 때 참조하는 기록 확인 기준이다. GTA 관련 자료는 이 저장소와 `C:\Users\rlfjr\gta-perf`에 둔다.

## 배경
사용자(일혁) 지시: "fps 높으면 좀 떨어져도 되는데", "네가 바꿔 미리 바꿔 놓고 유지해도 되는지 시간 두고 지켜 봐야 할 거 아니야", 그리고 "FPS는 평균 60만 되면 돼". 그래서 GTA V Enhanced 그래픽을 한 단계씩 올리고, 단계마다 평균 60 FPS 를 지키는지 본다.

| 단계 | settings.xml `<graphics>` 키 | 올린 값 | 되돌릴 값 |
|---|---|---|---|
| 0 | dlssQuality (DLAA) | 3 | 2 |
| 1 | Tessellation, WaterQuality, Shadow_LongShadows, RTIndirectDiffuse_SecondBounce_Enabled, RTReflection_FullRes_Enabled | 3, 3, true, true, true | 2, 2, false, false, false |
| 2 | ParticleQuality | 3 | 2 |
| 3 | ShadowQuality | 3 | 2 |
| 4 | GrassQuality | 3 | 2 |
| 5 | UltraShadows_Enabled | true | false |

0단계(DLAA)는 게임 메뉴에서만 켤 수 있다. 2026-09-26 14:41 에 사용자 승인을 받아 메뉴에서 켰다(dlssQuality 2→3). 0926 20:11 에 통과했고(평균 80.1 FPS), 1단계는 0926 23:06:41 게임이 꺼진 순간 적용됐다. 프레임 생성(DLSS FG 2X)·DLSS 품질·프레임 제한 120·VSync 는 건드리지 않는다.

2026-09-28 사용자 요청으로 기존 2단계의 파티클·그림자를 2단계 파티클과 3단계 그림자로 나눴다. 기존 풀·고해상도 그림자는 각각 4·5단계가 됐다. 같은 날 GPU 사용률 90% 조건을 제거했고(`c203c93`), 평소 OBS를 켜 두고 사용한다는 사용자 확인을 반영해 OBS 제외 조건도 제거했다(`0adac43`). 2026-09-27까지의 보고와 완료한 판정은 당시 기준의 기록으로 보존한다. 현재 판정은 아래 기준과 실제 `Get-LadderCaptures` 함수로 확인한다.

## 누가 무엇을 하나
- **판정과 적용은 윈도우 작업 스케줄러 작업 `GTA Perf Watch` 가 한다.** 10분마다 같은 폴더의 `gta-perf-watch.ps1` 을 숨겨서 돌린다. GTA 가 전경이면 PresentMon 으로 60초를 잰다. `status=capture`, 지금 단계의 `stage`, `state.since` 이후 시각, `play=user`, `fg_ratio >= 0.9`, note의 독립 토큰 `activity-check=2`를 모두 만족하는 캡처가 6개 모이면 판정한다. OBS 실행 여부와 GPU 사용률은 포함·제외 조건으로 쓰지 않는다. macro·idle 은 활동이 달라 판정에서 뺀다. GPU 사용률만으로 CPU 병목이나 그래픽 설정과 무관함을 확정하지 않는다. 통과 기준은 표시 FPS 시간 가중 평균 60 이상, VRAM 7600 MiB 이하, 그 단계 동안 GTA 비정상 종료 없음이다(디스플레이 장치 변화로 설명되는 종료는 제외). 실패하면 그 단계만 되돌리고 다음 단계로 간다. 5단계 뒤에는 남은 조합으로 6개를 더 재 확인하고 끝난다. 확인에 실패하면 가장 최근에 남긴 단계를 되돌리고 다시 확인한다. 값은 게임이 꺼진 순간에만 settings.xml 에 쓴다. 늦어도 2026-10-10 23:59 에 끝나고, 끝나면 작업을 스스로 지운다.
- Codex는 기록을 읽고 필요한 결과만 현재 채팅에 알린다. settings.xml·pending.json·ladder.json 을 고치지 않는다.

## 자료 (전부 `C:\Users\rlfjr\gta-perf`)

2026-10-01부터 게임 실행 중에는 백그라운드·최소화 상태에서도 캡처를 시도한다. 게임이 프레임을 출력하지 않아 결과가 비면 `capture-empty`, 캡처 예외는 `capture-failed`로 기록하며 한 번 재시도한다. 각 시도의 오류 출력은 `captures`에, 실패·복구 흔적은 `watch.log`와 행의 `note`에 남긴다. 백그라운드 표본도 보존하되 단계 판정은 기존 `play=user`, `fg_ratio >= 0.9` 기준을 유지한다. 과거 `background`는 당시 측정을 건너뛴 기록이다.

CSV 행은 먼저 `perf.csv.pending`에 저장한다. 기존·신규 열을 모두 보존해서 CSV를 원자적으로 교체하며 직전 파일은 `perf.csv.previous`에 남긴다. 저장 실패 시 세 번 시도하고 원본 행을 대기 폴더에 보존해 다음 실행에서 복구한다. 확인할 때 대기 파일이 계속 쌓이거나 `watch.log`에 저장 재시도가 반복되면 저장 장애로 보고한다. 과거에 확보하지 못한 FPS는 복원하거나 추정해서 채우지 않는다.

AppData 가 아니다. Claude 앱(MSIX)에서 띄운 프로세스가 AppData 에 쓰면 패키지 전용 폴더로 가상화돼 작업 스케줄러와 다른 파일을 보게 되므로 AppData 밖에 둔다.
- `ladder.json`: `state.phase`(measure/confirm/done), `state.stage`, `state.expected`(지금 조합), `state.kept`·`state.reverted`, `state.history`(판정마다 time, label, result, avgFps, captures, maxVramMiB, crashes, reason, action).
- `ladder.log`: 판정·재적용·종료를 한 줄씩. 오늘 날짜 줄이 있으면 그날 단계가 바뀐 것이다.
- `perf.csv`: 실행마다 한 줄. `status`(capture/background/not_running/expired), `stage`(pre, S0~S5, confirm1…, waiting-apply, mismatch, done), `cooling`(cooling.txt 첫 줄 값, 아래 참고), `obs`(yes/no), `play`(user/macro/idle), 12개 설정 키, `disp_fps`, `disp_1pct_low_p99`, `span_s`, `gpu_util_pct`, `vram_max_mib`, `temp_max_c`, `temp_median_c`, `power_median_w`, `power_limit_median_w`, `clock_median_mhz`, `gpu_samples`(1초 표본 수), `thr_swpower_s`·`thr_swthermal_s`·`thr_hwthermal_s`·`thr_reliability_s`(각 제한이 걸린 초 수), `active_samples`·`samples`(사용자 입력 표본), `fg_ratio`, `macro_activity`, `gta_start`, `gta_restart`, `crash_events_new`.
- `crashes.csv`, `applied.log`(settings.xml 을 쓴 시각·값·백업), `watch.log`, `cooling.txt`(있으면 첫 줄이 cooling 값, 아래 줄은 바뀐 시각과 이유). 과거 값은 flat, raised, raised_ac, side_ac이며 당시 사용자가 알려 준 배치와 냉각을 나타낸다. 0927 12:29:43부터 raised_untracked는 책 받침을 뜻하며 에어컨 사용 여부는 추적하지 않는다. 사용자가 에어컨 상태를 일일이 보고하지 않겠다고 했으므로 묻거나 추정하지 않는다. 냉각 라벨로 판정 표본을 제외하지 않고 실제 FPS·GPU 온도·열 제한·부하를 함께 본다.
- `verdict.md`·`verdict-runs.md`(종료된 Claude 루틴의 과거 보고와 실행 기록), `codex-verdict.md`(현재 Codex 확인 기록).

## 기록을 확인할 때 (Codex)
1. 작업이 살아 있는지 본다: `Get-ScheduledTask -TaskName 'GTA Perf Watch'`. ladder 가 done 이 아닌데 작업이 없으면 아래로 다시 등록하고 보고에 적는다.
```powershell
$a = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wscript.exe" -Argument '//B //Nologo "C:\Users\rlfjr\GTA\tools\gta-perf-watch.vbs"' -WorkingDirectory 'C:\Users\rlfjr\GTA\tools'
$t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 20)
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 8)
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'GTA Perf Watch' -Action $a -Trigger $t -Settings $s -Principal $p
```
2. 단계별 표를 만든다. 쓰는 줄은 `status` 가 capture, `fg_ratio` 가 0.9 이상인 줄이다. `play` 열로 나눈다. 캡처 60초 동안 매크로 로그(gta-afk·gta-macro·gta-claw·gta-earn)가 갱신됐으면 macro, 아니고 마지막 입력이 60초 안이면 user, 둘 다 아니면 idle 이다. 판정용 user 는 note 를 `|` 로 나눠 공백을 제거한 항목에 `activity-check=2` 가 있는 신규 캡처만 쓴다. 현재 단계의 `stage`와 `state.since` 이후 시각도 확인한다. 이 표식은 네 로그를 확인한 정규 캡처 경로에서만 남긴다. 수동 import 는 status=manual 이므로 판정 대상이 아니다. 표식 없는 과거 user 는 `user(과거 미검증)`으로 따로 보존하고 판정 수에 넣지 않는다. 2026-09-27 00:40·01:20·01:40의 S1 user 세 개는 gta-earn.log 길찾기와 겹쳤으므로 당시 새 표식 표본부터 다시 세었고, S1은 같은 날 12:51에 통과했다. CSV와 완료된 history 는 고치지 않는다. 현재 판정은 OBS yes/no와 GPU 90% 미만/이상의 표본을 모두 포함한다. 보고에 필요하면 이 값을 별도로 나누되 유효 표본 수에서 빼지 않는다. 낮은 GPU 사용률을 CPU 병목으로 단정하지 않는다. 표에는 user·user(과거 미검증)·macro·idle 의 캡처 수와 각각의 평균 FPS 를 나눠 적는다. `stage` 값마다(pre 포함):
   - 평균 FPS = Σ(disp_fps × span_s) ÷ Σ span_s, 캡처 수, 최대 vram_max_mib.
   - temp_median_c·power_median_w·clock_median_mhz 의 중앙값, temp_max_c 의 최댓값.
   - 제한 비율 = Σ thr_* ÷ Σ gpu_samples 를 SW Power Cap·SW Thermal·HW Thermal·Reliability 각각 %로.
   - 오늘 cooling 값이 둘 이상이면 같은 표를 cooling 값마다 나누고, 온도 중앙값·클럭 중앙값·열 제한 비율(thr_swthermal_s ÷ gpu_samples)을 값별로 비교한다. 0926 실측에서는 평평할 때 열 제한45~60초·2235~2400 MHz, 책 받침36초·2520 MHz, 에어컨 뒤0초·2580~2610 MHz가 관측됐다. 당시 높은 GPU 부하의 일부 캡처에는 약99 W 전력 한도가 기록됐다. 이 과거 관측이나 cooling.txt 라벨만으로 현재 에어컨·기기 배치·병목을 확정하지 않고, 최신 GPU 사용률·열 제한·전력 기록과 알려진 냉각 상태를 함께 적는다.
3. `C:\Users\rlfjr\gta-perf\codex-verdict.md`에 확인 시각, 지금 단계와 조합, 신규 판정, 유효 표본 수, 실패 여부를 기록한다. 기존 Claude 보고와 실행 기록은 과거 자료로 보존한다.
4. 단계 변경·측정 완료·실패·사용자 조치가 필요한 결과만 현재 Codex 작업 채팅에서 한국어로 알린다. 변화가 없으면 정기 보고를 남기지 않는다. 메일과 별도 22시 보고는 보내지 않는다.
5. 사다리가 끝나거나 2026-10-10 기한이 지나면 최종 결과와 미완료 사유를 현재 채팅에 알리고 Codex 후속 확인 `gta-obs`를 종료한다.

## 절대 금지
- 게임 창에 키·클릭을 보내거나, 창을 옮기거나, 게임을 끄지 않는다(디스플레이 변경과 창 이동에 게임이 종료된다).
- settings.xml, pending.json, ladder.json 을 고치지 않는다. 판정은 감시 스크립트 몫이다.
- GTA 그래픽 결과를 메일로 발송하거나 메일 초안을 만들지 않는다. 보고 채널은 현재 Codex 작업 채팅이다.
