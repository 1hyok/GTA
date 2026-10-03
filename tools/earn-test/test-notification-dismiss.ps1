#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '..\..\Core\NotificationDismiss.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
# Import only pure decision/result functions. The native/UIA adapter and script entry
# point are deliberately never evaluated, so this test cannot dismiss a real toast.
foreach ($name in @('New-NotificationResult', 'Get-NotificationBlockReason', 'Invoke-NotificationDismiss', 'Write-NotificationResult')) {
    $functions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $false))
    if ($functions.Count -ne 1) { throw "Production function missing or ambiguous: $name" }
    . ([scriptblock]::Create($functions[0].Extent.Text))
}
$script:checks = 0
function Assert-Notification {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL NotificationDismiss: $Message" }
    $script:checks++
}

function New-FixtureButton {
    [pscustomobject]@{ Name = 'Move this notification to Notification Center'; IsButton = $true; Enabled = $true; Offscreen = $false }
}

function Reset-NotificationFixture {
    $script:invoked = 0
    $script:snapshots = 0
    $script:buttonReads = 0
    $script:candidateReads = 0
    $script:throwAt = ''
    $script:changeAtEnd = ''
    $script:changeButton = $false
    $script:patternAvailable = $true
    $script:fixture = [pscustomobject]@{ WindowHandle = 12345L; ProcessId = 4321; ProcessName = 'ShellExperienceHost.exe'; Title = 'New notification'; LastInputTick = [uint32]4294967295 }
    $script:buttons = @(New-FixtureButton)
    $script:adapter = @{
        Snapshot = {
            param($Handle)
            $script:snapshots++
            if ($script:throwAt -eq 'snapshot') { throw 'Injected snapshot failure.' }
            if ($script:snapshots -eq 2 -and $script:changeAtEnd) {
                switch ($script:changeAtEnd) {
                    'WindowHandle' { $script:fixture.WindowHandle++ }
                    'ProcessId' { $script:fixture.ProcessId++ }
                    'ProcessName' { $script:fixture.ProcessName = 'Other.exe' }
                    'Title' { $script:fixture.Title = 'Approval' }
                    'LastInputTick' { $script:fixture.LastInputTick = [uint32]0 }
                }
            }
            $script:fixture
        }
        Candidates = {
            param($Handle)
            $script:candidateReads++
            if ($script:throwAt -eq 'candidates') { throw 'Injected UIA enumeration failure.' }
            $script:buttons
        }
        ButtonState = {
            param($Button)
            $script:buttonReads++
            if ($script:throwAt -eq 'button') { throw 'Injected stale element failure.' }
            if ($script:changeButton -and $script:buttonReads -eq 2) { $Button.Name = 'Approve' }
            $Button
        }
        Pattern = {
            param($Button)
            if ($script:throwAt -eq 'pattern') { throw 'Injected pattern failure.' }
            if ($script:patternAvailable) { 'fake-pattern' }
        }
        Invoke = {
            param($Pattern)
            if ($script:throwAt -eq 'invoke') { throw 'Injected invoke failure before effect.' }
            if ($Pattern -cne 'fake-pattern') { throw 'Unexpected invocation target.' }
            $script:invoked++
        }
    }
}

function Test-NotificationFixture {
    param([string]$Name, [string]$ExpectedStatus, [int]$ExpectedCode = 2, [int]$ExpectedInvokes = 0, [long]$Handle = 12345, [uint32]$Owner = 4321)
    $result = Invoke-NotificationDismiss $Handle $Owner ([uint32]4294967295) $script:adapter
    Assert-Notification ($result.Status -ceq $ExpectedStatus -and $result.ExitCode -eq $ExpectedCode -and $script:invoked -eq $ExpectedInvokes) "$Name (status=$($result.Status), exit=$($result.ExitCode), invokes=$script:invoked)"
}

