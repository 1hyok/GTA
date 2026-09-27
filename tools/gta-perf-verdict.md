---
name: gta-perf-verdict
description: GTA V Enhanced 그래픽 사다리(0~4단계, 평균 60 FPS 기준) 진행을 매일 22:00 KST 에 읽고, 단계가 바뀐 날과 끝난 날만 Gmail 로 알린다. 판정은 감시 스크립트가 직접 한다.
---

윈도우 PC 의 Claude 예약 작업 `gta-perf-verdict` 의 지시서다. 예약 작업 프롬프트는 이 파일을 가리키는 포인터다. 0927 에 career-prep 저장소(취업 준비용)에서 이 저장소로 옮겼다. 이 파일은 이 PC 에만 있으니 pull 없이 읽는다.

## 배경
사용자(일혁) 지시: "fps 높으면 좀 떨어져도 되는데", "네가 바꿔 미리 바꿔 놓고 유지해도 되는지 시간 두고 지켜 봐야 할 거 아니야", 그리고 "FPS는 평균 60만 되면 돼". 그래서 GTA V Enhanced 그래픽을 한 단계씩 올리고, 단계마다 평균 60 FPS 를 지키는지 본다.

| 단계 | settings.xml `<graphics>` 키 | 올린 값 | 되돌릴 값 |
|---|---|---|---|
| 0 | dlssQuality (DLAA) | 3 | 2 |
| 1 | Tessellation, WaterQuality, Shadow_LongShadows, RTIndirectDiffuse_SecondBounce_Enabled, RTReflection_FullRes_Enabled | 3, 3, true, true, true | 2, 2, false, false, false |
| 2 | ParticleQuality, ShadowQuality | 3, 3 | 2, 2 |
| 3 | GrassQuality | 3 | 2 |
| 4 | UltraShadows_Enabled | true | false |

0단계(DLAA)는 게임 메뉴에서만 켤 수 있다. 2026-09-26 14:41 에 사용자 승인을 받아 메뉴에서 켰다(dlssQuality 2→3). 0926 20:11 에 통과했고(평균 80.1 FPS), 1단계는 0926 23:06:41 게임이 꺼진 순간 적용됐다. 프레임 생성(DLSS FG 2X)·DLSS 품질·프레임 제한 120·VSync 는 건드리지 않는다.

## 누가 무엇을 하나
- **판정과 적용은 윈도우 작업 스케줄러 작업 `GTA Perf Watch` 가 한다.** 10분마다 같은 폴더의 `gta-perf-watch.ps1` 을 숨겨서 돌린다. GTA 가 전경이면 PresentMon 으로 60초를 잰다. 지금 단계의 전경 캡처 중 OBS 가 꺼져 있고, 사용자가 직접 플레이했고(play=user), GPU 평균 사용률이 90% 이상인 것이 6개 모이면 판정한다. 매크로가 도는 정지 장면(macro)과 아무 입력 없는 장면(idle)은 FPS 가 실제 플레이보다 높게 나오고, GPU 사용률 90% 미만(나이트클럽 안처럼 사람이 많아 CPU 가 막는 장면)은 그래픽 단계와 무관하게 낮게 나와서, 기록만 하고 판정에서 뺀다. 통과 기준은 표시 FPS 시간 가중 평균 60 이상, VRAM 7600 MiB 이하, 그 단계 동안 GTA 비정상 종료 없음이다. 실패하면 그 단계만 되돌리고 다음 단계로 간다. 4단계 뒤에는 남은 조합으로 6개를 더 재 확인하고 끝난다. 확인에 실패하면 가장 최근에 남긴 단계를 되돌리고 다시 확인한다. 값은 게임이 꺼진 순간에만 settings.xml 에 쓴다. 늦어도 2026-10-10 23:59 에 끝나고, 끝나면 작업을 스스로 지운다.
- **이 루틴은 읽고 알리기만 한다.** settings.xml·pending.json·ladder.json 을 고치지 않는다.

