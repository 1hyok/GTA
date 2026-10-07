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

## CI와 배포 패키지

GitHub Actions의 [CI](.github/workflows/ci.yml)는 Windows에서 AHK 문법, PowerShell·Python 구문, 게임 입력 없는 회귀검사를 실행한다. 실제 게임 입력·화면 캡처·GPU 측정·작업 스케줄러 실행은 포함하지 않는다. 검사 도구와 고정한 실행기 버전은 [tools/ci](tools/ci/README.md), 구성요소와 현장 시험의 경계는 [도구 경계](docs/tool-boundaries.md)에 있다.

로컬에서도 Windows PowerShell 5.1에서 같은 검사를 실행한다. Python 3가 PATH에 있어야 하며, 다른 실행기를 쓰면 `run-checks.ps1 -PythonPath`로 지정한다. AutoHotkey는 임시 디렉터리에 압축만 풀어 기존 설치를 유지한다.

```powershell
$ciDirectory = Join-Path $env:TEMP ('gta-ci-' + [guid]::NewGuid().ToString('N'))
$ahk = & .\tools\ci\install-autohotkey.ps1 -Destination (Join-Path $ciDirectory 'ahk')
& .\tools\ci\run-checks.ps1 -AhkPath $ahk -OutputDirectory (Join-Path $ciDirectory 'checks')
& .\tools\ci\package-macro.ps1 -CheckResults (Join-Path $ciDirectory 'checks\results.json') -OutputDirectory (Join-Path $ciDirectory 'package')
```

패키지는 검사를 통과한 소스와 이미지, 캡처 런타임, 기능을 꺼 둔 `Config.example.ini`, 파일별 SHA-256을 담는다. 실제 `Config.ini`는 포함하지 않는다. 처음 설치할 때 예제를 `Config.ini`로 복사해 검토하고 필요한 기능을 켠다. 기존 설치를 갱신할 때는 설정을 보존한다. 패키지 생성은 매크로 재시작·실행 파일 설치·작업 스케줄러 갱신을 수행하지 않는다.

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
| F11 | 작텔(Alt+F4). `JobWarpQuickJoin=1` 이면 첫 ×2 는 퀵 조인 준비 | ×2 |
| Num/ | 인형 뽑기 1판 | 한 번 |
| Num* | 인형 뽑기 반복 | 토글 |
| Num0 | 스낵 먹기 | 한 번 |
| Num3 | 카요 페리코 48분 타이머 | 토글 |
| Num. | 도움말 (×2 설정 창) | 한 번 |
| End | 전체 멈춤 | 한 번 |
| Pause | 종료 | ×2, 전역 |

키가 비어 있는 기능: 걷기(`Walk`), CEO·MC 재등록 텔레포트(`TeleportMC1/2`, 기능도 꺼 둠), 카지노 지문 해킹(꺼 둠). 설정 창 버튼으로는 걷기를 실행할 수 있다. 남는 키는 ScrollLock.

## 작텔 (잡 워프)

둘 다 일시정지 지도에서 작업 블립을 골라 화면 아래에 "Start Job (Space)" 가 보이는 상태에서 누른다. 실내면 `P` 다음 `CapsLock` 으로 전체 지도. 도착지는 그 작업의 출발점이다. 두 작텔은 동시에 돌지 않는다(한쪽의 Enter 가 다른 쪽 확인창에 들어가는 것을 막는다).

즐겨찾기한 남의 작업은 지도에 블립이 안 뜬다(내가 만든 작업만 뜬다, 0926 실측). 그런 작업은 `P` → ONLINE → Jobs → Play Job → Bookmarked 에서 골라 CONFIRM 창이 뜬 상태에서 F10 두 번(매크로가 CONFIRM 을 보면 Space 를 건너뛰고 Enter 부터 한다). F11 은 화면을 보지 않고 Space 부터 보내므로 지도에서만 쓴다.

임무 진행 중에는 Jobs가 `Jobs are currently unavailable.`로 막혀 위 목록 경로를 쓸 수 없다. 0927 페이폰 히트에서 기존 웹 기록과 같은 결과를 확인했다([확인 화면](docs/evidence/2026-09-27-payphone-jobs-unavailable.png)).

### 준비 작업 전 Quick Join 적용 순서

아래는 2026-09-27 대조한 웹 원문의 절차다. 로컬에서 Quick Join 없이 시작한 페이폰 히트는 Jobs 접근 불가까지 확인됐으며, 그 시험은 완료됐다.

1. Online → Options에서 `Matchmaking=Closed`, `Filter Quick Join Content=User Created Only`로 설정하고 필요한 지도 작업 표식을 표시한다.
2. 보스 미등록 상태에서 전화 `Quick Join → Random → Alone → Yes`로 검색한다. `Looking For Job`을 확인한 뒤 CEO/MC 등록으로 검색을 끝내고 prep를 시작한다.
3. 이미 보스라면 검색 → prep 시작 → 전화 Quick Join에 다시 접근 → 폰 닫기로 검색을 취소하는 순서를 쓴다. 두 경로 중 현재 상태에 맞는 하나를 적용한다.
4. 지도 작업 블립에서 시작한 뒤 아래 F11 절차를 쓴다. 이 준비는 prep마다 필요하며, 필터는 검색을 늦출 뿐 매칭을 막지는 않는다.

