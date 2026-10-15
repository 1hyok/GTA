# GTA 확정 자동화 현금흐름 보고서

`EarnLedger.ahk`가 남긴 TSV 사본을 읽어 출처별·시간대별 수입, 지출, 순액을 HTML·JSON·CSV로 만든다. Python 3.12 이상과 표준 라이브러리만 사용하며 macOS·Windows·Linux에서 실행할 수 있다. 게임, 실행 중인 매크로, 입력 원장을 변경하지 않는다.

## 실행

입력 파일, 새 출력 디렉터리, 표시 시간대를 명시한다. 아래 경로는 예시이며 사용자가 확보한 원장 사본 경로를 사용한다.

```sh
python tools/earn-ledger-report/ledger_report.py /path/to/gta-earn-ledger.tsv \
  --output /path/to/new-report --timezone UTC+09:00
```

```powershell
python tools/earn-ledger-report/ledger_report.py 'C:\analysis\gta-earn-ledger.tsv' --output 'C:\analysis\report-20261015' --timezone UTC+09:00
```

`report.html`은 브라우저에서 바로 열 수 있는 독립 보고서다. `report.json`은 선택한 거래 원문, 출처·시각별 합계와 모든 행 진단을 포함한다. `summary.csv`는 전체 합계, 출처별, 시간별, 시간·출처별 그룹을 `record_type`으로 구분한다. CSV 첫 행들에는 집계 범위, 품질, 필터, 입력 해시가 들어 있다. CSV의 숫자 열은 정수이며, 수식으로 해석될 수 있는 출처 문자열에는 작은따옴표를 붙인다. HTML은 원장 문자열을 escape하고 외부 리소스나 스크립트를 사용하지 않는다.

기존 출력 디렉터리는 덮어쓰지 않는다. 새 이름을 지정한다. 종료 코드 0은 보고서 생성 성공이며, 제외 행이 없다는 뜻은 아니다. 입력·시간대·출력 경로 오류는 종료 코드 2다. 합계와 품질 요약을 stdout에 JSON으로 출력한다.

## 시간 선택

`unix_epoch`를 정본 시각으로 사용한다. 표시 시간대는 필수다. `UTC`와 `UTC+09:00` 같은 고정 오프셋은 추가 패키지 없이 사용할 수 있다. `Asia/Seoul` 같은 IANA 이름은 기기에 해당 시간대 데이터가 있을 때 사용할 수 있으며, 없으면 오류를 반환한다. Windows에서 추가 설치 없이 한국 시각을 표시하려면 `UTC+09:00`을 사용한다. 원장의 `local_time`은 시간대 정보가 없으므로 원문으로만 보여 준다.

```sh
python tools/earn-ledger-report/ledger_report.py /path/to/gta-earn-ledger.tsv \
  --output /path/to/new-daily-report --timezone UTC+09:00 --bucket day \
  --start 2026-10-15T00:00:00+09:00 --end 2026-10-16T00:00:00+09:00
```

기본은 `--bucket hour`다. 날짜별 합계는 `--bucket day`로 고른다. `--start`는 포함하고 `--end`는 제외한다. 각 경계는 UTC 오프셋을 포함한 초 단위 ISO 8601 시각이어야 한다. 일광절약시간이 끝나 같은 시간이 두 번 나타나면 시간별 표에 UTC 오프셋을 남겨 두 구간을 분리한다.

## 집계 계약과 한계

- 입력 헤더는 `unix_epoch`, `local_time`, `cash_delta`, `direction`, `transaction`, `source`, `evidence`의 7열 TSV다. UTF-8 BOM과 CRLF를 허용한다.
- 정수가 아닌 시각·금액, 0원, 금액 부호와 방향 불일치, 잘못된 열 수·날짜·문자 인코딩은 집계에서 제외하고 원본 행 번호와 이유를 남긴다. 마지막 행에 줄바꿈이 없으면 쓰기 중일 수 있으므로 완성된 모양이어도 제외한다.
- 7열이 모두 같은 행은 중복 후보로 표시하고 합계에 유지한다. 거래 ID가 없어 실제로 두 번 일어난 거래인지 구분할 수 없다. 중복 후보가 있는 합계는 원본 근거와 함께 검토한다.
- 품질 진단은 입력 전체를 대상으로 한다. 거래·합계·기록 사이 간격은 선택한 시간 구간만 대상으로 한다. 필터 밖 유효 행 수와 선택 구간의 동일 행 후보 수를 따로 보여 준다.
- 수동 창고 판매, 미관측 거래, 원장 생성 전의 수입, 전체 지갑 잔액은 포함하지 않는다. 현금 지출 뒤 쌓이는 재고 자산도 평가하지 않는다. 순액이 음수라는 사실만으로 사업 손실이라고 판정할 수 없다.
- 기록이 있는 시간 구간만 표에 만든다. 공백을 수익 0이나 자동화 중단으로 해석하지 않는다. 첫·마지막 거래 사이 길이를 가동시간으로 취급하거나 시간당 수익률을 계산하지 않는다.
- 실제 실행 여부, 게임 화면 판독의 정확성, 거래 전체의 누락 여부를 검증하는 도구는 아니다. 입력 파일 해시는 읽은 바이트를 식별하며, 원본 게임 결과의 진위를 증명하지 않는다.

`--label '합성 표본, 실제 운영 수익 아님'`으로 자료 설명을 보고서에 넣을 수 있다. 실제 원장과 개인 증거는 저장소에 추가하지 않는다.

포함된 `example.tsv`는 실제 운영 자료가 아닌 합성 표본이다. 동일 행 후보 1개, 방향 불일치 1개, 마지막 미완성 행 1개를 의도적으로 넣었다. 다음 명령의 결과는 유효 거래 8건, 수입 $360,000, 지출 $85,000, 순액 $275,000이며 동일 행 후보도 합계에 들어 있다.

```sh
python tools/earn-ledger-report/ledger_report.py tools/earn-ledger-report/example.tsv \
  --output /path/to/new-example-report --timezone UTC+09:00 \
  --label '합성 표본, 실제 운영 수익 아님'
```

## 검증

```sh
python -m unittest discover -s tools/earn-ledger-report -p 'test_*.py' -v
```

직접 계산한 현금 이동 표본으로 집계, 필터 경계, 시간대·날짜 전환, 중복 후보 유지, 손상·미완성 행 제외, 빈 원장, HTML·CSV 출력, 입력 보존과 덮어쓰기 방지를 검사한다. 전용 CI는 Ubuntu와 Windows의 Python 3.12에서 같은 검사를 실행한다. IANA 데이터가 없는 환경에서는 DST 검사만 건너뛰고 고정 오프셋 검사를 실행한다. 게임 입력과 실제 운영 로그 검증은 하지 않는다.