## 자료 (전부 `C:\Users\rlfjr\gta-perf`)
AppData 가 아니다. Claude 앱(MSIX)에서 띄운 프로세스가 AppData 에 쓰면 패키지 전용 폴더로 가상화돼 작업 스케줄러와 다른 파일을 보게 되므로 AppData 밖에 둔다.
- `ladder.json`: `state.phase`(measure/confirm/done), `state.stage`, `state.expected`(지금 조합), `state.kept`·`state.reverted`, `state.history`(판정마다 time, label, result, avgFps, captures, maxVramMiB, crashes, reason, action).
- `ladder.log`: 판정·재적용·종료를 한 줄씩. 오늘 날짜 줄이 있으면 그날 단계가 바뀐 것이다.
- `perf.csv`: 실행마다 한 줄. `status`(capture/background/not_running/expired), `stage`(pre, S0~S4, confirm1…, waiting-apply, mismatch, done), `cooling`(cooling.txt 첫 줄 값, 아래 참고), `obs`(yes/no), `play`(user/macro/idle), 12개 설정 키, `disp_fps`, `disp_1pct_low_p99`, `span_s`, `gpu_util_pct`, `vram_max_mib`, `temp_max_c`, `temp_median_c`, `power_median_w`, `power_limit_median_w`, `clock_median_mhz`, `gpu_samples`(1초 표본 수), `thr_swpower_s`·`thr_swthermal_s`·`thr_hwthermal_s`·`thr_reliability_s`(각 제한이 걸린 초 수), `active_samples`·`samples`(사용자 입력 표본), `fg_ratio`, `macro_activity`, `gta_start`, `gta_restart`, `crash_events_new`.
- `crashes.csv`, `applied.log`(settings.xml 을 쓴 시각·값·백업), `watch.log`, `cooling.txt`(있으면 첫 줄이 cooling 값, 아래 줄은 바뀐 시각과 이유). 값은 flat(0926 19:15 전), raised(노트북 밑에 책, 19:15~), raised_ac(책 + 에어컨, 19:33~), side_ac(책 + 에어컨 + 노트북을 옆으로 세움, 0926 23:00~)이다.
- `verdict.md`(이 루틴이 쓰는 보고), `verdict-runs.md`(이 루틴의 실행 기록).

## 할 일 (매일 22:00)
1. 작업이 살아 있는지 본다: `Get-ScheduledTask -TaskName 'GTA Perf Watch'`. ladder 가 done 이 아닌데 작업이 없으면 아래로 다시 등록하고 보고에 적는다.
```powershell
$a = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wscript.exe" -Argument '//B //Nologo "C:\Users\rlfjr\GTA\tools\gta-perf-watch.vbs"' -WorkingDirectory 'C:\Users\rlfjr\GTA\tools'
$t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 20)
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 8)
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'GTA Perf Watch' -Action $a -Trigger $t -Settings $s -Principal $p
```
2. 단계별 표를 만든다. 쓰는 줄은 `status` 가 capture, `obs` 가 no, `fg_ratio` 가 0.9 이상인 줄이다. `play` 열로 나눈다. 캡처 60초 동안 매크로 로그(gta-afk·gta-macro·gta-claw)가 갱신됐으면 macro, 아니고 마지막 입력이 60초 안이면 user, 둘 다 아니면 idle 이다. user 중에서도 `gpu_util_pct` 가 90 미만인 줄은 `user(cpu)` 로 따로 센다(0926 21:10~23:00 실측: GPU 55~90 %, 전력 한도가 99 W 에서 71~83 W 로 내려감, 43~68 FPS). 판정은 GPU 90% 이상 user 만 쓰지만, 표에는 user·user(cpu)·macro·idle 의 캡처 수와 각각의 평균 FPS 를 나눠 적는다. `stage` 값마다(pre 포함):
   - 평균 FPS = Σ(disp_fps × span_s) ÷ Σ span_s, 캡처 수, 최대 vram_max_mib.
   - temp_median_c·power_median_w·clock_median_mhz 의 중앙값, temp_max_c 의 최댓값.
   - 제한 비율 = Σ thr_* ÷ Σ gpu_samples 를 SW Power Cap·SW Thermal·HW Thermal·Reliability 각각 %로.
   - 오늘 cooling 값이 둘 이상이면 같은 표를 cooling 값마다 나누고, 온도 중앙값·클럭 중앙값·열 제한 비율(thr_swthermal_s ÷ gpu_samples)을 값별로 비교한다. 이 노트북 GPU(RTX 4060 Laptop)는 86도쯤에서 열 제한을 걸므로 냉각이 좋아지면 온도보다 열 제한 시간과 클럭이 먼저 바뀐다(0926 실측: 평평 45~60초·2235~2400 MHz, 책 받침 36초·2520 MHz, 에어컨 뒤 0초·2580~2610 MHz). 열 제한이 0초가 된 뒤에는 병목이 전력 한도(약 99 W)다.
