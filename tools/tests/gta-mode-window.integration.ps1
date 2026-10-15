#Requires -Version 7.6
# A private WinForms fixture only; never opens G-Helper or sends game input.
param([string]$ControllerPath = (Join-Path $PSScriptRoot '..\..\Core\gta-turbo.ps1'))
$ErrorActionPreference = 'Stop'
. $ControllerPath -LibraryOnly
$fixture = Join-Path $env:TEMP ('gta-mode-window-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$child = $null; $window = $null
try {
    $hostScript = Join-Path $fixture 'host.ps1'
    [IO.File]::WriteAllText($hostScript, @'
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object Windows.Forms.Form
$form.Text = 'GTA mode test fixture'
$button = New-Object Windows.Forms.Button
$button.Name = 'buttonSilent'
$button.Text = 'Silent'
$form.Controls.Add($button)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'handle.txt'), $form.Handle.ToInt64().ToString())
[Windows.Forms.Application]::Run()
'@)
    $exe = (Get-Process -Id $PID).Path
    $child = Start-Process $exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$hostScript`"" -WindowStyle Hidden -PassThru
    $handlePath = Join-Path $fixture 'handle.txt'
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Path $handlePath)) {
        if ($child.HasExited -or (Get-Date) -ge $deadline) { throw 'Fixture did not start.' }
        Start-Sleep -Milliseconds 100
    }
    Initialize-ModeWindow
    $window = [GtaModeWindow]::Read([IntPtr]([long][IO.File]::ReadAllText($handlePath)))
    if ($window.ProcessId -ne $child.Id -or $window.Visible) { throw 'Unexpected fixture identity or visibility.' }
    $foreground = [GtaModeWindow]::GetForegroundWindow()
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $element = [Windows.Automation.AutomationElement]::FromHandle($window.Handle)
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, 'buttonSilent')
    if ($element.FindAll([Windows.Automation.TreeScope]::Descendants, $condition).Count -ne 0) { throw 'Fixture controls were not lazy.' }
    [GtaModeWindow]::Prepare($window)
    Start-Sleep -Milliseconds 500
    $element = [Windows.Automation.AutomationElement]::FromHandle($window.Handle)
    if ($element.FindAll([Windows.Automation.TreeScope]::Descendants, $condition).Count -ne 1) { throw 'Nonactivating preparation did not create the lazy button.' }
    [GtaModeWindow]::Restore($window)
    if ([GtaModeWindow]::GetForegroundWindow() -ne $foreground) { throw 'Fixture changed the foreground window.' }
    'PASS lazy WinForms button creation, hidden-state restoration and foreground preservation'
} finally {
    if ($child -and -not $child.HasExited) { Stop-Process -Id $child.Id }
    Get-ChildItem -LiteralPath $fixture -File | Remove-Item
    Remove-Item -LiteralPath $fixture
}
