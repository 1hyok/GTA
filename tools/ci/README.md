# 오프라인 CI

Windows PowerShell 5.1과 Python 3.12를 사용한다. AutoHotkey는 공식 배포 ZIP을 별도 디렉터리에 풀고, 버전과 ZIP·실행 파일 SHA256을 `autohotkey.json`과 대조한다. 사용자 설치는 변경하지 않는다.

```powershell
$runtime = Join-Path $env:TEMP ('gta-ahk-' + [guid]::NewGuid().ToString('N'))
$results = Join-Path $env:TEMP ('gta-checks-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $env:TEMP ('gta-package-' + [guid]::NewGuid().ToString('N'))
$ahk = & .\tools\ci\install-autohotkey.ps1 -Destination $runtime
& .\tools\ci\run-checks.ps1 -AhkPath $ahk -PythonPath python -OutputDirectory $results
if ($LASTEXITCODE -ne 0) { throw '검사 실패. results.json과 개별 로그를 확인한다.' }
& .\tools\ci\package-macro.ps1 -CheckResults (Join-Path $results 'results.json') -OutputDirectory $package
```

`run-checks.ps1`은 PowerShell 구문, 관리 중인 Python·PYW 구문, Main의 AHK include 구문, 명시된 오프라인 회귀검사를 확인한다. Python 코드를 import하거나 실행하지 않는다. Main은 `/validate`만 사용하며, 게임 입력·실화면 캡처·성능 감시 본문·작업 스케줄러를 실행하지 않는다. 실제 게임 동작 검증은 별도다.

각 검사에 종료 코드, 시간 제한, stdout/stderr 로그가 있고 `results.json`에 리비전·작업 트리 상태·입력 파일 해시를 기록한다. 결과 디렉터리는 저장소 밖의 새 경로를 권장한다. GitHub Actions는 공백이 있는 checkout 경로에서 같은 명령을 실행한다.

ZIP은 성공한 검사 결과와 현재 소스 해시가 일치할 때만 만든다. 포함 범위는 `Main.ahk`, `Core`의 AHK·PowerShell, `Features`의 AHK, `Images`의 이미지, `README.md`, `Config.example.ini`, 파일별 SHA256을 담은 `manifest.json`이다. 사용자 `Config.ini`, 외부 도구, 테스트, 캡처 증거, 로그, 인터프리터는 포함하지 않는다.

신규 설치에서는 예시 설정을 `Config.ini`로 복사하고 필요한 기능을 선택한다. 예시의 입력 기능과 자동 AFK는 꺼져 있다. 기존 설치에서는 사용자 `Config.ini`를 유지한다. ZIP 생성과 업로드는 실행 중인 매크로 교체나 PC 자동 배포를 하지 않는다.
