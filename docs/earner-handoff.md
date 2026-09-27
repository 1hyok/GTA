# 수익 자동화 인계 (2026-09-27, Claude Code → Codex)

## 지금 상태

- 나이트클럽 금고 비우기 동작은 게임에서 성공했다(0927 00:48, $12,000 → $0).
- 금고 작업 전체(나이트클럽에 들어가 금고까지 걷기 → 비우기 → 아케이드 MCT 로 돌아오기)는 아직 한 번도 끝까지 통과하지 못했다. 막힌 곳은 "나이트클럽 1층 스폰에서 사무실로 가는 길 고르기"다(아래 "마지막 시험").
- 벙커 보급 구매·DJ 교체는 MCT 화면을 아직 실측하지 못해 구매·교체 함수가 멈추기만 한다. 그래서 `Config.ini` 기본값이 `EarnBunker=0`, `EarnDJ=0` 이다.
- 현장 파견은 손대지 않았다.
- 11:14 에 `Main.ahk` 를 다시 켜 AFK 방지가 켜져 있다(`%TEMP%\gta-afk.log` 의 "11:14:19 on"). GTA 는 10:58 에 누군가 다시 켰고, 그때 `Main.ahk` 는 꺼져 있었다(누가 껐는지는 모름).

## 요청 (요청자: 사용자 일혁)

`Main.ahk` 안에 스케줄러 하나를 두고 아래를 돌린다. 단축키는 F9 두 번(`Features/Earn/Earner.ahk`).

1. 벙커 보급: 아케이드 지하 MCT 에서 산다. 보급 한 칸(20%)이 다 비었을 때만 산다(업그레이드 완료 기준 한 칸 28분). 재고가 가득이면(생산 멈춤) 사지 않는다. 막대를 못 읽으면 사지 말고 로그만 남긴다. 보급이 가득일 때 게임이 구매를 막는지도 확인한다.
2. DJ 교체: MCT 에서 이미 고용한 DJ 끼리 바꾼다($10,000, 인기도 +10%). 인기도 95% 미만이면 95% 이상이 될 때까지, 한 번에 최대 10번. 바꿀 때마다 인기도가 올랐는지 확인하고, 안 올랐거나 못 읽으면 바로 멈춘다. 막대가 연속으로 차는지 20% 단위인지 실측한다.
3. 나이트클럽 금고: 약 3.5시간마다 비운다(상한 $250,000).
4. 현장 파견: 선택. 할 가치가 없으면 빼고 이유를 적는다. 스폰으로 못 가는 부동산은 사용자가 만든 워프 작업(즐겨찾기 11~17, Apse18)을 쓴다. 같은 것을 또 즐겨찾기하지 않는다.

### 반드시 지킬 것

- 금지: 결제·구독·크레딧 버튼, 게임에 Esc(Backspace 를 쓴다), 종료 확인창 Yes, 즐겨찾기 삭제, $100,000 짜리 새 DJ 고용 줄, 사용자에게 게임 조작을 부탁하기.
- CEO·MC 는 평소 은퇴 상태다. MCT 작업 동안만 CEO 로 등록하고, 구매·교체가 끝나면 바로 Retire 한 뒤 M 메뉴에 "Register as a Boss" 가 보이는지 확인한다.
- 키를 보내기 전마다 화면으로 확인한다. 확인이 안 되면 그 자리에서 멈추고 AFK 방지는 켜 둔다. 확인창의 Enter·클릭은 화면에서 문구를 확인한 뒤에만 보낸다.
- 금고 가느라 아케이드를 떠난 동안 벙커는 쉬고, 돌아와 MCT 가 열리는 것을 확인한 뒤 이어서 한다.
- AFK 방지·End(전체 멈춤)와 같이 돌아야 한다.
- 게임을 다시 켜야 하면 사용자와 먼저 맞춘다. 게임이 꺼진 동안 `settings.xml` 을 고치지 않는다.
- 커밋·푸시는 묻지 않고 한다. 스테이징은 자기 변경분만 한다.
- 사용자에게는 한국어로 답하고, 작업 중에 들어온 질문에는 바로 답한다. 토큰을 아끼기 위해 판정은 로그로 하고, 캡처는 실패했을 때만 한다.

