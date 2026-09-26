# GTA Online 매크로

GTA V Enhanced(Steam, `GTA5_Enhanced.exe`) 온라인용 키 입력 매크로. AutoHotkey v2 로 `Main.ahk` 하나를 띄우면 아래 기능이 전부 올라온다. 메모리 읽기·인젝션·게임 파일 수정은 없고, 키보드·마우스 입력과 화면 캡처만 쓴다.

## 실행

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" "C:\Users\rlfjr\GTA\Main.ahk"
```

같은 폴더의 `Config.ini` 를 읽는다(없으면 알림창 뒤 종료). 다시 실행하면 이전 인스턴스를 교체한다. 시작하면 AFK 방지(`[Features] AntiAFK=1` 이고 `AFKOnStart=1` 일 때)와 오버레이(`OverlayEnabled=1`)가 켜진 채로 뜬다.

고친 뒤 검사는 같은 폴더의 사본으로 한다(`#Include Core\…` 가 상대 경로라 다른 폴더에서는 못 읽는다). `/validate` 는 실행하지 않고 문법만 본다.

```powershell
Copy-Item Main.ahk Main_check.ahk
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" /validate /ErrorStdOut Main_check.ahk
[IO.File]::Delete("Main_check.ahk")
```

## 사용법을 보는 곳

- 게임 안: `Num.` 한 번이면 현재 키맵 툴팁이 8초 뜬다(다시 누르면 닫힘). 2초 안에 두 번 누르면 설정 창이 열린다.
- 설정 창: 트레이 아이콘 더블클릭, 또는 트레이 메뉴 "설정 창 열기". 노트북 화면(GTA 가 없는 모니터) 가운데에 뜬다. 지금 상태, 기능 실행 버튼, `Config.ini` 값 저장, 최근 로그(`gta-macro.log`·`gta-afk.log` 끝 15줄씩)가 한 창에 있다. 실행 버튼은 GTA 를 앞으로 가져온 뒤 누르고, 두 번 눌러야 하는 기능은 키(2초)와 달리 3초 안에 두 번 누른다.
- 트레이 메뉴: 설정 창 열기 / 단축키 보기 / AFK 방지 켜기·끄기 / 전체 멈춤 / 종료.
- 오버레이: 게임 오른쪽 위(돈 표시 아래)에 도는 기능과 AFK 상태가 한 줄씩 보인다. 클릭이 통과하고 게임에 입력을 보내지 않는다. 위치(`OverlayXPct`·`OverlayYPct`)가 화면 감지 영역(오른쪽 아래 구석, 왼쪽 위, 화면 가운데)을 덮으면 기본 위치로 되돌아가고 그것도 덮으면 숨는다.
- 이 파일과 `Config.ini` 의 주석.
- 조사·실측 기록(작텔이 되는 조건, 봇 절차, 막힌 방법, 되돌리는 절차): dotfiles 의 `claude/skills/gta-online-research/SKILL.md`. 아래에 "0926 실측" 이라 적은 것은 거기에 근거가 있다.

## 키

게임 창이 앞일 때만 잡힌다(종료만 전역. 스팀 봇 작텔이 도는 동안은 전체 멈춤도 모든 창에서 잡힌다). 밖에서는 F키·넘패드가 원래대로 동작한다. ×2 는 2초 안에 두 번 눌러야 실행되는 기능이다(첫 누름에 "한 번 더 누르면 실행" 툴팁. 꾹 누르고 있는 자동 반복은 두 번째로 세지 않는다). 키 배정은 `Config.ini [Hotkeys]`, 쉼표로 여러 키를 붙일 수 있고 같은 키를 두 기능에 주면 먼저 등록된 쪽만 잡힌다.

| 키 | 기능 | 방식 |
|---|---|---|
| F4 | AFK 방지 | 토글 |
| F5 | 초대 전용 세션으로 이동 | ×2 |
| F6 | 달리기(Shift+W 유지) | 토글 |
| F7 | 자동 클릭 | 토글 |
| F8 | 벨럼 운전(W 유지 + 3초마다 LCtrl) | 토글 |
| F9 | 수익 자동화 | ×2 토글 |
| F10 | 작텔(스팀 봇) | ×2 |
| F11 | 작텔(Alt+F4) | ×2 |
| Num/ | 인형 뽑기 1판 | 한 번 |
| Num* | 인형 뽑기 반복 | 토글 |
| Num0 | 스낵 먹기 | 한 번 |
| Num1 | CEO 등록 | 한 번 |
| Num2 | MC 등록 | 한 번 |
| Num3 | 카요 페리코 48분 타이머 | 토글 |
| Num. | 도움말 (×2 설정 창) | 한 번 |
| End | 전체 멈춤 | 한 번 |
| Pause | 종료 | ×2, 전역 |

