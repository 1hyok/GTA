# 오프라인 검사

GitHub Actions는 PR에서 전체 검사를 한 번 실행한다. `push` 검사는 `main`에만 실행해 PR 브랜치의 동일 커밋이 `push`와 `pull_request`에서 중복 검사되지 않게 한다. `workflow_dispatch`는 전체 검사를 수동 실행한다.

Windows PowerShell 5.1과 Python 3.12를 사용한다. AutoHotkey는 공식 배포 ZIP을 별도 디렉터리에 풀고, 버전과 ZIP·실행 파일 SHA256을 `autohotkey.json`과 대조한다. 사용자 설치는 변경하지 않는다.

```powershell
$runtime = Join-Path $env:TEMP ('gta-ahk-' + [guid]::NewGuid().ToString('N'))
$results = Join-Path $env:TEMP ('gta-checks-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $env:TEMP ('gta-package-' + [guid]::NewGuid().ToString('N'))
$ahk = & .\tools\ci\install-autohotkey.ps1 -Destination $runtime
& .\tools\ci\run-checks.ps1 -AhkPath $ahk -PythonPath python -Checks @('validate-main', 'test-earntasks') -OutputDirectory $results
if ($LASTEXITCODE -ne 0) { throw '검사 실패. results.json과 개별 로그를 확인한다.' }
```

개발 중에는 변경된 영역의 검사만 `-Checks`에 지정한다. 전체 검사 이름은 `run-checks.ps1`의 `$allExpectedChecks` 목록을 따른다. PR을 만들면 GitHub Actions가 전체 검사를 실행하므로 전체 로컬 검사와 패키징을 매번 반복할 필요가 없다. 릴리스 패키지를 만들 때만 `-Checks`를 생략해 전체 검사를 완료한 뒤 `package-macro.ps1`을 실행한다.

수동으로 전체 검사와 패키징이 필요한 경우에는 다음처럼 실행한다.

```powershell
& .\tools\ci\run-checks.ps1 -AhkPath $ahk -PythonPath python -OutputDirectory $results
if ($LASTEXITCODE -ne 0) { throw '전체 검사 실패. results.json과 개별 로그를 확인한다.' }
& .\tools\ci\package-macro.ps1 -CheckResults (Join-Path $results 'results.json') -OutputDirectory $package
```

`run-checks.ps1`은 PowerShell 구문, 관리 중인 Python·PYW 구문, Main의 AHK include 구문, 명시된 오프라인 회귀검사를 확인한다. Python 코드를 import하거나 실행하지 않는다. Main은 `/validate`만 사용하며, 게임 입력·실화면 캡처·성능 감시 본문·작업 스케줄러를 실행하지 않는다. 실제 게임 동작 검증은 별도다.

각 검사에 종료 코드, 시간 제한, stdout/stderr 로그가 있고 `results.json`에 전체 또는 targeted 범위, 리비전·작업 트리 상태·입력 파일 해시를 기록한다. targeted 결과는 로컬 반복 확인용이며 패키징이 거부된다. 검증 중에는 소스를 동시에 편집하지 않는다. 오프라인 검사에서 게임 의존성을 대체하는 방식은 보안 sandbox를 제공하지 않는다. 결과 디렉터리는 저장소 밖의 새 경로를 권장한다. GitHub Actions는 공백이 있는 checkout 경로에서 전체 검사를 실행한다.

ZIP은 성공한 검사 결과와 현재 소스 해시가 일치할 때만 만든다. 포함 범위는 `Main.ahk`, `Core`의 AHK·PowerShell, `Features`의 AHK, `Images`의 이미지, `README.md`, `Config.example.ini`, 파일별 SHA256을 담은 `manifest.json`이다. 사용자 `Config.ini`, 외부 도구, 테스트, 캡처 증거, 로그, 인터프리터는 포함하지 않는다.

검증 시작 시 Git 작업 트리에 변경이 있으면 ZIP 이름에 `-dirty`를 붙인다. Manifest에는 그 상태를 나타내는 `workingTreeDirty`와 검증 결과 파일의 SHA256을 기록하며, 로컬 변경 파일 목록은 공개하지 않는다. 이 상태값은 파일 내용이 HEAD와 일치한다는 증명은 아니며, Git에서 무시한 파일도 포함 범위에 맞으면 ZIP에 들어갈 수 있다. 포함 파일의 동일성은 파일별 SHA256으로 확인한다. 작업 트리 상태가 없는 이전 검사 결과는 다시 검증해야 한다. ZIP은 실행별 고유한 임시 이름으로 생성하고, 압축 안의 각 파일과 생성한 manifest의 SHA256까지 검증한 뒤 최종 `.zip`과 `.sha256` 이름으로 발행한다.

신규 설치에서는 예시 설정을 `Config.ini`로 복사하고 필요한 기능을 선택한다. 예시의 입력 기능과 자동 AFK는 꺼져 있다. 기존 설치에서는 사용자 `Config.ini`를 유지한다. ZIP 생성과 업로드는 실행 중인 매크로 교체나 PC 자동 배포를 하지 않는다.