## 파일

| 파일 | 내용 |
|---|---|
| `Features/Earn/Earner.ahk` | 스케줄러. 5초마다 때가 된 작업 하나를 끝까지 한다. 사용자가 45초 안에 입력했거나 다른 매크로가 키를 보내는 중이면 기다린다. 위험하지 않은 실패는 `EarnSoftFail` 로 N분 뒤 다시(연속 12번이면 끈다), 나머지 실패는 전체를 끄고 AFK 방지를 켠다 |
| `Features/Earn/EarnTasks.ahk` | 작업 본체. `EarnSafeTask`, `EarnGoHome`(MCT 로 복귀), `EarnRejoin`(초대 전용 세션으로 다시 들어가기), `EarnBunkerTask`(28분 규칙까지 구현, `EarnBunkerBuy` 는 멈추기만 함), `EarnDJTask`(`EarnDJSwapLoop` 는 멈추기만 함), `EarnDispatchTask`(빈 함수) |
| `Features/Earn/EarnCore.ahk` | 공통 함수. 템플릿 확인, 상호작용 메뉴·스폰 위치, 미니맵 아이콘 찾기(`EarnBlip`), 길 찾기(`EarnNavPlan`, `EarnNavTo`), 카메라 돌리기(`EarnTurn`), MCT 열고 닫기, 막대 읽기(`EarnBarFill`), CEO 등록·은퇴(`EarnCEO`, 템플릿 미캡처), 인기도 읽기 |
| `Images/Earn/1920x1080/*.png` | 템플릿. 분홍(FF00FF) 칸은 투명 |
| `Features/SessionSwitch.ahk` | 초대 전용 세션 이동. `JoinInviteOnlySession(false)` 는 End 신호를 지우지 않는다 |
| `Core/Screen.ahk` | `TemplateSeen` |
| `Config.ini` `[Settings]` `Earn*` | 설정과 설명 주석 |
| `tools/earn-test/` | 시험 도구(아래 "시험 방법") |
| `Features/RegisterCEO.ahk` | 기존 CEO 등록 메뉴 매크로(화면 확인 없이 정해진 횟수로 누름). `EarnCEO` 는 템플릿 확인 방식으로 따로 짰다 |

## 실측 사실 (이 PC, 1920x1080)

### 미니맵과 이동

- 미니맵 영역은 화면 좌표 (20,860)-(310,1050), 플레이어 화살표 중심은 (164,1005).
- 아이콘은 템플릿으로 안 잡힌다(그릴 때마다 1px 씩 달라짐). 색 덩어리로 찾는다.
  - 금고 `$`: 가득이면 빨강(0xDE3030 부근), 덜 찼으면 초록(0x72CC72 부근), $0 이면 아이콘이 없다.
  - 노트북: 흰 덩어리 높이 5~7px. MCT 모니터: 흰 덩어리 높이 8~10px.
  - 미니맵 범위 밖의 아이콘은 가장자리에 붙어 그려진다. 이때는 방향만 믿고 거리는 999 로 돌려준다.
- 미니맵은 지금 층만 그린다. 다른 층에 있는 금고는 아이콘이 안 보인다.
- 카메라는 `mouse_event` 상대 이동으로 돌린다. 약 29단위가 1도다. 빠르게 돌리면(10~12ms 마다 40~60단위 이상) 게임이 미니맵을 몇 초 동안 축소해 판정이 깨진다. 그래서 `EarnTurn` 은 15ms 마다 20단위씩 돌리고, 걸은 뒤 1.3초 기다린다.
- 길 찾기: 미니맵에서 바닥 밝기(평균 85~150)인 칸을 3px 격자로 보고 BFS 를 돈다. 가장자리 아이콘이면 진행 지표로 실제 거리 대신 "길 끝까지 남은 거리" 를 쓴다.
- 체력 막대 초록(0x4C8F4C, y 1049~1057)이 보이면 로딩이 끝난 것으로 본다.
- 툴팁이 미니맵을 가려 판정이 깨진 적이 있어, 툴팁을 미니맵 오른쪽으로 옮겼다(`Core/Common.ahk`).