출처는 [2024-12-30 작성자 절차](https://www.reddit.com/r/gtaglitches/comments/1hpoqk9/job_warping_during_missions_update/)와 기존 조사에서 인용한 [한국어 가이드의 작업 텔레포트 절](https://www.namu.moe/w/Grand%20Theft%20Auto%20Online/가이드)다. 원문의 2025-03-08 댓글은 PC 카지노 prep에서 Alt+F4 후 60초 대기로 성공했다고 보고한다(Legacy/Enhanced 구분·세부 버전 미기재). 일부 임무의 취소·운반물 유실도 원문에 명시돼 있어 모든 prep의 유지 보장은 아니다. 이 계정의 유지 성공 실측은 아래 페이폰 히트 두 건이며, 웹 보고와 구분한다. 조사 원자료와 과거 invalid 작업 경로는 dotfiles의 `claude/skills/gta-online-research/SKILL.md`에 정리했다.

### F11 두 번: Alt+F4 방식

#### 퀵 조인 준비까지 F11 로 (`JobWarpQuickJoin=1`)

F11 두 번을 두 단계로 쓴다. prep 을 시작하기 전(보스 해제가 되는 때)에 누른다.

1. F11 두 번: 매크로가 보스 해제 → 폰 Quick Join → Random → Alone → Yes → 곧바로 보스 등록(`JobWarpBossRole`, 기본 CEO)까지 하고 오버레이에 "작텔 준비됨" 을 띄운다. Looking For Job 은 기다리지 않는다. Yes 까지 눌렸으면 검색은 시작됐고, 바로 등록해야 검색이 작업 로비를 잡기 전에 끝난다.
2. 직접: prep 을 시작하고, 지도에서 작업 아이콘에 커서를 올려 "Start Job (Space)" 가 보이게 한다.
3. F11 두 번: 아래 Alt+F4 작텔. 성공하면 준비 상태가 풀린다. 준비 상태는 `JobWarpArmMaxMin`(30분)이 지나도 풀린다.

옛 재등록 텔레포트와 순서는 같지만 칸 수를 세지 않는다. 폰 앱·목록 줄·상호작용 메뉴 줄을 누르기 전마다 `Images\JobWarp\1920x1080\` 템플릿으로 선택된 줄을 확인하고, 안 보이면 더 누르지 않고 멈춘다(까닭은 툴팁과 `gta-macro.log` 의 `[jobwarp]` 줄). 템플릿 목록은 `Features/Teleport/QuickJoinPrep.ahk` 맨 위. 1920x1080 CEO 템플릿은 0927 에 떠서 `JobWarpQuickJoin=1` 로 켜 두었다. 0927 저택 안 실제 시험에서 F11 두 번 뒤 약 18초에 "작텔 준비됨" 이 됐고(Yes 뒤 폰은 저절로 닫히고, 약 3.5초 뒤 CEO 등록), 그 뒤 95초 동안 작업 로비로 끌려가지 않았다. 0928 에 실외(Vinewood 길가)에서도 뜨도록 템플릿을 실내·실외 원본을 겹쳐 다시 떴고(까닭은 `tools/build-jobwarp-templates.ps1` 머리말), 같은 자리 흐린 낮 실제 시험에서 F11 두 번 뒤 약 18초에 "작텔 준비됨" 이 됐다. MC(`JobWarpBossRole=MC` 나 MC 상태)와 다른 해상도는 템플릿이 없어 그 단계에서 멈추니, 그때는 템플릿을 더 뜨거나 `JobWarpQuickJoin=0` 으로 두면 F11 이 예전처럼 바로 작텔한다.

1920x1080 템플릿은 `tools/build-jobwarp-templates.ps1` 이 `docs/evidence/2026-09-27-jobwarp/` 의 실측 화면(코드가 찾는 영역 그대로 자른 무손실 PNG, 전체 화면은 같은 이름 JPG)에서 잘라 만들고, 같은 스크립트가 모든 원본에 코드와 같은 영역·옵션으로 대 보아 맞는 상태에서만 찾히는지 표로 확인한다(`-TestOnly` 는 시험만). 새로 뜰 때는 `tools/jobwarp-capture.ps1` 로 찍는다. 백그라운드로 띄워 두면 App menu 키(오른쪽 클릭 메뉴 키)를 한 번 눌러 켠 동안, 또는 ScrollLock 이 켜진 동안만 게임 모니터를 찍고 앞 장과 달라진 화면만 `%TEMP%\claude\jobwarp\` 에 남긴다(게임에 키를 보내지 않는다). 켜고 손으로 한 번 보스 해제 → Quick Join → Random → Alone → Yes → 보스 등록을 한 뒤 App menu 키를 다시 눌러 끄면, 남은 장에서 선택된 줄을 잘라 템플릿을 만든다.

```powershell
Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File tools\jobwarp-capture.ps1' -WindowStyle Hidden
```

사전 설정: Online → Options → Matchmaking = Closed, 상호작용 메뉴 → Preferences → Map Blip Options → Jobs 표시.

Space → CONFIRM Enter → 바로 Alt+F4 → 게임 종료 확인창에서 60초가 지나고 오른쪽 아래 No/Yes 안내가 보이면 Backspace(No). 작업 로딩이 뒤에서 튕기고 나면 작업 위치 프리모드에 떨어진다. 0926 페이폰 히트에서 목표·타이머를 유지한 채 두 번 성공했으나, 그때는 Quick Join으로 다른 작업 로비를 다녀온 뒤 지도에 작업 블립이 보이는 상태였다. 0927 Quick Join을 쓰지 않은 페이폰 히트에서는 지도 작업 블립이 사라졌다. 임무 중 항상 지도 작텔을 시작할 수 있다는 뜻은 아니다.

- No/Yes 안내는 20초쯤에 뜨지만 그때 누르면 작업 로비로 들어간다(0926 실측: 32초 실패, 60초 성공 2회). `JobWarpMinWaitMs=60000` 을 줄이지 않는다.
- 90초까지 안내를 못 찾거나 대기 중 End 를 누르면 매크로는 Backspace 를 안 보낸다. 종료 확인창은 직접 Backspace 로 닫는다. Enter(Yes)는 게임이 꺼진다.
- 로비로 들어갔으면 Backspace → Yes 로 나오면 원래 자리.
- 오버레이가 "작텔 대기 N/60초" 를 보여 준다. 안내 감지 자리가 오른쪽 아래 구석이라 오버레이를 거기에 두지 않는다.

### F10 두 번: 스팀 봇 방식

작업 시작 → 로딩 중 스팀 그룹 채팅 "CCYXJ差传" 의 봇(`BotWarpBotRow` 1: 差传CCYXJ01, 2: 差传CCYXJ03)에 Join Game → "join a different session" Enter → (조준 모드가 다르면 경고 Enter) → "incompatible assets" Enter → 약 20초 뒤 출발점. 60초 대기가 없어 F11 보다 빠르다.

이 방식의 로컬 성공은 새 세션의 프리모드 도착이다. 진행 중인 prep가 유지됐다는 실측은 없으며, [2026년 PC Enhanced 봇 가이드](https://www.reddit.com/r/gtaglitches/comments/1qaewlg/pc_enhanced_gtav_job_teleport_guide_3_easy/)도 prep 유지 여부는 설명하지 않는다. 따라서 Steam 봇의 prep 유지·소실은 미확정이며, Alt+F4의 임무 유지 결과를 봇 방식에 적용하지 않는다.

- 준비: 스팀 그룹 채팅 창을 열어 둔다(매크로가 노트북 화면 오른쪽 위로 옮긴다. 필터 칸은 좌표로, 봇 줄과 Join Game 은 `Images\BotWarp\steam\` 참조 이미지로 찾은 자리를 누른다). 노트북 화면 배율 175%, 게임 16:9. `join_game.png` 가 없으면 시작하지 않는다. 봇이 게임 중(멤버 목록에서 초록 글자)이어야 한다.
- 채팅 창이 없으면 `open_in_steam.png`·`join_group_chat.png` 가 있을 때만 초대 링크로 자동으로 연다(친구 목록 창이 없으면 매크로가 먼저 띄운다. 0926 실측: 친구 목록이 한 번도 안 뜬 상태에서는 Open in Steam 이 무반응). 두 장이 없으면 채팅 창을 직접 열어 두라고 알리고 멈춘다.
- 메뉴 매크로·인형 뽑기·수익 자동화·이동·자동 클릭 토글이 켜져 있으면 시작하지 않는다.
- 도착한 세션은 새 세션이다(초대 전용이 아니다). 거기서 다시 Start Job 을 누르면 "Currently unavailable" 이 뜨니 매크로가 Backspace 로 닫고 멈춘다. F5 두 번으로 초대 전용에 옮긴 뒤 다시 한다. 세션을 옮긴 직후에는 지도에 블립이 한동안 없다. 그때는 위의 Play Job 경로.
- 조준 모드 경고를 거절(Backspace)하는 옛 방식은 게임이 13분 넘게 멈춘다(0926 실측). 수락하면 조준 모드가 봇 쪽으로 바뀐다(0926 실측: Assisted Aim - Partial). 초대 전용 세션 위주면 되돌릴 필요가 거의 없고, 되돌리는 절차는 조사 스킬에 있다.
- Join Game 뒤에 키보드를 만지면 사용자가 넘겨받은 것으로 보고 멈춘다. Join Game 뒤 20초 안에 참가 알림이 안 뜨면 멈추는데 작업은 로딩 중이니 봇에 직접 Join Game 하거나 작업을 나간다. incompatible 알림 없이 게임 화면으로 돌아오면 봇 세션에 들어갔을 수 있으니 위치를 확인한다.
- 중단은 End(스팀 창이 앞이어도 먹는다). 스팀 클릭·검색어 입력 전 대기 중에 End를 누르거나 스팀이 포커스를 잃으면 남은 입력 없이 멈춘다. Join Game 클릭 직후 대기에서 중단해도 GTA를 앞으로 가져오는 다음 단계로 넘어가지 않는다. CONFIRM 대기 중에 멈췄으면 확인창을 직접 Backspace 로 닫는다.
- KeyHoldTest.ahk·LCtrlSpammer.ahk 도 F10 을 쓰니 같이 켜지 않는다.

## 초대 전용 세션 (F5 두 번)

`P` → ONLINE → Find New Session → Invite Only Session → 확인창 OK. 줄 수를 세지 않고, ONLINE 목록에 들어간 뒤부터는 오른쪽 칸 제목과 확인창 문구를 템플릿(`Images\Session\1920x1080\`)으로 확인한 뒤에만 Enter 를 보낸다. 게임을 켠 방식에 따라 ONLINE 목록 길이가 달라 줄 높이로 세면 Quit to Story Mode 에서 Enter 가 나갔다(0926). 제목을 못 찾거나 마지막 확인창 문구가 3초 안에 "quit this session" 으로 확인되지 않으면 추가 입력 없이 멈춘다. 템플릿이 1920x1080 것뿐이라 다른 해상도는 안 된다.

## AFK 방지 (F4)

실제 키보드·마우스 입력이 45초 없을 때만 200초(±20초)마다 동작한다. 일반 모드는 W/S를 150ms씩 번갈아 누른다. MCT 전용 모드는 사업장 목록과 앉은 안내 사이를 왕복한다. MCT 앞이거나 전화·앱·메뉴가 없는 게임 HUD를 확인하면 M으로 상호작용 메뉴를 열었다 닫는다. 시점이 MCT 안내 밖으로 바뀌어도 카메라를 되돌리지 않고 보호한다. 중간 화면과 시작 화면으로의 복귀를 각각 확인하며 이동·시점 회전·사업장 선택은 하지 않는다. 전화·앱·미확인 화면에는 입력하지 않고 경고한다. 로그의 화면 왕복 확인과 실제 장시간 접속 유지 결과는 구분한다. 인형 반복·이동 토글·자동 클릭·작텔·수익 작업 중에는 쉬고, GUI·시험 하네스가 입력 잠금을 가진 동안에는 전면화도 하지 않는다. End 는 AFK 방지를 끄지 않는다.

다른 창이 GTA 포커스를 가져가 있으면 입력이 없는 시간을 두 가지로 재서 가른다. 하나는 물리 입력(`A_TimeIdlePhysical`, 키보드·마우스 훅)이고, 다른 하나는 크롬 원격 데스크톱·computer-use·코덱스처럼 다른 프로그램이 주입한 입력까지 세는 전체 입력(`A_TimeIdle`, 이 매크로 자신의 입력은 뺀다)이다.

| 입력 없음 | 동작 |
|---|---|
| 둘 중 하나라도 `AFKRefocusIdleSec`(기본 300초) 미만 | 누가 자리에 있거나 다른 창을 쓰는 중이라고 보고 창을 뺏지 않는다. `skip: GTA 포커스 없음, 전면화하지 않음 (idle=Ns, 주입 포함 idle=Ms, 기준 300s)` 을 남기고 30초 뒤 다시 본다 |
| 둘 다 그 이상 | GTA 를 앞으로 가져오고(최소화면 복원) `AFKRefocusSettleMs`(800ms) 기다린 뒤, 위의 입력 조건을 다시 보고 누른다 |

- 0928 07:45 예약 작업이 띄운 크롬이 GTA 포커스를 가져간 뒤 입력이 끊겨 15분 만에(07:59) 방치 킥을 당한 뒤 넣은 동작이다. 전에는 다른 창이 앞이면 건너뛰기만 했다.
- 주입 입력까지 보는 까닭: 원격 데스크톱으로 쓰는 사람과 에이전트의 입력은 물리 입력에 안 잡힌다. 그때 GTA 를 가져오면 그 클릭은 사격으로, `T` 뒤 글자와 Enter 는 공개 채팅으로 게임에 들어간다. 대가로 에이전트나 예약 작업이 OS 입력으로 15분 넘게 쉬지 않고 다른 창을 조작하면 방치 킥을 못 막는다. 관리자 권한 창(작업 관리자 등)에서 치는 입력도 Main 의 훅은 못 보지만 전체 입력에는 잡혀 창을 뺏지 않는다.
- Main 을 켠 직후에는 훅이 물리 입력 시간을 0 부터 다시 센다. 훅을 깐 뒤 물리 입력을 한 번도 못 봤으면 전체 입력 시간으로 메우므로, 오래 비운 자리에서 다시 켜도 5분을 기다리지 않는다.
- 가져오기에 실패하거나 가져온 직후 포커스를 다시 잃으면 30초, 60초 뒤 다시 해 본다. 같은 앞 창과 유휴 구간에서 세 번 실패하면 추가 전면화를 멈추고 `refocus blocked` 로그와 경고를 남긴다. 사용자가 입력하거나 앞 창이 바뀌면 새 구간으로 판단한다. GTA가 다시 앞에 오면 AFK 입력을 재개한다. 기다리는 사이 사람이 돌아온 것은 실패로 세지 않는다.
- Windows 알림(`ShellExperienceHost.exe / New notification`)이 전면화를 막으면 `Move this notification to Notification Center`라는 UI Automation 버튼이 정확히 하나일 때만 한 번 눌러 알림 센터로 옮기고 복귀를 재시도한다. 승인·거절·알림 본문은 누르지 않는다. 창 신원과 마지막 입력 시점이 달라지거나 버튼이 모호하면 취소한다. 검사 프로세스는 최대 8초이며, 최근 입력과 다른 매크로 동작을 기다리는 동안에도 확인한다. 알림 처리 성공 뒤에도 GTA 포커스와 실제 AFK 입력 성공을 각각 확인해 로그에 남긴다.
- 앞 창에 직접 보내는 키는 앞 창이 입력 도구(`TextInputHost.exe`)거나 앞 창이 없을 때의 Alt 한 번뿐이다(0926 대응과 같은 조건, 로그에 `Alt 보조`). 다만 AHK 의 `WinActivate` 는 실패하면 스스로 Alt 를 두 번 누를 수 있다(AHK 소스 기준, 실측 안 함). 이런 Alt 는 전체 입력 시간에서 뺀다.
- 가져온 뒤에는 GTA 가 앞이므로 수익 자동화도 차례가 된 작업을 시작한다.
- `AFKRefocusIdleSec=0` 이면 가져오지 않고 전처럼 건너뛰기만 한다. `AFKUserIdleSec` 보다 작게 잡아도 `AFKUserIdleSec` 이 먼저 걸린다. 이 값은 Main 만 읽는다. `tools/earn-test/afk-guard.ahk` 는 `Config.ini` 를 안 읽고 자기 기준(아래)으로 가져오므로 0 으로 끌 수 없다.
- 로그 예: `refocus ok idle=312s 주입 포함 idle=312s 앞 창=chrome.exe / about:blank - Google Chrome`, `refocus 실패: 2초 안에 앞으로 오지 않음 idle=640s 앞 창=… (다음 시도 30초 뒤, 같은 까닭은 다시 적지 않음)`.
- 메뉴가 열린 채 자리를 비우면 W/S 가 Up/Down 으로 먹어 선택 줄이 밀린다(0926 실측: 지도 범례가 8칸 밀림). 메뉴는 닫아 두거나 F4 로 끈다.
- 입력 없음 시간과 간격은 설정 창에서 바꾼다(5~600초, 30~600초). 전면화 기준 등 나머지 값은 `Config.ini`. 로그는 `%TEMP%\gta-afk.log`.

## 판매 차례 알림 (Num1)

디코 오버레이(DiscordChatHUD) 채팅 아래 판매 대기자 맨 위가 `Config.ini` 의 `SaleAlertName` 이 되면 삐 소리 세 번과 툴팁으로 한 번 알리고 스스로 꺼진다. 평소에는 꺼져 있고 Num1 로 켜고 끈다. 그 자리를 10초마다 한국어 OCR 로 읽는다.

## 상호작용 메뉴 매크로 (Num0 스낵)

M 을 열고 `Config.ini` 의 칸 수대로 Down·Enter 를 보낸다(스낵만 끝에 M 으로 다시 닫는다). 화면 확인이 없어 커서는 맨 위(Quick GPS) 기준이고, 게임이 마지막 커서 위치를 기억하므로 다른 항목에 두고 닫았으면 한 번 빗나간다. 칸 수 기본값은 공개 문서·매크로에서 가져온 것이라 안 맞으면 `[Settings]` 의 `Snack*` 을 고친다. 한 번에 하나만 돌고, 다른 것이 진행 중이면 툴팁만 뜬다.

내 부동산(아케이드 등) 안에서는 맨 위에 "… Management" 줄이 하나 더 붙는다. 설정 창의 "부동산 안/밖" 라디오(`MenuTopOffset`)를 맞춘다.

CEO·MC 는 평소 해제 상태로 둔다. 켜 두면 사업장이 습격 대상이 된다. 시험으로 등록했으면 그 자리에서 Retire·Disband.

## 이동·클릭 (F6 / F7 / F8)

F6 은 Shift+W, F8 은 W 를 누른 채 3초마다 LCtrl(벨럼 이륙 유지). 켜져 있는 동안 AFK 방지는 쉰다. 스크립트가 이동 키를 누른 채 끝나면 캐릭터가 계속 걸어가므로 종료·전체 멈춤·오류 때 매크로가 누른 키를 뗀다.

F7 자동 클릭은 커서가 게임 화면 안에 있을 때만 왼쪽 클릭을 반복한다(클릭마다 `ClickHoldTime` 50ms 누르고 `ClickInterval` 1ms 쉬므로 약 50ms 에 한 번). 문자·숫자·F키·Enter·방향키 같은 다른 키를 누르거나 커서가 게임 밖으로 나가면 멈춘다(0926: 커서가 설정 창 위에 남아 설정 창 버튼을 연타한 사고). 첫 클릭이 거절되거나 클릭 대기 중 End로 멈춰도 타이머를 다시 켜지 않는다. 설정 창 버튼으로 켜면 커서를 게임 가운데로 옮겨 준다.

## 인형 뽑기 (Num/ 한 판, Num* 반복)

아케이드 기계 앞 "Press E to play" 상태에서 누른다. E → W 5초 → D 5초 → Enter 순서이고 단계마다 왼쪽 위 안내 문구 이미지(`Images\Claw\`)를 확인한 뒤에야 다음 키를 보낸다. 안내가 안 보이면 아무 키도 안 보내고 멈춘다(캐릭터가 걸어가 버리는 사고 방지). 반복을 끄면 진행 중인 판은 다음 키 전에 멈추고, 중간에 멈춘 판은 다음 시작 때 먼저 내려서 정리한다. 이 복구 과정도 내리기 안내를 확인하지 못하거나 중단·포커스 이탈을 감지하면 Enter를 보내지 않는다. 해상도별 폴더(`Images\Claw\<가로>x<세로>\`)가 있어야 하고 2560x1600 만 루트에 있다. 이동 시간 값(`ClawForwardMs`, `ClawRightMs`)은 1920x1080, RT 켬, DLSS 품질/FG 2X, 120fps 에서 잰 것이다. 로그는 `%TEMP%\gta-claw.log`, 진단 상태는 `%TEMP%\claw-status.ini`.

## 수익 자동화 (F9 두 번)

저택 MCT를 거점으로 벙커 보급·DJ 교체·나이트클럽 창고 직원을 관리한다. GTA+의 Vinewood Club 앱으로 나이트클럽 금고를 회수하고 보석 집행 요원·스페셜 패키지 창고 직원을 파견한다. 현재 기본 설정은 `EarnMCTOnly=1`과 `EarnBunker`, `EarnDJ`, `EarnSafe`, `EarnWarehouse`, `EarnBailAgents`, `EarnCargoStaff`가 모두 1이다. Main을 실행한 뒤 MCT 사업장 목록이나 확인 가능한 MCT 앞 대기 위치에서 F9를 두 번 누른다. 테러바이트 MCT(터치스크린 앞)도 지원한다. 테러바이트는 선 채 Space로 열고 닫으면 바로 접속 안내로 돌아오므로 앉고 일어서는 단계가 없어 거점으로 더 안정적이다. AFK 방지도 이 안내 화면에서 M 메뉴 왕복으로 입력한다. 지원 화면은 1920×1080 영어 UI이며 한글 UI는 지원하지 않는다. 적용 정책과 계산은 [수익 자동화 정책](docs/earner-policy.md), 실제 검증 범위는 [인계 기록](docs/earner-handoff.md)을 따른다.

스케줄러는 1초마다 때가 된 작업을 본다. 벙커·DJ·창고 직원은 MCT 작업이라 그 시점에 차례가 된 것들을 MCT를 한 번 열어 묶어 처리하고 한 번만 닫는다. 진행 중 새로 차례가 된 작업은 다음 회차다. 금고 회수와 앱 직원 파견은 그다음 Vinewood 앱에서 따로 한다. F9를 놓고 키보드·마우스 입력이 2초 동안 없으면 다음 확인에서 시작한다(보통 2~3초). 대기 중에는 오버레이에 입력 안정 또는 GTA 포커스 대기 이유를 표시하며, 진행 중 사용자 입력·포커스 이탈·End가 감지되면 중단한다. CEO는 상호작용 메뉴를 먼저 열어 등록하지 않는다. MCT에서 사업장을 고를 때 뜨는 `Press L Ctrl to register as a CEO` 안내를 확인한 뒤 그 자리에서 등록하고, 묶음이 끝나 MCT를 닫은 뒤 한 번 해제한다. 이 안내는 커서를 사업장 버튼에서 치우면 사라지므로 안내를 읽는 동안에는 커서를 두고, 사업장에 들어간 뒤에 치운다. 다음 동작은 화면 템플릿과 영어 OCR로 확인하며, 판독 실패나 예상과 다른 확인창에서는 자동화를 멈춘다. 이유는 `%TEMP%\gta-earn.log`, 오버레이, 설정 창에 남긴다. F9 운용에는 부동산 이동·세션 전환이 필요하지 않으며 현장 파견은 `EarnDispatch=0`이다.

벙커 기본값 `EarnBunkerIntervalSec=6720`은 기본 생산 속도에서 112분, 보급 네 칸 소모를 뜻한다. 보급 20%와 가격 $60,000을 함께 확인한 뒤에만 구매한다. 남은 한 칸(약 28분 생산분)으로 약 10분 배송 동안에도 생산이 이어지고, 도착한 보급은 가득 채워지므로 배송 뒤에는 새 보급량부터 다시 계산한다. `1680`초의 1~5배로 28·56·84·112·140분에 해당하는 소모량을 선택할 수 있으며 8400(빈 보급에서 $75,000 주문)은 배송 중 생산 공백이 있다. 중간에 확인해 보급이 75%처럼 경계를 지나쳤으면 다음 20% 소모 경계까지 기다리고, 실제 가격이 계획한 칸 수 × $15,000과 맞는지도 확인한다. 최대 5분 간격의 상태 관측은 구매 주기가 아니다. 보급은 1%에 약 84초씩 줄어 경계 값이 머무는 시간이 짧으므로, 예상 경계 3분 전에 재관측을 예약하고 경계가 4분 안이면 MCT를 닫지 않은 채 최대 4분 동안 화면을 새로 읽는다. 그 4분을 넘긴 판독으로는 결제하지 않는다. 재고가 가득하거나 배송 중이면 추가 구매하지 않는다.

DJ 기본 목표는 95%다. 직원 업그레이드·일반 수입 배수에서 정상 주기는 100%와 95%의 $50,000 지급을 받은 뒤 90%에서 기존 DJ를 $10,000에 재고용하는 방식이다. 95%에서 100%를 만들기 위한 교체는 하지 않는다. 96분당 $100,000 수입에서 재고용 비용 $10,000을 뺀 $90,000이므로 매 지급마다 100%로 복구하는 것보다 순수입이 높다. 5분마다 Nightclub의 Home 화면을 새로 열어 인기도를 확인하고 95% 미만일 때만 Solomun/Tale Of Us를 재고용한다. 교체 뒤에는 Home → MCT → Home으로 한 번 재진입하고 최대 15초 동안 읽기만 반복해 증가를 확인한다. 갱신이 늦다는 이유로 재결제하지 않는다. DJ 지출 판단에는 이 Home 막대만 사용한다.

금고는 Vinewood 앱 사업장 목록의 모든 금고(나이트클럽·아케이드·에이전시·구조물 처리장·보석 사무소·의류 공장)를 한 줄씩 읽는다. 쓰지 않는 세차장은 건너뛴다(`EarnSafeIgnored()`). 다음 입금(게임 하루 48분마다의 최대 입금)이 그 금고 한도를 넘길 금액이면 회수한다(예: 나이트클럽은 한도 $250,000·하루 $50,000 이라 $200,000 초과). 꽉 찰 때까지 기다리면 넘치는 입금이 버려진다. 행을 선택한 뒤 하단 `Claim $X from your <사업장> safe.` 문구의 금액을 읽고, 수거 직전에 같은 선택·금액을 다시 확인하고, 수거 후 `Your <사업장> safe is empty.`를 확인한다. 목록을 다 돈 뒤 앱 종료와 MCT 앞 대기 상태를 확인한다. 다음 확인은 금고마다 남은 입금 횟수로 구해 가장 이른 것으로 정한다. 한도·하루 입금 표는 `EarnVinewood.ahk`의 `EarnSafeLimits()`.

나이트클럽 창고 직원은 10분마다 관측해 가득 찬 품목에 배정된 직원만 해금된 미포화·미배정 품목으로 옮긴다. 목적지 우선순위는 남미 수입품, 의약품, 현금, 화물, 스포츠 용품, 유기농, 인쇄 순이며 저장 용량은 실제 화면에서 읽는다. 현재 화면 판독은 직원 5명을 모두 고용하고 각각 품목에 배정한 상태를 전제로 한다. 미배정 직원이나 담당 품목을 알 수 없는 직원이 있으면 자동 배정·고용을 시도하지 않고 중단한다. 품목을 누르면 뜨는 `Assign Technician` 확인창은 문구를 읽은 뒤 Confirm을 한 번 누른다. 가득 찬 품목이 셋 이상이면 오버레이에 `나이트클럽 창고 만재 N개: 판매 필요`를 띄우니 Sell Goods에서 직접 판매한다.

앱 직원은 파견한 대상이 돌아올 49분 뒤(게임 하루 48분 + 1분)에 다시 확인하고, Main 재시작 뒤처럼 언제 보냈는지 모르는 작업 중 대상만 `EarnStaffIntervalMin=5`분마다 확인한다. 금고는 남은 입금 횟수로, 창고 직원은 실측한 품목별 생산 속도로 다음 확인을 미룬다. `Manage Staff Members`의 Bail Office에서는 준비된 Agent 1·2만 파견하고, Warehouse에서는 소유한 1~5개 창고를 순회한다. 스페셜 패키지는 선택 행의 이름·$7,500·준비 문구를 다시 확인한 뒤 창고당 한 번만 주문한다. 작업 중·만재는 건너뛰며 요청 후 최대 60초 동안 작업 중 문구를 기다린다. 5분 관측이나 평시 약 48분 복귀 시간이 무조건 재주문하는 주기는 아니다. 이 기능은 Bail Office 금고 수거나 Hangar 파견을 포함하지 않는다.

2026-09-27에 기존 DJ 재고용과 배송 중 중복 결제 방지를 실측했다. 2026-10-03에는 벙커 재고 36%·보급 22%에서 구매를 건너뛰고 다음 경계를 예약한 뒤 CEO 해제까지 성공했다. DJ는 Home 91%에서 한 번 재고용한 직후 값이 그대로여서 시험이 중단됐지만, 추가 결제 없이 Home을 다시 열어 100%를 확인했다. 후속 DJ 작업은 Home 100%에서 무구매 후 CEO 해제까지, 나이트클럽 창고 작업은 이동 대상이 없어 배정을 유지한 뒤 CEO 해제까지 성공했다. 금고 작업도 Nightclub $150,000을 읽고 수거 없이 앱을 닫아 복귀했다.

10월 3일 09:50에는 빈 보급의 $75,000 구매와 배송 중 안내까지 확인했다. 구매 버튼·확인창의 글자 가장자리 차이로 판독이 실패하던 템플릿과, 창이 닫힌 뒤 배경이 밝아지기 전에 복귀를 시도하던 처리를 고쳤다. 후속 벙커 작업은 배송 중 안내를 읽어 중복 결제하지 않고 MCT 종료·CEO 해제까지 성공했다. MCT 접근 안내와 복귀 화면도 정해진 기한 안에서 나타나는 즉시 진행하며, 화면을 확인하지 못하면 추가 입력을 멈춘다.

앱 직원 모듈의 실제 전체 실행은 요원 1 파견, 작업 중인 요원 2 건너뛰기, 창고 4곳의 각 $7,500 조달과 작업 중 확인, 만재인 Foreclosed Garage 건너뛰기, 앱 종료와 MCT 앞 복귀까지 성공했다. 직원 모듈의 입력 없는 검사는 438건, 실제 저장 화면 8장의 OCR을 포함하면 462건을 통과했다. 남은 실전 검증은 실제 $250,000 앱 수거, 나이트클럽 직원 재배정과 장시간 연속 운용이다. 전체 검사는 `tools/ci/run-checks.ps1`의 `results.json`으로 확인한다. 기존 DJ·벙커 정책에는 실제 ChatGPT Pro 5/5 검토를 반영했으며 새 앱 직원 범위의 외부 검토는 브라우저 연결 실패로 미완료다. 코드 변경 자체가 Main 실행이나 F9 토글을 대신하지 않는다.

앱 첫 화면의 `Manage Staff Members`는 맨 위 기본 선택에서 `Up` 한 번으로 감아 이동한다. 현재 선택 줄 OCR이 빠져도 이 진입만은 `Up`을 기본 방향으로 사용하고, 이동 뒤 실제 선택 줄을 다시 확인한 다음 Enter를 보낸다. 직원 관리의 Hangar·Warehouse·Bail Office 목록이 확인되면 이동 방향은 실제 3개 행의 선택 막대 위치로 계산한다. 회색 행이 OCR에서 빠져도 목록을 2줄로 줄여 계산하지 않는다. 목표에 도착했는지는 실제로 읽힌 목표 이름과 선택 막대를 다시 확인한다. 목표 이름이 계속 읽히지 않으면 제한된 탐색 뒤 중단하고 Enter를 보내지 않는다.

반복 예약과 오류 처리의 입력 없는 검사는 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earner.ps1`로 실행한다. 실제 스케줄러 함수를 사용하지만 게임·창·키 입력은 대체하므로 장시간 게임 운용을 검증하는 시험은 아니다.

이전 금고 방문·아케이드 복귀 경로의 실측과 실패 기록은 [9월 인계 기록](docs/earner-handoff.md)에 보존한다. 이 이동 경로는 현재 F9 금고 작업의 완료 조건에서 제외했다. 남아 있는 길찾기·블립 검사는 `tools/earn-test/test-earnnav.ps1`, `tools/earn-test/test-earnblip.ps1`이다.

시험은 `tools/earn-test/earntest.ahk`로 Main 없이 실행한다. 하네스 자체는 Main과 AFK를 켜지 않는다. 하네스는 8초 물리 입력 유휴를 최대 2분 기다리고, 시험 도중 사용자 입력·포커스 이탈·End가 감지되면 중단한다. 실행 제한은 25분이고 오류는 창 대신 로그와 표준 출력에 남긴다. `Status`·`Idle`·`PhoneStatus`는 전면화나 입력 없이 상태를 읽는다. `PhoneStatus`는 전화 테두리와 통화 종료 아이콘의 감지 결과를 구분한다. 시험 하네스의 세션 전환에는 추가 화면 검사(`SessionGuard.ahk`)가 적용되므로 필요한 메뉴 템플릿이 없으면 해당 키 전에 멈춘다.

MCT에서 일어선 뒤 게임 전화가 연결되면 통화 종료 아이콘을 확인하고 Backspace로 끊은 뒤 복귀한다. 10월 7일에는 Steam 녹화에서 맞던 아이콘이 실제 데스크톱에서는 허용 오차 40을 넘어 통화를 놓쳤다. 해당 아이콘만 허용 오차를 60으로 보정했다. 실제 화면·녹화·전화 없는 화면을 비교하는 `test-phone-call-template.ps1`을 CI에 포함한다.

작업 중 AFK 보호는 `tools/earn-test/afk-guard.ahk`를 별도 실행한다. Main과 수익 스케줄러를 실행하지 않고, 시험 종료·실패 뒤에도 남는다. 실제 사용자 입력이 45초 없으면 GTA를 앞으로 가져와 게임 HUD를 확인하고(원격 데스크톱·에이전트의 주입 입력을 포함한 전체 입력이 45초 안에 있었으면 가져오지 않는다) 약 120초마다 상호작용 메뉴를 열었다 닫는다. MCT 사업장 목록이나 앉은 안내에서는 확인된 화면을 닫았다 열거나 열었다 닫아 원래 상태로 돌아온다. 전화·앱·메뉴가 없는 HUD를 확인하며 걷거나 시점을 움직이지 않는다. 장시간 접속 유지 효과는 실제 세션에서 별도로 확인한다. 다른 메뉴나 로딩 화면에서는 입력하지 않는다. `earntest`와는 공통 입력 잠금(`Local\GtaMacroInput`)을 쓰며, `earntest`·GUI 수신기·Main 창이 살아 있는 동안 대기한다. GTA가 앞일 때 F4로 켜고 끈다. 상태는 `%TEMP%\gta-afk-guard-state.txt`, 실제 입력 기록은 `%TEMP%\gta-afk.log`다.

```powershell
Start-Process -FilePath "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" -ArgumentList '/ErrorStdOut tools\earn-test\afk-guard.ahk' -WindowStyle Hidden
```

GUI 작업에서 확인한 구간을 직접 조작할 때는 `tools/earn-test/gui-input.ahk`와 `gui-input.ps1`을 쓴다. GTA가 이미 앞에 있어야 하며 Main·AFK를 켜거나 창을 전면화하지 않는다. 처음 시작할 때만 실제 사용자 입력 유휴 8초를 확보한다(최대 60초 대기). 이후 자기 입력 때문에 유휴 시간을 다시 기다리지 않는다. 실제 사용자 입력·GTA 포커스 이탈·End를 감지하면 보유 키를 놓고 종료하며, 전체 실행 제한은 25분이다. 다른 작업·매크로·Computer Use와의 조작권 직렬화는 계속 필요하다.

아래 PowerShell은 현재 디렉터리가 이 저장소 루트이고 AutoHotkey v2가 현재 사용자의 기본 위치에 설치됐다고 가정한다. 실행마다 새 빈 TEMP 디렉터리와 토큰을 만든다.

```powershell
$gtaRepo = (Get-Location).Path
$guiToken = [Guid]::NewGuid().ToString('N')
$guiSession = Join-Path $env:TEMP ('gta-gui-' + $guiToken)
New-Item -ItemType Directory -Path $guiSession | Out-Null
$guiAhk = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
$guiArgs = '/ErrorStdOut "' + (Join-Path $gtaRepo 'tools\earn-test\gui-input.ahk') + '" "' + $guiSession + '" "' + $guiToken + '"'
Start-Process -FilePath $guiAhk -ArgumentList $guiArgs -WindowStyle Hidden -PassThru
```

`Get-Content (Join-Path $guiSession 'state.txt')`의 상태가 `ready`인 것을 확인한 뒤 명령 하나를 보내고 `result-N.txt`를 확인한다. 입력을 묶는 범위와 화면 확인 시점은 스킬 정본 `~/dotfiles/codex/skills/gta-macro-ops/SKILL.md`의 메뉴·이동 규칙을 따른다. 확인한 시작 상태에서 고정된 탐색 구간을 한 호출로 보내고, 의미 있는 분기·실행 확정·구간 결과에서 캡처를 확인한다. 전송 성공은 화면 전환의 증거가 아니다. 아래 예시는 각각 별도로 실행하며 `hold`는 화면에서 확인한 장애물 없는 직선 구간에서 W/A/S/D 중 한 키를 최대 15,000ms 유지한다.

```powershell
& .\tools\earn-test\gui-input.ps1 -SessionDir $guiSession -Action tap -Key Backspace
```

```powershell
& .\tools\earn-test\gui-input.ps1 -SessionDir $guiSession -Action hold -Key W -HoldMs 6000
```

`navigate`는 `Up`·`Down`·`Left`·`Right`·`PgUp`·`PgDn` 1~20개를 한 번에 보낸다. `-InterKeyMs`는 150~500ms이며 기본값은 200ms다. Enter·Backspace 등 실행 확정·뒤로 키는 넣을 수 없다. 결과와 `navigate-N.log`에 완료 키 수와 `elapsed_ms`가 남는다.

프리모드에서 전화는 `tap -Key Up` 한 번으로 연다. Up을 빠르게 두 번 누르면 Snapmatic 카메라가 열리므로, 전화 열기 다음 탐색은 `Right` → `Up` 순서를 쓴다. 먼저 전화 홈의 `Job List`가 선택된 상태를 확인한 뒤 아래 구간으로 Contacts에 이동하고, 선택 결과를 확인한 뒤 별도 `tap -Key Enter`로 목록을 연다. 2026-09-27 수정 경로의 성공 실측은 이미 열린 Job List 홈에서 시작했으며, 프리모드부터 수정한 전체 경로는 아직 재검증하지 않았다.

```powershell
& .\tools\earn-test\gui-input.ps1 -SessionDir $guiSession -Action navigate -Keys @('Right','Up') -InterKeyMs 200
```

다음 연락처 구간은 Contacts 목록 최상단 `DE-SSANTA`가 선택된 화면에서 쓴다. 실행 뒤 `Franklin`이 선택된 화면이 종료 조건이다. 다른 이름이 선택돼 있으면 Enter를 이어 보내지 않고 현재 상태를 다시 확인한다.

```powershell
& .\tools\earn-test\gui-input.ps1 -SessionDir $guiSession -Action navigate -Keys @('Right','Right','Down') -InterKeyMs 200
```

Franklin 선택을 확인한 뒤 별도 `tap -Key Enter`로 전화를 건다. 연결 완료는 화면의 `Franklin CONNECTED`와 서비스 메뉴로 확인한다. 2026-09-27 실측에서 위 연락처 탐색 3키는 750ms였고, Enter·5초 대기·연결 화면 캡처는 별도로 5,843ms였다. 임무 요청의 접수·진행 여부는 그 다음 화면 증거로 판정한다([실측 기록](docs/earner-handoff.md)).

지도 확대·축소는 화면의 키 안내를 확인한 뒤 `-Action tap -Key PgUp` 또는 `PgDn`을 쓴다. `click`은 현재 캡처에서 읽은 물리 화면 좌표를 지정한다. GTA 클라이언트 영역 밖이면 거부하고, 영역 안에서는 커서 위치를 확인한 뒤 좌클릭을 100ms 누른다. 축소 캡처의 좌표를 그대로 넣지 않는다. DPI 처리를 포함한 실제 좌표 일치는 현장 화면으로 검증하며, 선택·실행 결과는 위 구간 기준에 맞춰 확인한다. 다음 좌표는 형식 예시다.

```powershell
& .\tools\earn-test\gui-input.ps1 -SessionDir $guiSession -Action click -X 960 -Y 540
```

범례 스크롤은 현재 커서가 범례 위에 있는 것을 확인한 뒤 `wheel`을 쓴다. 커서를 옮기지 않으며 매 틱마다 게임 포커스·사용자 입력·GTA 영역 안 커서 위치를 확인한다. `-Ticks`는 -5~5 중 0을 제외하며 양수는 위, 음수는 아래다. 탐색 구간 결과에서 캡처로 범례를 확인한다.

```powershell
& .\tools\earn-test\gui-input.ps1 -SessionDir $guiSession -Action wheel -Ticks -3
```

도구는 다음 행동을 자동으로 선택하거나 반복하지 않는다. 마지막 명령이 끝나면 `stop`으로 수신기를 종료한다. 진행 중인 이동의 즉시 중단은 End를 쓴다.

```powershell
& .\tools\earn-test\gui-input.ps1 -SessionDir $guiSession -Action stop
```

## 전체 멈춤 (End) · 종료 (Pause 두 번)

End 는 도는 것을 전부 멈추고(카요 타이머 포함) 누른 키를 뗀다. AFK 방지만 남긴다. 게임 밖에서 End 가 안 잡히면 트레이 메뉴. Pause 는 전역 키라 노트북 Fn 오타로 꺼지지 않게 두 번 눌러야 한다.

F11 작텔은 작업 시작과 종료창의 마지막 대기까지 End와 게임 포커스를 확인한다. 종료창 대기 중 게임 포커스를 잃으면 해당 작텔은 중단하며, 게임으로 돌아와도 자동으로 이어서 No를 누르지 않는다.

## 매크로가 지키는 것

- Esc 를 게임에 보내지 않는다. Rockstar 런처·스팀 Big Picture 가 앞이면 종료 확인으로 받는다. 뒤로 가기·No 는 Backspace.
- 게임 종료·세션 나가기·스토리 모드 확인창에 매크로가 보내는 키는 둘뿐이다. F5 는 문구가 "quit this session" 으로 확인될 때만 Enter(OK), F11 은 게임 종료 확인창에 60초 뒤 Backspace(No). 그 밖에는 아무 키도 보내지 않는다. "quit this Job?"(작업 로비 나가기)은 매크로가 다루지 않고 직접 Backspace → Yes 로 나온다.
- 키를 보내기 전마다 GTA 가 앞인지 본다. 진행 중인 시퀀스(메뉴 매크로·세션 이동·작텔·인형 뽑기)는 포커스가 빠지면 그 자리에서 멈춘다. 수익 자동화 타이머는 다른 창을 전면화하지 않는다. Main의 AFK 방지는 물리 입력과 주입 입력이 둘 다 `AFKRefocusIdleSec`(기본 300초) 넘게 없을 때만 전면화한다. 별도 작업 AFK 실행기는 위에 설명한 유휴 조건(45초)에서 전면화한다. 설정 창의 명시적 실행 버튼은 GTA를 앞으로 가져온다.
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
- `tools\kick-watch\kick-watch.pyw`: 작업 스케줄러 "GTA Kick Watch" 가 5분마다 pythonw 로 띄우는 킥 원인 기록기(이미 돌고 있으면 바로 끝난다). 게임과 매크로에 입력을 보내지 않고 `Main.ahk` 와 키가 겹치지 않는다. 기록은 `%USERPROFILE%\gta-kick\`: `fg.log`(전경 창 변화), `events.log`(세션 변경과 AFK 로그), `shots\`(세션 변경 2·15·45초 뒤 전체 화면), `observations.jsonl`(5초마다 전경·커서·OS 입력 시각), `afk-shots\`(AFK 입력 로그 전후와 세션 변경 직전 GTA 영역). [기록의 의미와 원인 분리 시험](tools/kick-watch/README.md)을 따른다. 입력 실행 로그는 게임의 방치 시간 초기화 성공을 뜻하지 않는다.

별도로 보관하는 도구는 `third_party/` 아래에 있다. Main의 CI 검사와 배포 패키지에는 넣지 않는다. 기존 폴더 안의 파일과 상대 경로는 그대로 보존했다.

- `third_party/Lester-Ver2.0/`: 자체 Python 앱. 해당 디렉터리로 이동한 뒤 그 안의 [README](third_party/Lester-Ver2.0/README.md)에 따라 의존성을 설치하고 `python main.py`로 실행한다.
- `third_party/CodeSwine GTA5O - Private Public Lobby V1.0.1/`: `CodeSwine-Private_Public_Lobby.exe`와 인접한 DLL·설정을 함께 보관한다. 사용하는 바로가기는 새 디렉터리를 대상으로 지정한다.
