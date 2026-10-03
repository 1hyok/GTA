#Requires -Version 5.1
param(
    [long]$WindowHandle,
    [uint32]$ProcessId,
    [uint32]$LastInputTick,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'

function New-NotificationResult {
    param([string]$Status, [int]$ExitCode)
    [pscustomobject]@{ Status = $Status; ExitCode = $ExitCode }
}

function Get-NotificationBlockReason {
    param($Snapshot, [long]$ExpectedHandle, [uint32]$ExpectedProcess, [uint32]$ExpectedInput)
    if ($null -eq $Snapshot) { return 'snapshot-missing' }
    if ($Snapshot.WindowHandle -ne $ExpectedHandle) { return 'foreground-changed' }
    if ($Snapshot.ProcessId -ne $ExpectedProcess) { return 'process-changed' }
    if ($Snapshot.ProcessName -cne 'ShellExperienceHost.exe') { return 'wrong-process' }
    if ($Snapshot.Title -cne 'New notification') { return 'wrong-title' }
    if ($Snapshot.LastInputTick -ne $ExpectedInput) { return 'input-changed' }
    return ''
}

function Invoke-NotificationDismiss {
    param([long]$ExpectedHandle, [uint32]$ExpectedProcess, [uint32]$ExpectedInput, [hashtable]$Adapter)
    try {
        if ($ExpectedHandle -le 0 -or $ExpectedProcess -eq 0) {
            return New-NotificationResult 'blocked:invalid-identity' 2
        }
        $reason = Get-NotificationBlockReason (& $Adapter.Snapshot $ExpectedHandle) $ExpectedHandle $ExpectedProcess $ExpectedInput
        if ($reason) { return New-NotificationResult ('blocked:' + $reason) 2 }

        $matches = @(
            foreach ($candidate in @(& $Adapter.Candidates $ExpectedHandle)) {
                $state = & $Adapter.ButtonState $candidate
                if ($state.Name -ceq 'Move this notification to Notification Center' -and $state.IsButton -eq $true) {
                    $candidate
                }
            }
        )
        if ($matches.Count -ne 1) { return New-NotificationResult 'blocked:exact-button-count' 2 }
        $button = $matches[0]
        $state = & $Adapter.ButtonState $button
        if ($state.Name -cne 'Move this notification to Notification Center' -or $state.IsButton -ne $true) {
            return New-NotificationResult 'blocked:button-changed' 2
        }
        if ($state.Enabled -ne $true) { return New-NotificationResult 'blocked:button-disabled' 2 }
        if ($state.Offscreen -ne $false) { return New-NotificationResult 'blocked:button-offscreen' 2 }
        $pattern = & $Adapter.Pattern $button
        if ($null -eq $pattern) { return New-NotificationResult 'blocked:invoke-unavailable' 2 }

        # Final identity/input check comes after every potentially slow UIA read.
        $reason = Get-NotificationBlockReason (& $Adapter.Snapshot $ExpectedHandle) $ExpectedHandle $ExpectedProcess $ExpectedInput
        if ($reason) { return New-NotificationResult ('blocked:' + $reason) 2 }
        $null = & $Adapter.Invoke $pattern
        return New-NotificationResult 'dismissed' 0
    } catch {
        $reason = [regex]::Replace($_.Exception.GetType().Name, '([a-z])([A-Z])', '$1-$2').ToLowerInvariant()
        return New-NotificationResult ('error:' + $reason) 1
    }
}

function Initialize-NotificationNative {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class GtaNotificationNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    public static uint LastInputTick() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref info)) throw new Win32Exception(Marshal.GetLastWin32Error());
        return info.dwTime;
    }
}
'@
}

function Get-NotificationSnapshot {
    param([long]$ExpectedHandle)
    $handle = [IntPtr]$ExpectedHandle
    [uint32]$ownerProcess = 0
    if ([GtaNotificationNative]::GetWindowThreadProcessId($handle, [ref]$ownerProcess) -eq 0) {
        throw 'Notification window no longer exists.'
    }
    $process = [Diagnostics.Process]::GetProcessById([int]$ownerProcess)
    try { $processName = $process.MainModule.ModuleName } finally { $process.Dispose() }
    $title = New-Object Text.StringBuilder 512
    $null = [GtaNotificationNative]::GetWindowText($handle, $title, $title.Capacity)
    [pscustomobject]@{
        ProcessId = $ownerProcess
        ProcessName = $processName
        Title = $title.ToString()
        WindowHandle = [GtaNotificationNative]::GetForegroundWindow().ToInt64()
        LastInputTick = [GtaNotificationNative]::LastInputTick()
    }
}

function New-NotificationAdapter {
    @{
        Snapshot = { param($Handle) Get-NotificationSnapshot $Handle }
        Candidates = {
            param($Handle)
            $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Handle)
            $condition = New-Object Windows.Automation.PropertyCondition(
                [Windows.Automation.AutomationElement]::NameProperty,
                'Move this notification to Notification Center'
            )
            $root.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
        }
        ButtonState = {
            param($Button)
            $current = $Button.Current
            [pscustomobject]@{
                Name = $current.Name
                IsButton = $current.ControlType -eq [Windows.Automation.ControlType]::Button
                Enabled = $current.IsEnabled
                Offscreen = $current.IsOffscreen
            }
        }
        Pattern = {
            param($Button)
            $pattern = $null
            if ($Button.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
                $pattern
            }
        }
        Invoke = { param($Pattern) $Pattern.Invoke() }
    }
}

function Write-NotificationResult {
    param([string]$Path, [string]$Status)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $temporary = $fullPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Status, (New-Object Text.UTF8Encoding $false))
        if ([IO.File]::Exists($fullPath)) {
            [IO.File]::Replace($temporary, $fullPath, [NullString]::Value)
        } else {
            [IO.File]::Move($temporary, $fullPath)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { exit 1 }
    Initialize-NotificationNative
    $result = Invoke-NotificationDismiss $WindowHandle $ProcessId $LastInputTick (New-NotificationAdapter)
} catch {
    $reason = [regex]::Replace($_.Exception.GetType().Name, '([a-z])([A-Z])', '$1-$2').ToLowerInvariant()
    $result = New-NotificationResult ('error:' + $reason) 1
}
try { Write-NotificationResult $OutputPath $result.Status } catch { exit 1 }
exit $result.ExitCode