### 스폰

- 스폰 위치는 상호작용 메뉴 Preferences → Spawn Location 에서 Left/Right 로 고른다. Nightclub 에서 Right 2 번이 Arcade 다.
- 나이트클럽 스폰 자리는 매번 바뀐다(1층 바·댄스플로어·화장실, 2층 난간·뒷방, 침대 옆). 같은 자리가 몇 번 이어지기도 한다.
- 조사(0927 01:51~01:59, 걷지 않고 다시 들어가기만 8번씩):
  - 나이트클럽 8/8 이 1층. 노트북 아이콘은 가장자리(방향 -12°, 153°, 81°, 29°, 5° 등), 금고 아이콘은 한 번도 안 보임.
  - 아케이드 8/8 이 지하 차고의 같은 자리. 노트북 41°, 길 끝까지 10px. 이때 "금고" 로 잡힌 25° 덩어리는 초록 물체 오탐이라 아케이드에서는 금고를 찾지 않는다.
- 전에 성공한 길: 1층 바에서 노트북 방향을 따라가 사무실에 도착(40걸음, 약 2분) 1번, 침대 옆 스폰에서 도착 1번.

### 금고

- 나이트클럽 안에서는 화면 오른쪽 아래에 "WALL SAFE $X" 가 보인다(`hud_safe_label`, $0 이면 `hud_safe_zero`).
- 비우는 순서: 금고 앞에서 `safe_prompt` 확인 → E → 4.5초 → `hud_safe_zero` 와 `safe_close_prompt` 확인(안 보이면 금고 쪽으로 돌고 조금 걸어 최대 4번) → E → 닫힘 안내가 사라질 때까지 기다림(`EarnSafeCollect`).

### MCT·세션·기타

- MCT 는 CEO 가 아니면 "CEO 가 필요하다" 는 화면(`mct_need_ceo`)이 뜬다. 여는 순서: `mct_sit` 안내 → E → `mct_seated` → Enter → `mct_title`. 닫을 때는 `mct_seated` 가 보일 때까지 Backspace, 그다음 오른쪽 클릭.
- MCT 카드 막대(화면 좌표): 벙커 재고 초록 y555, 보급 파랑 y577(x 766~1154), 나이트클럽 인기도 y471(x 340~708).
- 나이트클럽 안 인기도 HUD 는 5칸(x 1751~1880, y 1048).
- 세션 이동은 일시정지 메뉴 ONLINE → Find New Session → Invite Only Session. ONLINE 목록 길이가 바뀌어 줄 수가 아니라 오른쪽 칸 제목 템플릿으로 판정한다(`d81d3c2`).
- 위키에는 나이트클럽 사무실 컴퓨터로도 DJ 를 바꿀 수 있다고 나오지만 게임에서는 확인하지 않았다.

## 마지막 시험 (0927 02:58~03:04, `EarnSafeTask`)

- 나이트클럽에 11번 다시 들어가는 동안 매번 "이 자리에서는 못 감(길 없음)" 이 나왔다.
- 원인: `EarnSpawnRoute()` 가 노트북 아이콘이 가장자리에 걸린 경우(거리 999)를 받지 않는다. 조사에서 나이트클럽 스폰이 전부 1층이었으니, 이 조건으로는 길을 고를 수 없다.
- 12번째로 다시 들어가다 세션 메뉴 제목을 확인하지 못해 멈췄다(`invite-only 중단`). 03:03:40 에 `Main.ahk` 쪽 수익 자동화가 켜졌다가 1초 만에 꺼진 기록이 있어, 누가 F9 를 눌렀거나 포커스가 빠진 것으로 보인다. 원인은 확인하지 못했다.