3. `C:\Users\rlfjr\gta-perf\verdict.md` 맨 위에 오늘 절을 더한다(이전 절은 아래에 남긴다): 날짜, 지금 phase·단계·조합, 오늘 ladder.log 줄, 단계별 표, 되돌린 단계와 이유, 비정상 종료, 작업 상태.
4. 메일은 **오늘 단계가 바뀌었을 때**(ladder.log 에 오늘 날짜의 판정 줄이 있을 때)와 **사다리가 끝났을 때**만 Gmail 커넥터 `send_message` 로 `dnfjddk2@gmail.com` 에 보낸다. 그 밖의 날은 보내지 않는다. `PushNotification` 은 예약 실행에서 폰에 가지 않으니 쓰지 않는다.
   - subject: `[GTA 그래픽] <n>단계 <통과|실패, 되돌림> → 지금 <단계>` 또는 끝난 날은 `[GTA 그래픽] 사다리 끝: <남은 조합 요약>`
   - body(평문, 14줄 이내): 지금 단계, 단계별 user·user(cpu)·macro·idle 캡처 수와 각각의 평균 FPS·최대 VRAM 한 줄씩, 단계별 온도·전력·클럭 중앙값과 열·전력 제한 비율 한 줄씩, 되돌린 게 있으면 그 이유, cooling 이 바뀐 날이면 cooling 값별로 나눈 값, 자세한 표는 `C:\Users\rlfjr\gta-perf\verdict.md`.
5. `C:\Users\rlfjr\gta-perf\verdict-runs.md` 맨 위(제목 줄 바로 아래)에 `- <yyyy-MM-dd HH:mm> <phase>/<단계>: <오늘 한 줄> (메일 <보냄|안 보냄>)` 을 더한다. 이 폴더는 git 저장소가 아니니 커밋하지 않는다.
6. **감시가 끝났으면**(ladder.json 의 phase 가 done 이고 작업 GTA Perf Watch 가 없거나, 2026-10-10 이 지났으면) 4단계의 끝난 날 메일을 보내고 5단계 기록을 남긴 뒤, ToolSearch 로 `mcp__scheduled-tasks__delete_scheduled_task` 를 불러 taskId `gta-perf-verdict` 를 지운다.

## 절대 금지
- 게임 창에 키·클릭을 보내거나, 창을 옮기거나, 게임을 끄지 않는다(디스플레이 변경과 창 이동에 게임이 종료된다).
- settings.xml, pending.json, ladder.json 을 고치지 않는다. 판정은 감시 스크립트 몫이다.
- 같은 날 같은 메일을 두 번 보내지 않는다. Gmail `subject:"[GTA 그래픽]" newer_than:1d` 로 이미 보냈는지 먼저 본다.