키가 비어 있는 기능: 걷기(`Walk`), CEO·MC 재등록 텔레포트(`TeleportMC1/2`, 기능도 꺼 둠), 카지노 지문 해킹(꺼 둠). 설정 창 버튼으로는 걷기를 실행할 수 있다. 남는 키는 ScrollLock.

## 작텔 (잡 워프)

둘 다 일시정지 지도에서 작업 블립을 골라 화면 아래에 "Start Job (Space)" 가 보이는 상태에서 누른다. 실내면 `P` 다음 `CapsLock` 으로 전체 지도. 도착지는 그 작업의 출발점이다. 두 작텔은 동시에 돌지 않는다(한쪽의 Enter 가 다른 쪽 확인창에 들어가는 것을 막는다).

즐겨찾기한 남의 작업은 지도에 블립이 안 뜬다(내가 만든 작업만 뜬다, 0926 실측). 그런 작업은 `P` → ONLINE → Jobs → Play Job → Bookmarked 에서 골라 CONFIRM 창이 뜬 상태에서 F10 두 번(매크로가 CONFIRM 을 보면 Space 를 건너뛰고 Enter 부터 한다). F11 은 화면을 보지 않고 Space 부터 보내므로 지도에서만 쓴다.

### F11 두 번: Alt+F4 방식

사전 설정: Online → Options → Matchmaking = Closed, 상호작용 메뉴 → Preferences → Map Blip Options → Jobs 표시.

Space → CONFIRM Enter → 바로 Alt+F4 → 게임 종료 확인창에서 60초가 지나고 오른쪽 아래 No/Yes 안내가 보이면 Backspace(No). 작업 로딩이 뒤에서 튕기고 나면 작업 위치 프리모드에 떨어진다. 임무 중에도 된다(0926 실측: 페이폰 히트 중 두 번 성공, 목표·타이머 유지).

- No/Yes 안내는 20초쯤에 뜨지만 그때 누르면 작업 로비로 들어간다(0926 실측: 32초 실패, 60초 성공 2회). `JobWarpMinWaitMs=60000` 을 줄이지 않는다.
- 90초까지 안내를 못 찾거나 대기 중 End 를 누르면 매크로는 Backspace 를 안 보낸다. 종료 확인창은 직접 Backspace 로 닫는다. Enter(Yes)는 게임이 꺼진다.
- 로비로 들어갔으면 Backspace → Yes 로 나오면 원래 자리.
- 오버레이가 "작텔 대기 N/60초" 를 보여 준다. 안내 감지 자리가 오른쪽 아래 구석이라 오버레이를 거기에 두지 않는다.

### F10 두 번: 스팀 봇 방식

작업 시작 → 로딩 중 스팀 그룹 채팅 "CCYXJ差传" 의 봇(`BotWarpBotRow` 1: 差传CCYXJ01, 2: 差传CCYXJ03)에 Join Game → "join a different session" Enter → (조준 모드가 다르면 경고 Enter) → "incompatible assets" Enter → 약 20초 뒤 출발점. 60초 대기가 없어 F11 보다 빠르다.