## 다음 순서 (권장)

1. `EarnSpawnRoute()` 가 가장자리 노트북(거리 999)도 받게 고친다. `EarnNavTo("laptop")` 은 가장자리 아이콘일 때 길 끝 거리를 진행 지표로 쓰도록 이미 되어 있다. 1층 → 계단 → 사무실까지 가는지 본다.
2. 사무실(같은 층)에 들어가면 금고 아이콘이 보인다. `EarnNavTo("safe", "safe_prompt")` 로 금고 앞까지 간다.
3. 금고가 $0 이면 HUD 로 판정해 건너뛴다(이미 있음).
4. 복귀는 스폰을 Arcade 로 두고 다시 들어가 차고 → 노트북 → MCT(`EarnGoHome`, `EarnWalkToMCT`).
5. 끝까지 통과하면 커밋한다.
6. CEO 메뉴 템플릿(`m_boss`, `m_boss_sel`, `m_ceo_sel`, `m_start_org_sel`, `m_securo`, `m_securo_sel`, `m_retire_sel`)을 떠서 `EarnCEO` 를 완성한다.
7. CEO 상태로 MCT 에 들어가 벙커 보급 구매 화면과 DJ 화면을 실측하고 `EarnBunkerBuy`, `EarnDJSwapLoop` 을 짠다. DJ 는 $100,000 새 DJ 줄을 절대 누르지 않는다.
8. 현장 파견을 할 가치가 있는지 판단한다.
9. 사용자에게 최종 보고: 스폰 목록, 테러바이트 MCT 미확인, 고른 거점, 기능별 결과, 뺀 것과 이유, 커밋 해시.

## 시험 방법

- 하네스: `tools/earn-test/earntest.ahk` 가 `Main.ahk` 없이 함수 하나를 부른다. 결과 한 줄은 표준 출력, 과정은 `%TEMP%\gta-earn.log`.

  ```powershell
  $ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
  & $ahk /ErrorStdOut /Validate tools\earn-test\earntest.ahk          # 문법 확인
  $p = Start-Process $ahk -ArgumentList 'tools\earn-test\earntest.ahk','EarnSafeTask' -PassThru -RedirectStandardOutput "$env:TEMP\et_safe.out"
  if (-not $p.WaitForExit(25 * 60 * 1000)) { $p.Kill() }             # AHK 경고창이 뜨면 멈춘 채 기다리므로 시간 제한을 꼭 둔다
  Get-Content "$env:TEMP\gta-earn.log" -Tail 30
  ```

  다른 예: `earntest.ahk Census Nightclub 8 Left`(스폰 자리 조사), `earntest.ahk BlipInfo laptop`, `earntest.ahk NavInfo safe`.
- 시험하는 동안 `Main.ahk` 의 AFK 방지가 W/S 를 끼워 넣으므로, 시험 전에 F4 로 끄고 끝나면 다시 켠다. 켜고 끈 기록은 `%TEMP%\gta-afk.log`.
- `tools/earn-test/nav.ps1 -Keys F4`: 사용자가 12초 동안 입력하지 않을 때 GTA 를 앞으로 가져와 키를 보낸다. 종료 코드 4 는 GTA 가 앞이 아니라 키를 하나도 안 보냈다는 뜻이다. `-Shot` 은 이 PC 의 다른 도구를 부르므로 쓰지 않는다.
- `tools/earn-test/capscreen.ps1 -Name x -X 0 -Y 0 -W 1920 -H 1080 -Scale 1`: 게임 모니터 캡처(`%TEMP%\claude\x.png`). 기본값은 오른쪽 노트북 화면이라 인자를 꼭 준다.
- `tools/earn-test/look.ps1 -Dx 600 -Steps 30 -StepMs 15`: 카메라를 천천히 돌린다(한 번에 20단위 안팎).
- 로그: `%TEMP%\gta-earn.log`(수익), `%TEMP%\gta-afk.log`(AFK), `%TEMP%\gta-macro.log`(세션 이동 등).
