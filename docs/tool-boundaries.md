# GTA 코드와 도구의 경계

하나의 저장소에서 함께 검토하되 실행 방식과 검증 범위를 구분한다. 별도 프로세스라는 이유만으로 저장소를 나누지 않는다.

| 구성요소 | 위치 | 실행과 검증 |
|---|---|---|
| 매크로 런타임 | `Main.ahk`, `Core/`, `Features/`, `Images/` | 한 프로세스에서 입력 잠금·전체 멈춤·AFK 상태를 공유한다. 문법과 무입력 회귀검사를 CI에서 실행한다. |
| 캡처 런타임 | `Core/ScreenCapture.ps1` | 수익 자동화가 동기로 호출한다. 저장소와 배포 패키지에 포함한다. 실제 화면 캡처는 현장 실행이다. |
| 무입력 회귀검사 | `tools/earn-test/test-*.ps1`, `tools/earn-test/test-session-guard.ahk`, `tools/tests/` | CI 실행 목록은 `tools/ci/run-checks.ps1`에 명시한다. 게임 창·입력·캡처는 테스트 대역이나 저장 fixture로 바꾼다. |
| 현장 시험과 입력 도구 | `tools/earn-test/earntest.ahk`, `gui-input.*`, `nav.ps1`, `look.ps1`, `afk-guard.ahk` | 실제 게임 상태와 사용자 조작권을 확인한 뒤 실행한다. CI에서 실행하지 않는다. |
| 캡처와 템플릿 제작 | `tools/earn-test/capscreen.ps1`, `tools/jobwarp-capture.ps1`, `tools/*templates.ps1`, `tools/earn-test/build-mct-templates.ps1` | 수동 현장 도구다. 기존 `capscreen.ps1` 명령은 `Core/ScreenCapture.ps1`로 위임한다. |
| 성능 감시 | `tools/gta-perf-watch.ps1`, `tools/gta-perf-watch.vbs` | 실제 스케줄러가 이 경로를 사용한다. 판정 함수의 fixture 검사만 CI에서 실행한다. |
| 킥 기록 | `tools/kick-watch/kick-watch.pyw` | 실제 스케줄러가 이 경로를 사용한다. CI에서는 Python 구문을 확인한다. |
| 별도 보관 도구 | `third_party/Lester-Ver2.0/`, `third_party/CodeSwine GTA5O - Private Public Lobby V1.0.1/` | 자체 실행기와 의존성을 가진다. 로컬에만 두고 저장소에서 추적하지 않는다(1010). |

`tools/earn-test`의 기존 경로는 현장 사용처를 위해 유지한다. CI는 폴더 전체를 자동 실행하지 않고 위 실행 목록에 등록한 검사만 선택한다. 현장 도구를 추가해도 CI의 실행 권한이 늘어나지 않는다.

## 캡처 경로

`EarnSnapMinimap`은 `Features/Earn/EarnCore.ahk` 자신의 경로인 `A_LineFile`을 기준으로 캡처 스크립트를 찾는다. `Main.ahk`와 `tools/earn-test/earntest.ahk`에서 같은 런타임을 사용하며, `%TEMP%\claude\capscreen.ps1` 사본이 필요하지 않다. 결과는 기존과 같이 `%TEMP%\claude\gta-earn-<tag>.png`에 저장한다. 출력 디렉터리가 없으면 생성한다.

`EarnSnapFail`도 같은 스크립트로 MCT 실패 순간의 GTA 클라이언트 전체를 `%TEMP%\claude\gta-earn-fail-<시각>-<사유>.png`에 남기고 30장을 넘으면 오래된 것부터 지운다. `EarnFail`에서 `MCT`로 시작하는 사유에만 호출되며, GTA 창이 없으면 아무것도 하지 않는다.

`tools/tests/screen-capture.tests.ps1`은 실제 호출 함수를 별도 디렉터리에 놓고 두 진입점에서 실행한다. 화면 조회는 대역으로 바꾸고 캡처 스크립트는 전달받은 인자만 기록한다. 공백과 `&`가 있는 경로, 음수 좌표, 기존 수동 명령의 인자와 기본값, 새 출력 디렉터리 생성을 검사한다. 이 검사는 실제 화면을 캡처하지 않는다.

## 감시 도구의 운영 데이터

성능 감시의 데이터는 `%USERPROFILE%\gta-perf`, 킥 기록은 `%USERPROFILE%\gta-kick`에 둔다. 성능 감시는 매크로 로그 네 종류를 읽고, 킥 기록기는 AFK 로그를 읽는다. 이 로그 계약과 기존 스케줄러 실행 경로를 유지한다. 소유자·릴리스 주기·의존성 관리가 실제로 갈라질 때 별도 저장소를 검토하고, 옮길 때는 스케줄러와 로그 소비처를 함께 검증한다.

## 배포 범위

CI에서 만든 패키지는 `Main.ahk`, `Core/`, `Features/`, `Images/`, README, `Config.example.ini`와 파일 목록·해시를 묶는다. `tools/`, `third_party/`, 운영 로그·스크린샷·실제 `Config.ini`는 포함하지 않는다. 설치된 매크로 교체, 재시작, 설정 적용, 감시 작업 등록은 패키지 생성과 별도로 수행한다.
