# 수익 자동화 정책

2026-10-03 기준 적용 계약이다. 저택 MCT에서 벙커 보급·DJ·나이트클럽 창고 직원을 관리한다. GTA+ Vinewood Club 앱으로 나이트클럽 금고를 회수하고 보석 집행 요원과 스페셜 패키지 창고 직원을 파견한다. 지원 화면은 1920×1080 영어 UI이며 한글 UI는 지원하지 않는다. 시작 방법은 [README의 F9 설명](../README.md#수익-자동화-f9-두-번), 실제 실행 증거와 남은 검증은 [인계 기록](earner-handoff.md)을 따른다.

## 관측과 실행

| 작업 | 기본 설정 | 실행 조건 |
|---|---|---|
| 벙커 | `EarnBunkerIntervalSec=8400`, 대기 중 최대 5분마다 관측 | 실제 빈 보급과 $75,000 확인. 다른 배수 설정은 해당 소모 경계와 가격 확인 |
| DJ | `EarnDJIntervalMin=5`, `EarnDJPopularityPct=95` | 새로 연 Nightclub Home의 인기도 95% 미만에서 기존 DJ 재고용 |
| 금고 | `EarnSafeIntervalMin=5`, `EarnSafeFirstMin=0` | Vinewood 앱에서 Nightclub 금고 $250,000 확인 |
| 창고 직원 | `EarnWarehouseIntervalMin=10` | 만재 품목의 배정 직원과 생산 가능한 미배정 목적지가 함께 존재 |
| 앱 직원 | `EarnBailAgents=1`, `EarnCargoStaff=1`, `EarnStaffIntervalMin=5` | 대상 선택과 준비 문구 확인. 스페셜 패키지는 창고당 $7,500도 확인 |

스케줄러의 5초 확인은 작업 실행 가능 여부를 보는 간격이다. 표의 관측 간격마다 돈을 쓰거나 직원을 움직이는 것은 아니다. 모든 작업은 직렬로 실행하며 현재 화면을 판독하지 못하면 지출·수거·재배정을 진행하지 않는다. 벙커 주문 뒤에는 약 10분 배송 대기와 화면의 배송 중 안내를 구분해 처리한다.

사용자 물리 입력 후 45초가 지났고 GTA가 앞일 때만 작업을 시작한다. 진행 중 사용자 입력·포커스 이탈·End를 감지하면 중단한다. MCT 작업은 필요한 동안만 CEO를 등록하고 작업 후 해제한다. CEO 관리 하위 메뉴에서도 제목과 `Retire` 문맥을 확인하며 종료 화면까지 확인한다. 이 조건은 각 입력의 허용 조건이며 장시간 AFK 접속 유지 성공을 보장하는 검증은 아니다.

## 벙커 보급

직원·장비 업그레이드, 제조 전용, 기본 생산 속도에서 보급 전체는 140분에 소모된다. 한 칸 20%는 28분이며 기본 구매 가격은 한 칸당 $15,000이다. 따라서 설정은 1680초의 정수배 1~5만 허용한다. 연구 전용·제조/연구 겸임·업그레이드 차이·생산 가속이 적용되면 이 시간 전제가 맞지 않으므로 실제 화면의 소모량과 가격 확인이 필요하다. [GTA Wiki 생산 수치](https://gta.fandom.com/wiki/Disruption_Logistics), [GTPlanet의 직접 운영 계산](https://www.gtplanet.net/forum/threads/the-comprehensive-guide-to-gta-online.376233/)

| 설정값(초) | 기본 속도의 소모 시간 | 결손량 | 남은 보급 경계 | 확인할 가격 |
|---:|---:|---:|---:|---:|
| 1680 | 28분 | 20% | 80% | $15,000 |
| 3360 | 56분 | 40% | 60% | $30,000 |
| 5040 | 84분 | 60% | 40% | $45,000 |
| 6720 | 112분 | 80% | 20% | $60,000 |
| 8400 | 140분 | 100% | 0% | $75,000 |

구매 판단은 보급 막대와 확인창 가격을 함께 사용한다. 예를 들어 28분 소모를 골랐지만 관측 때 보급이 75%라면 바로 $30,000을 내지 않고 다음 60% 경계를 기다린다. 판독값이 소모 경계에 못 미치면 미리 사지 않는다. 경계를 조금 지난 값이 구매 후보가 되더라도 확인창 가격이 계획한 칸 수 × $15,000과 다르면 결제하지 않는다. OCR의 숫자나 다른 가격을 추측해서 고치지 않는다. 기본 140분 전략은 0% 판독을 요구한다. 화면의 130개 표본 지점으로 읽는 막대는 게임 내부 수치와 같다고 보장할 수 없으며, 실제 가격 검증을 생략할 근거가 아니다.

주문 시각은 배송 완료 시각이 아니다. 구매한 보급은 약 10분 뒤 도착하며 남은 보급이 있으면 그동안에도 생산한다. 빈 보급에서 주문하는 기본 전략에는 배송 중 생산 공백이 있다. 140분을 선택했다는 이유로 주문부터 140분 뒤 무조건 다시 구매하지 않는다. 생산 가속·중단·배송 도착이 시간 계산을 바꾸므로 화면을 다시 읽는다. 재고가 가득 차 생산이 멈춘 동안에는 사지 않고, 배송 중 안내가 있으면 중복 결제하지 않는다. [배송 시간과 생산 중단 조건](https://gta.fandom.com/wiki/Supplies), [배송 중 생산 설명](https://www.gtplanet.net/forum/threads/the-comprehensive-guide-to-gta-online.376233/)

## DJ 재고용

기존 DJ 재고용은 $10,000에 인기도 +10%p다. 최고 수입 구간인 95~100%에서는 48분마다 $50,000을 받는다. 직원 업그레이드가 적용된 정상 운영에서는 100%와 95% 지급을 받은 뒤 90%에서 재고용한다. [지급 표와 재고용 수치](https://gta.fandom.com/wiki/Nightclubs)

| 정상 운영 방식 | 96분 수입 | 재고용 비용 | 비용을 뺀 수입 |
|---|---:|---:|---:|
| 90%에서 100%로 한 번 재고용 | $100,000 | $10,000 | $90,000 |
| 매 지급 뒤 95%에서 100%로 재고용 | $100,000 | $20,000 | $80,000 |

계산은 일반 수입 배수, 직원 업그레이드, 수거 가능한 금고, 지속 운용을 전제로 하며 운영비는 제외했다. 기본 목표 95%는 첫 번째 주기를 만든다. 처음 읽은 값이 94%처럼 중간값이면 최고 수입 구간으로 복구할 수 있으므로 "90% 초과는 항상 재고용 금지"로 바꾸지 않는다. Solomun/Tale Of Us의 기존 고용 이력과 $10,000 재고용 화면을 확인하며 $100,000 신규 고용은 선택하지 않는다.

지출 판단 전에는 Nightclub의 Home 화면을 새로 열고 `Nightclub Popularity` 문맥과 막대를 확인한다. 이 Home 판독이 95% 미만일 때만 재고용한다. 교체 후에는 Home → MCT → Home으로 한 번 재진입하고 최대 15초 동안 읽기만 반복해 증가를 확인한다. 08:42 실제 시험에서 결제 직후 91%가 그대로 보였으나 08:44 추가 결제 없이 Home을 다시 열자 100%가 확인된 지연 갱신을 반영했다. 값이 갱신되지 않으면 추가 결제하지 않고 중단한다. MCT 카드와 Home 값이 다르게 보인 실제 화면을 확인했으므로 MCT 카드의 인기도는 DJ 지출 근거로 사용하지 않는다. 이전 시험 함수가 넘기는 MCT 판독값도 진단용 인수로만 남아 있다.

## Vinewood 금고

GTA+의 Vinewood Club 앱은 사업장 금고 수익을 원격 회수하는 기능을 제공한다. 현재 정책은 앱에 표시된 Nightclub 금고가 상한 $250,000일 때만 회수한다. [Rockstar의 앱 기능 안내](https://support.rockstargames.com/articles/eUgRHVRSN2V9gimBT32YX/gtav-title-update-1-69-notes-ps5-ps4-xbox-series-x-s-xbox-one-pc)

앱 메인에서 `Claim Business Earnings`를 열면 사업장 목록이 나온다. 메인과 목록은 모두 `THE VINEWOOD CLUB APP` 제목을 쓰며 Nightclub 행 자체에는 금액이 없다. Nightclub을 선택하고 하단 `Claim $250000 from your Nightclub safe.` 문장만 금액 근거로 사용한다. 다른 사업장 이름, 여러 금액, 손상된 숫자는 수거 근거가 될 수 없다.

메인의 `No earnings to claim.`이나 Nightclub의 `Your Nightclub safe is empty.`는 수거 없이 종료한다. $250,000보다 적을 때도 다음 관측까지 기다린다. 만재일 때는 선택과 금액을 다시 읽고 한 번만 수거를 요청한다. 성공 확인은 Nightclub의 빈 금고 문구와 앱 종료 뒤 MCT 접근 안내다. 결과가 불명확해도 수거 Enter를 다시 보내지 않는다.

## 나이트클럽 창고 직원

관측 입력은 7개 품목의 실제 재고 수량·용량·해금 여부·직원 배정이다. 저장층 수로 용량을 추정하지 않는다. `count=capacity`인 품목에 배정된 직원만 이동 원천이고, 해금되어 있으며 `count<capacity`이고 직원이 없는 품목만 목적지다.

목적지 우선순위는 `south_american` → `pharmaceutical` → `cash` → `cargo` → `sporting` → `organic` → `printing`이다. 한 계획에서 같은 직원이나 목적지를 두 번 쓰지 않는다. 목적지가 없으면 현재 배정을 유지하며, 아직 생산 중인 직원이나 빈 창고의 정상 배정을 임의로 재정렬하지 않는다. 품목 누락·중복, 수량 범위 오류, 같은 직원의 중복 배정은 판독 오류로 처리한다.

현재 UI 관측은 직원 5명을 모두 고용하고 각각 담당 품목에 배정한 상태를 요구한다. 다섯 직원의 얼굴과 선택한 품목의 사람 아이콘을 확인한다. 미배정 직원과 판독하지 못한 직원을 구별해 자동 고용·초기 배정하는 기능은 없으며, 담당 품목이 하나로 확인되지 않으면 중단한다. 이동 뒤에는 전체 배정과 재고를 새로 읽어 다음 계획을 만든다.

## Vinewood 앱 직원 파견

사용자는 Vinewood Club 앱에서 보석 집행 요원을 파견하고 스페셜 패키지 창고 직원에게 조달을 맡기는 기능을 추가로 확인했다. Rockstar는 앱의 원격 직원 관리 대상으로 Hangar·Warehouses·Bail Office를 명시한다. 이번 추가 요청은 그중 Bail Office와 Warehouses이며 나이트클럽 창고 직원 재배정과는 다른 작업이다. [Rockstar 1.72 패치노트](https://support.rockstargames.com/articles/0ExWSr9Bvq5Putzsn5w54/gtav-title-update-1-72-notes-ps5-ps4-xbox-series-x-or-s-xbox-one-pc-enhanced)

스페셜 패키지 직원 조달의 기본 비용은 창고당 회당 $7,500다. [Rockstar 1.61 패치노트](https://support.rockstargames.com/articles/5aud9bTiQluHnVEP6x7YRp/gtav-title-update-1-61-notes-ps4-ps5-xbox-one-xbox-series-x-s-pc) 보석 집행 요원의 수익은 Bail Office 금고에 들어간다. [Rockstar 1.69 패치노트](https://support.rockstargames.com/articles/eUgRHVRSN2V9gimBT32YX/gtav-title-update-1-69-notes-ps5-ps4-xbox-series-x-s-xbox-one-pc) 두 직원의 평시 복귀 시간 약 48분은 플레이 관측과 교차 확인한 값이며, 공식 패치노트에 시간 수치가 실려 있지는 않다. [창고 직원 플레이 기록](https://gtaforums.com/topic/984368-bug-lupe-generic-warehouse-staff-crate-sourcing/), [보석 집행 요원 플레이 기록](https://gtaforums.com/topic/997642-gta-online-bottom-dollar-bounties-out-now/page/13/)

`EarnVinewoodStaffTask`는 Main과 F9 스케줄러에 연결돼 있다. 앱 메인의 `Manage Staff Members`를 열고 Bail Office와 Warehouse를 각각 확인한다. 기본 5분은 상태 관측 간격이며 준비 상태가 돌아왔을 때만 다시 파견한다. 약 48분을 고정 재주문 시각으로 사용하지 않는다.

앱 제목과 메뉴 행은 메뉴 영역을 잘라 읽는다. 일반 OCR이 투명 배경의 흰 글자를 놓치면 같은 영역을 흰 글자 전처리로 다시 읽되, 정확한 전체 문구와 행 위치를 요구한다. 선택된 행의 검은 글자는 일반 OCR로 확인하며 Enter 직전에도 같은 대상의 선택을 새로 확인한다. 잘린 이름을 완전한 문구로 간주하지 않는다.

| 대상 | 선택 후 준비 문구 | 요청 뒤 확인 문구 |
|---|---|---|
| Bail Office의 Agent 1·2 | `Send your Bail Office staff member out on a job.` | `Your Bail Office staff member is currently out on a job.` |
| Warehouse의 선택 창고 | `Send your Warehouse staff member out on a job.`와 $7,500 | `Your Warehouse staff member is currently out on a job.` |

창고는 관측한 목록의 1~5개 행을 순서대로 선택하며 이름을 하드코딩하지 않는다. 선택된 흰 행의 이름·가격은 일반 OCR로, 하단의 두 줄 설명은 흰 글자 전처리를 거쳐 읽는다. 상세 문구 위치와 메뉴의 행 간격으로 목록의 끝을 확인한다. `There is no more room to store cargo for this property.`이면 만재로 건너뛰고 작업 중 문구에서도 주문하지 않는다. 회색으로 비활성화된 행의 가격을 읽지 못해도 명시적인 작업 중·만재 상태에서는 건너뛸 수 있지만, 준비 상태의 가격은 반드시 $7,500이어야 한다.

요청 직전에 같은 대상·선택·상태를 새로 읽고 스페셜 패키지 가격도 재확인한다. Enter는 한 번만 보내며 요청 직전부터 최대 60초 동안 작업 중 문구를 기다린다. 같은 앱 제목과 선택 대상이 확인되면 일시적인 설명 판독 실패에는 읽기만 다시 시도한다. 비선택 회색 요원명이 빠져도 선택한 요원의 정확한 이름·행 위치·선택 픽셀과 전체 Bail 상세 문구가 필요하다. 60초 절대 기한을 각 OCR 호출에도 전달하며 기한 뒤 확인된 결과는 성공으로 기록하지 않는다. 실제 관측에서는 Enter 직후 준비 문구가 남았다가 약 40초 뒤 작업 중 문구를 확인했다. 기한 내 확인 실패·선택 신원 변경·사용자 입력·포커스 이탈 때는 재요청하지 않고 중단한다. 과거 앱에서 만재 창고 주문과 거래 대기 문제가 관측된 점도 이 확인 조건에 반영했다. [앱 직접 사용 보고](https://www.reddit.com/r/gtaonline/comments/1pnxwwo/so_this_happened/)

이번 요청은 요원 파견과 스페셜 패키지 조달이다. Bail Office 금고 수거와 Hangar 파견은 포함하지 않는다. Bail Office 금고가 가득 차면 파견 수익이 쌓이지 않을 수 있으므로 해당 금고의 회수는 사용자가 관리한다.

## 검증

아래 명령은 실제 정책·앱 함수와 모의 화면을 사용하며 게임에 입력하지 않는다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnpolicy.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnvinewood.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnwarehouse.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnwarehouse-read.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earntasks.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnstaff.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnstaff.ps1 -FixtureDirectory "$env:TEMP\claude"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnocr.ps1 -VinewoodSamplePath "$env:TEMP\claude\earn-vinewood-amount.png" -StaffSampleDirectory "$env:TEMP\claude"
```

`-FixtureDirectory`는 로컬에 저장한 Bail 준비·작업 중, Cargo 준비·작업 중·만재, 요원 2 파견 뒤 결과, 앱 메인과 직원 관리 행 선택 화면까지 8장을 실제 OCR과 정책 함수에 넣는다. 원본 전체 화면은 저장소에 포함하지 않는다. 무입력 검사는 게임 입력·창 전면화·화면 캡처를 대체하고, 오류를 대화상자 대신 stdout과 종료 코드로 회수한다.

확인된 입력 없는 검사는 정책 101건, Vinewood 147건, 작업 분기 278건, 반복 예약 41건과 입력 잠금 9건, 나이트클럽 창고 흐름 85건, 창고 판독 38건, 화면·금액 판독 48건, OCR 명령 구성 39건이다. 앱 직원은 모의 화면 438건, 실제 저장 화면의 OCR을 포함하면 462건이다. OCR 기반 검사는 9건이며 실제 저장 화면을 추가한 실행은 15건이다. `test-mct-seated-template`은 나이트클럽 템플릿 18건과 MCT 템플릿·생성 재현 9건을 실행하며, 별도 실제 앉은 화면을 추가하면 MCT 검사는 10건이다. AFK 관련 검사는 상태 분기 48건, 알림 명령 60건, 입력 잠금 35건, 알림 처리 52건이다. 작업 분기 278건은 이번 반영 대상의 staged 트리 기준이며 다른 작업의 탐색 검사 11건이 포함된 작업 디렉터리의 289건과 구분한다. 전체 CI 결과는 `tools/ci/run-checks.ps1`이 기록하는 `results.json`으로 확인하며 각 결과는 해당 실행의 코드와 자료 범위에 한정된다.

저택 MCT에서 일어난 뒤 반대 벽을 보던 화면을 제자리 180도 카메라 회전으로 되돌려 `Press E to sit down.` 안내를 확인했다. MCT 종료 안내 대기를 보완한 뒤 실제 벙커 작업은 재고 36%·보급 22%에서 구매 없이 다음 경계를 기다리고 CEO 해제까지 성공했다. DJ 작업은 Home 100%에서 무구매로, 나이트클럽 창고 작업은 이동 대상 없이 배정을 유지하고 각각 CEO 해제까지 마쳤다. 금고 작업은 Nightclub $150,000을 확인해 수거 없이 앱을 닫고 복귀했다.

새 직원 모듈의 실제 전체 실행은 요원 1 파견, 요원 2 작업 중 건너뛰기, Discount Retail Unit·Railyard Warehouse·Darnell Bros Warehouse·West Vinewood Backlot의 각 $7,500 조달과 작업 중 확인, Foreclosed Garage 만재 건너뛰기, 앱 종료와 MCT 앞 복귀까지 성공했다. 결과는 `EarnVinewoodStaffTask() = 1`, 153,922ms, 종료 코드 0이다. 남은 실전 검증은 새 벙커 결제 분기, 실제 $250,000 금고 수거, 나이트클럽 직원 재배정과 장시간 스케줄러 운용이다. 증거 경로와 중간 실패 기록은 [인계 기록](earner-handoff.md#현재-정책과-검증-범위-2026-10-03)에 있다.

기존 DJ·벙커 수익 정책에는 실제 ChatGPT Pro 5/5 검토 응답을 반영했다. 추가 직원 파견 범위의 외부 검토는 브라우저 연결 실패로 전송하지 못했으므로 미완료다. 9월의 현장 금고 수거와 이동 시도는 앱 경로 성공 근거로 사용하지 않는다.