Reset-NotificationFixture
Test-NotificationFixture 'one exact visible enabled button invokes once' 'dismissed' 0 1
Assert-Notification ($script:snapshots -eq 2) 'identity and input rechecked immediately before invocation'
Reset-NotificationFixture
Test-NotificationFixture 'invalid HWND' 'blocked:invalid-identity' -Handle 0
Reset-NotificationFixture
Test-NotificationFixture 'invalid PID' 'blocked:invalid-identity' -Owner 0
foreach ($case in @(
    @('WindowHandle', 12346L, 'foreground-changed'),
    @('ProcessId', 4322, 'process-changed'),
    @('ProcessName', 'Other.exe', 'wrong-process'),
    @('ProcessName', 'shellexperiencehost.exe', 'wrong-process'),
    @('Title', 'New notification - Approval', 'wrong-title'),
    @('Title', 'new notification', 'wrong-title'),
    @('LastInputTick', [uint32]0, 'input-changed')
)) {
    Reset-NotificationFixture
    $script:fixture.($case[0]) = $case[1]
    Test-NotificationFixture ("wrong initial " + $case[0]) ('blocked:' + $case[2])
    Assert-Notification ($script:candidateReads -eq 0) 'initial mismatch never enumerates UIA'
}
foreach ($field in @('WindowHandle', 'ProcessId', 'ProcessName', 'Title', 'LastInputTick')) {
    Reset-NotificationFixture
    $script:changeAtEnd = $field
    $reason = @{ WindowHandle = 'foreground-changed'; ProcessId = 'process-changed'; ProcessName = 'wrong-process'; Title = 'wrong-title'; LastInputTick = 'input-changed' }[$field]
    Test-NotificationFixture ("changed before invoke: " + $field) ('blocked:' + $reason)
}
Reset-NotificationFixture
$script:buttons = @()
Test-NotificationFixture 'no exact button' 'blocked:exact-button-count'
Reset-NotificationFixture
$script:buttons = @((New-FixtureButton), (New-FixtureButton))
Test-NotificationFixture 'multiple exact buttons' 'blocked:exact-button-count'
Reset-NotificationFixture
$script:buttons[0].Name = 'Approve'
Test-NotificationFixture 'approval is never a dismissal target' 'blocked:exact-button-count'
Reset-NotificationFixture
$script:buttons[0].Name = 'Decline'
Test-NotificationFixture 'decline is never a dismissal target' 'blocked:exact-button-count'
Reset-NotificationFixture
$script:buttons[0].Name += ' now'
Test-NotificationFixture 'partial name match rejected' 'blocked:exact-button-count'
Reset-NotificationFixture
$script:buttons[0].IsButton = $false
Test-NotificationFixture 'same name but not a button' 'blocked:exact-button-count'
Reset-NotificationFixture
$script:buttons[0].Enabled = $false
Test-NotificationFixture 'disabled button' 'blocked:button-disabled'
Reset-NotificationFixture
$script:buttons[0].Offscreen = $true
Test-NotificationFixture 'offscreen button' 'blocked:button-offscreen'
Reset-NotificationFixture
$script:patternAvailable = $false
Test-NotificationFixture 'no invoke pattern' 'blocked:invoke-unavailable'
Reset-NotificationFixture
$script:changeButton = $true
Test-NotificationFixture 'button identity changed' 'blocked:button-changed'
Reset-NotificationFixture
$approve = New-FixtureButton
$approve.Name = 'Approve'
$script:buttons = @($approve, (New-FixtureButton))
Test-NotificationFixture 'unrelated approval button ignored beside dismiss' 'dismissed' 0 1
foreach ($stage in @('snapshot', 'candidates', 'button', 'pattern', 'invoke')) {
    Reset-NotificationFixture
    $script:throwAt = $stage
    Test-NotificationFixture ("exception at " + $stage) 'error:runtime-exception' 1
}

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('gta-notification-test-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testDirectory)
try {
    $resultPath = Join-Path $testDirectory 'result.txt'
    Write-NotificationResult $resultPath 'blocked:input-changed'
    Assert-Notification ([IO.File]::ReadAllText($resultPath) -ceq 'blocked:input-changed') 'atomic first result contains only status'
    Write-NotificationResult $resultPath 'dismissed'
    Assert-Notification ([IO.File]::ReadAllText($resultPath) -ceq 'dismissed') 'atomic replacement contains only new status'
    Write-NotificationResult $resultPath 'error:runtime-exception'
    Assert-Notification ([IO.File]::ReadAllText($resultPath) -ceq 'error:runtime-exception') 'exception status written'
    Assert-Notification (@([IO.Directory]::GetFiles($testDirectory)).Count -eq 1) 'no temporary output remains'

    # Exercise the actual entry point/exit codes in a child process with both native
    # initialization and the entire UIA adapter replaced before any script runs.
    $sourceText = [IO.File]::ReadAllText($sourcePath)
    $mockAdapter = @'
function New-NotificationAdapter {
    @{
        Snapshot = {
            param($Handle)
            [pscustomobject]@{ WindowHandle = 12345L; ProcessId = 4321; ProcessName = 'ShellExperienceHost.exe'; Title = 'New notification'; LastInputTick = [uint32]4294967295 }
        }
        Candidates = { param($Handle) 'fake-button' }
        ButtonState = { param($Button) [pscustomobject]@{ Name = 'Move this notification to Notification Center'; IsButton = $true; Enabled = $true; Offscreen = $false } }
        Pattern = { param($Button) 'fake-pattern' }
        Invoke = { param($Pattern) }
    }
}
'@
    foreach ($entryCase in @(
        @('success', 'function Initialize-NotificationNative {}', 12345, 0, 'dismissed'),
        @('identity-block', 'function Initialize-NotificationNative {}', 54321, 2, 'blocked:foreground-changed'),
        @('initialization-exception', "function Initialize-NotificationNative { throw 'Injected startup failure.' }", 12345, 1, 'error:runtime-exception')
    )) {
        $childText = $sourceText
        $replacements = @(
            @{ Name = 'Initialize-NotificationNative'; Text = $entryCase[1] },
            @{ Name = 'New-NotificationAdapter'; Text = $mockAdapter }
        ) | ForEach-Object {
            $replacement = $_
            $functionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $replacement.Name }, $false)
            if (-not $functionAst) { throw "Missing adapter function $($replacement.Name)" }
            [pscustomobject]@{ Start = $functionAst.Extent.StartOffset; Length = $functionAst.Extent.EndOffset - $functionAst.Extent.StartOffset; Text = $replacement.Text }
        } | Sort-Object Start -Descending
        foreach ($replacement in $replacements) {
            $childText = $childText.Remove($replacement.Start, $replacement.Length).Insert($replacement.Start, $replacement.Text)
        }
        $childPath = Join-Path $testDirectory 'offline-entry.ps1'
        [IO.File]::WriteAllText($childPath, $childText, (New-Object Text.UTF8Encoding $false))
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -WindowHandle {1} -ProcessId 4321 -LastInputTick 4294967295 -OutputPath "{2}"' -f $childPath, $entryCase[2], $resultPath
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $child = New-Object Diagnostics.Process
        $child.StartInfo = $start
        try {
            $null = $child.Start()
            if (-not $child.WaitForExit(10000)) { $child.Kill(); throw 'Offline notification child timed out.' }
            $stdout = $child.StandardOutput.ReadToEnd()
            $stderr = $child.StandardError.ReadToEnd()
            Assert-Notification ($child.ExitCode -eq $entryCase[3]) ("entrypoint exit: " + $entryCase[0])
            Assert-Notification ([IO.File]::ReadAllText($resultPath) -ceq $entryCase[4]) ("entrypoint status: " + $entryCase[0])
            Assert-Notification ([string]::IsNullOrEmpty($stdout) -and [string]::IsNullOrEmpty($stderr)) ("entrypoint writes only result file: " + $entryCase[0])
        } finally { $child.Dispose() }
    }
} finally {
    # Delete only the exact files created above; never recurse into a computed path.
    if ([IO.File]::Exists($resultPath)) { [IO.File]::Delete($resultPath) }
    if ($childPath -and [IO.File]::Exists($childPath)) { [IO.File]::Delete($childPath) }
    [IO.Directory]::Delete($testDirectory)
}
Write-Output "PASS NotificationDismiss checks=$script:checks (offline adapters only)"