- 준비: 스팀 그룹 채팅 창을 열어 둔다(매크로가 노트북 화면 오른쪽 위로 옮긴다. 필터 칸은 좌표로, 봇 줄과 Join Game 은 `Images\BotWarp\steam\` 참조 이미지로 찾은 자리를 누른다). 노트북 화면 배율 175%, 게임 16:9. `join_game.png` 가 없으면 시작하지 않는다. 봇이 게임 중(멤버 목록에서 초록 글자)이어야 한다.
- 채팅 창이 없으면 `open_in_steam.png`·`join_group_chat.png` 가 있을 때만 초대 링크로 자동으로 연다(친구 목록 창이 없으면 매크로가 먼저 띄운다. 0926 실측: 친구 목록이 한 번도 안 뜬 상태에서는 Open in Steam 이 무반응). 두 장이 없으면 채팅 창을 직접 열어 두라고 알리고 멈춘다.
- 메뉴 매크로·인형 뽑기·수익 자동화·이동·자동 클릭 토글이 켜져 있으면 시작하지 않는다.
- 도착한 세션은 새 세션이다(초대 전용이 아니다). 거기서 다시 Start Job 을 누르면 "Currently unavailable" 이 뜨니 매크로가 Backspace 로 닫고 멈춘다. F5 두 번으로 초대 전용에 옮긴 뒤 다시 한다. 세션을 옮긴 직후에는 지도에 블립이 한동안 없다. 그때는 위의 Play Job 경로.
- 조준 모드 경고를 거절(Backspace)하는 옛 방식은 게임이 13분 넘게 멈춘다(0926 실측). 수락하면 조준 모드가 봇 쪽으로 바뀐다(0926 실측: Assisted Aim - Partial). 초대 전용 세션 위주면 되돌릴 필요가 거의 없고, 되돌리는 절차는 조사 스킬에 있다.
- Join Game 뒤에 키보드를 만지면 사용자가 넘겨받은 것으로 보고 멈춘다. Join Game 뒤 20초 안에 참가 알림이 안 뜨면 멈추는데 작업은 로딩 중이니 봇에 직접 Join Game 하거나 작업을 나간다. incompatible 알림 없이 게임 화면으로 돌아오면 봇 세션에 들어갔을 수 있으니 위치를 확인한다.
- 중단은 End(스팀 창이 앞이어도 먹는다). CONFIRM 대기 중에 멈췄으면 확인창을 직접 Backspace 로 닫는다.
- KeyHoldTest.ahk·LCtrlSpammer.ahk 도 F10 을 쓰니 같이 켜지 않는다.

## 초대 전용 세션 (F5 두 번)

`P` → ONLINE → Find New Session → Invite Only Session → 확인창 OK. 줄 수를 세지 않고, ONLINE 목록에 들어간 뒤부터는 오른쪽 칸 제목과 확인창 문구를 템플릿(`Images\Session\1920x1080\`)으로 확인한 뒤에만 Enter 를 보낸다. 게임을 켠 방식에 따라 ONLINE 목록 길이가 달라 줄 높이로 세면 Quit to Story Mode 에서 Enter 가 나갔다(0926). 제목을 못 찾으면 그 자리에서 멈추고, 마지막 확인창 문구가 3초 안에 "quit this session" 으로 확인되지 않으면 Backspace 로 취소하고 멈춘다. 어느 쪽이든 열린 메뉴는 직접 닫는다. 템플릿이 1920x1080 것뿐이라 다른 해상도는 안 된다.

## AFK 방지 (F4)

키보드·마우스를 45초 안 만졌을 때만 200초(±20초)마다 W 와 S 를 150ms 씩 번갈아 누른다. 다른 창이 앞이면 GTA 를 앞으로 가져온 뒤 누르고, 못 가져오면 30초 뒤 다시 한다. 인형 반복·이동 토글·자동 클릭·작텔이 켜져 있는 동안과 수익 자동화가 작업 하나를 실제로 하는 동안은 쉰다(수익 자동화를 켜면 AFK 방지도 같이 켜진다). End 는 AFK 방지를 끄지 않는다.

- 메뉴가 열린 채 자리를 비우면 W/S 가 Up/Down 으로 먹어 선택 줄이 밀린다(0926 실측: 지도 범례가 8칸 밀림). 메뉴는 닫아 두거나 F4 로 끈다.
- 입력 없음 시간과 간격은 설정 창에서 바꾼다(5~600초, 30~600초). 나머지 값은 `Config.ini`. 로그는 `%TEMP%\gta-afk.log`.

## 상호작용 메뉴 매크로 (Num0 / Num1 / Num2)

M 을 열고 `Config.ini` 의 칸 수대로 Down·Enter 를 보낸다(스낵만 끝에 M 으로 다시 닫는다). 화면 확인이 없어 커서는 맨 위(Quick GPS) 기준이고, 게임이 마지막 커서 위치를 기억하므로 다른 항목에 두고 닫았으면 한 번 빗나간다. 칸 수 기본값은 공개 문서·매크로에서 가져온 것이라 안 맞으면 `[Settings]` 의 `CEO*`·`MC*`·`Snack*` 을 고친다. 한 번에 하나만 돌고, 다른 것이 진행 중이면 툴팁만 뜬다.

내 부동산(아케이드 등) 안에서는 맨 위에 "… Management" 줄이 하나 더 붙는다. 설정 창의 "부동산 안/밖" 라디오(`MenuTopOffset`)를 맞춘다. CEO·MC 등록이 끝나면 게임이 메뉴를 스스로 닫으므로 `CEOCloseMenu`·`MCCloseMenu` 는 0(1 이면 M 이 메뉴를 다시 연다, 0926 실측).

CEO·MC 는 평소 해제 상태로 둔다. 켜 두면 사업장이 습격 대상이 된다. 시험으로 등록했으면 그 자리에서 Retire·Disband.

## 이동·클릭 (F6 / F7 / F8)

F6 은 Shift+W, F8 은 W 를 누른 채 3초마다 LCtrl(벨럼 이륙 유지). 켜져 있는 동안 AFK 방지는 쉰다. 스크립트가 이동 키를 누른 채 끝나면 캐릭터가 계속 걸어가므로 종료·전체 멈춤·오류 때 매크로가 누른 키를 뗀다.

F7 자동 클릭은 커서가 게임 화면 안에 있을 때만 왼쪽 클릭을 반복한다(클릭마다 `ClickHoldTime` 50ms 누르고 `ClickInterval` 1ms 쉬므로 약 50ms 에 한 번). 문자·숫자·F키·Enter·방향키 같은 다른 키를 누르거나 커서가 게임 밖으로 나가면 멈춘다(0926: 커서가 설정 창 위에 남아 설정 창 버튼을 연타한 사고). 설정 창 버튼으로 켜면 커서를 게임 가운데로 옮겨 준다.

## 인형 뽑기 (Num/ 한 판, Num* 반복)

아케이드 기계 앞 "Press E to play" 상태에서 누른다. E → W 5초 → D 5초 → Enter 순서이고 단계마다 왼쪽 위 안내 문구 이미지(`Images\Claw\`)를 확인한 뒤에야 다음 키를 보낸다. 안내가 안 보이면 아무 키도 안 보내고 멈춘다(캐릭터가 걸어가 버리는 사고 방지). 반복을 끄면 진행 중인 판은 다음 키 전에 멈추고, 중간에 멈춘 판은 다음 시작 때 먼저 내려서 정리한다. 해상도별 폴더(`Images\Claw\<가로>x<세로>\`)가 있어야 하고 2560x1600 만 루트에 있다. 이동 시간 값(`ClawForwardMs`, `ClawRightMs`)은 1920x1080, RT 켬, DLSS 품질/FG 2X, 120fps 에서 잰 것이다. 로그는 `%TEMP%\gta-claw.log`, 진단 상태는 `%TEMP%\claw-status.ini`.

## 수익 자동화 (F9 두 번)

`Features\Earn\` 과 `Images\Earn\` 은 아직 커밋 전이다. 아케이드 지하 MCT 앞에 세우고 CEO·MC 를 해제한 뒤 켜면 5초마다 때가 된 일(벙커 보급·DJ 교체·나이트클럽 금고) 하나를 화면 템플릿(`Images\Earn\1920x1080\`)으로 확인하며 한다. 부동산 사이 이동은 스폰 위치를 바꾸고 초대 전용 세션으로 다시 들어가는 방식이라 세션이 바뀐다. 어느 단계든 확인이 안 되면 자동화 전체를 끄고 AFK 방지는 켜 둔다. 까닭은 `%TEMP%\gta-earn.log`, 오버레이, 설정 창. 작업은 마지막 키보드·마우스 입력에서 45초가 지나야 시작하고 5초마다 다시 보므로 손을 떼면 저절로 이어진다. 벙커 구매 화면과 DJ 교체 화면은 아직 자리표시자라 그 조건(보급이 한 칸 이상 빔, 인기도 95% 미만)에 이르면 전체가 꺼진다. 현장 파견은 `EarnDispatch=0` 으로 꺼 두어 돌지 않는다.

## 전체 멈춤 (End) · 종료 (Pause 두 번)

End 는 도는 것을 전부 멈추고(카요 타이머 포함) 누른 키를 뗀다. AFK 방지만 남긴다. 게임 밖에서 End 가 안 잡히면 트레이 메뉴. Pause 는 전역 키라 노트북 Fn 오타로 꺼지지 않게 두 번 눌러야 한다.

## 매크로가 지키는 것

- Esc 를 게임에 보내지 않는다. Rockstar 런처·스팀 Big Picture 가 앞이면 종료 확인으로 받는다. 뒤로 가기·No 는 Backspace.
- 게임 종료·세션 나가기·스토리 모드 확인창에 매크로가 보내는 키는 둘뿐이다. F5 는 문구가 "quit this session" 으로 확인될 때만 Enter(OK), F11 은 게임 종료 확인창에 60초 뒤 Backspace(No). 그 밖에는 아무 키도 보내지 않는다. "quit this Job?"(작업 로비 나가기)은 매크로가 다루지 않고 직접 Backspace → Yes 로 나온다.
- 키를 보내기 전마다 GTA 가 앞인지 본다. 진행 중인 시퀀스(메뉴 매크로·세션 이동·작텔·인형 뽑기)는 포커스가 빠지면 그 자리에서 멈춘다. AFK 방지·수익 자동화·설정 창 버튼은 멈추는 대신 GTA 를 앞으로 가져온 뒤 누른다.
- 초대 전용 세션·수익 자동화·작텔 알림은 메뉴에 들어간 직후 첫 키가 씹히는 일이 잦아 누른 횟수가 아니라 화면으로 판정한다. 상호작용 메뉴 매크로와 F11 의 Space → Enter 는 화면을 보지 않고 정해진 횟수·간격으로만 보낸다.
- CapsLock 이 켜져 있으면 AHK 가 키 앞뒤로 CapsLock 을 눌러 특수 능력이 발동하므로 `SetStoreCapsLockMode false`(0926 원인 확정).
- 오류 대화상자는 띄우지 않는다(포커스를 빼앗아 AFK 방지까지 막는다). `%TEMP%\gta-macro.log` 의 `[error]` 줄과 툴팁으로 알린다. 예외는 시작 때 `Config.ini` 가 없을 때의 알림창 하나다.

## 설정 (Config.ini)

`[Features]` 로 기능을 켜고 끈다(0 이면 키가 등록되지 않고 설정 창 버튼도 비활성). `[Hotkeys]` 는 키, `[Settings]` 는 시간·칸 수. 설정 창에서 바꾼 값(`MenuTopOffset`, AFK 두 값, `OverlayEnabled`)은 재시작 없이 반영된다. 나머지는 손으로 고친 뒤 설정 창 "다시 불러오기". 이것은 스크립트를 다시 시작하는 것이라 돌던 기능은 멈추고 AFK 방지·오버레이는 시작 설정대로 다시 켜진다.

- BOM 없는 UTF-8, CRLF. BOM 이 있으면 첫 섹션을 못 읽는다(발견하면 매크로가 떼고 다시 저장).
- 값 줄 끝에 `;` 주석을 붙이면 주석까지 값으로 읽힌다. 주석은 줄을 따로 쓴다. 숫자가 아닌 값은 기본값으로 대체하고 `[config]` 로그를 남긴다.

꺼 둔 기능: `Teleport=0`(CEO/MC 재등록 텔레포트. 휴대폰 경로가 Quick Join → Random 으로 바뀌어 이름대로 동작하지 않고, 해체 뒤 눈 감고 누르는 키가 작업 로비에서 나간다), `CasinoFingerprint=0`.

## 로그

| 파일 | 내용 |
|---|---|
| `%TEMP%\gta-macro.log` | 공통. `[jobwarp]` `[botwarp]` `[session]` `[menu]` `[hotkey]` `[config]` `[stop]` `[panel]` `[screen]` `[error]` |
| `%TEMP%\gta-afk.log` | AFK 방지 |
| `%TEMP%\gta-claw.log` | 인형 뽑기 |
| `%TEMP%\gta-earn.log` | 수익 자동화 |

로그는 잘리지 않고 계속 쌓인다. 설정 창의 최근 로그에는 앞의 둘만 보인다.

## 따로 실행하는 스크립트

`Main.ahk` 에 포함되지 않는다. 키가 겹치니 매크로와 같이 켜지 않는다.

- `bunker.ahk`: F9 토글(전역 키). 커서를 좌표로 옮기고 Enter 를 보내는 것과 시간만으로 벙커 보급을 27분 25초마다 산다. 화면 확인 없음, `Config.ini` 안 읽음. F12 종료.
- `KeyHoldTest.ahk`: F10. M 다음 바로 Enter 를 보내 메뉴가 열리는지 보는 시험. `Config.ini` 를 읽는다(`KeyHoldTime`·`MenuControlDelay`). F12 종료.
- `LCtrlSpammer.ahk`: F10 토글. 100ms 마다 LCtrl. `Config.ini` 안 읽음. F12 종료.
- `tools\gta-perf-watch.ps1`: 작업 스케줄러가 10분마다 돌리는 성능 감시. 게임에 입력은 안 보내고, 게임이 꺼져 있을 때 `settings.xml` 의 그래픽 단계를 바꾼다. 기록은 `%USERPROFILE%\gta-perf\`.

`Lester-Ver2.0/` 과 `CodeSwine GTA5O - Private Public Lobby V1.0.1/` 은 별개 도구다.
