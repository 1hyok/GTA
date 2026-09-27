param(
  [string[]]$Keys = @(),        # e.g. Esc, Right, Down, Enter, Backspace, Up, Left, E, F10, Space
  [int]$GapMs = 750,
  [int]$IdleSec = 12,           # wait until the user has not touched keyboard/mouse for this long
  [int]$MaxWaitSec = 120,
  [string]$Shot = "",
  [int]$ShotDelayMs = 1500,
  [switch]$NoActivate
)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class NV {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LII p);
  public static double IdleSeconds(){ LII l = new LII(); l.cbSize=(uint)Marshal.SizeOf(l); GetLastInputInfo(ref l); return (Environment.TickCount - (int)l.dwTime)/1000.0; }
  public static void Tap(byte vk, bool ext){ byte sc=(byte)MapVirtualKey(vk,0); uint f = ext ? 1u : 0u; keybd_event(vk,sc,f,UIntPtr.Zero); System.Threading.Thread.Sleep(70); keybd_event(vk,sc,f|2u,UIntPtr.Zero); }
  public static void Hold(byte vk, bool ext, int ms){ byte sc=(byte)MapVirtualKey(vk,0); uint f = ext ? 1u : 0u; keybd_event(vk,sc,f,UIntPtr.Zero); System.Threading.Thread.Sleep(ms); keybd_event(vk,sc,f|2u,UIntPtr.Zero); }
}
"@
$map = @{ Esc=@(0x1B,$false); Enter=@(0x0D,$false); Backspace=@(0x08,$false); Space=@(0x20,$false); Tab=@(0x09,$false)
          Up=@(0x26,$true); Down=@(0x28,$true); Left=@(0x25,$true); Right=@(0x27,$true)
          E=@(0x45,$false); W=@(0x57,$false); P=@(0x50,$false); Q=@(0x51,$false); M=@(0x4D,$false); A=@(0x41,$false); S=@(0x53,$false); D=@(0x44,$false); F10=@(0x79,$false); F9=@(0x78,$false); Alt=@(0x12,$false); F4=@(0x73,$false); F5=@(0x74,$false); F6=@(0x75,$false); F7=@(0x76,$false); F8=@(0x77,$false); Numpad0=@(0x60,$false); Numpad1=@(0x61,$false); Numpad2=@(0x62,$false); Numpad3=@(0x63,$false); NumpadDot=@(0x6E,$false); NumpadDiv=@(0x6F,$true); NumpadMult=@(0x6A,$false); End=@(0x23,$true); Pause=@(0x13,$false); Caps=@(0x14,$false); F11=@(0x7A,$false); Home=@(0x24,$true) }
$g = Get-Process GTA5_Enhanced -ErrorAction SilentlyContinue
if (-not $g) { "GTA not running"; exit 2 }
$h = $g.MainWindowHandle
# wait for the user to be idle so our keys do not collide with their typing
$t0 = Get-Date
while ([NV]::IdleSeconds() -lt $IdleSec) {
  if (((Get-Date) - $t0).TotalSeconds -gt $MaxWaitSec) { "user still active after ${MaxWaitSec}s (idle=$([int][NV]::IdleSeconds())s); aborting"; exit 3 }
  Start-Sleep -Milliseconds 1000
}
if (-not $NoActivate -and [NV]::GetForegroundWindow() -ne $h) {
  $fg=[NV]::GetForegroundWindow(); $pid0=0; $t=[NV]::GetWindowThreadProcessId($fg,[ref]$pid0); $me=[NV]::GetCurrentThreadId()
  [NV]::AttachThreadInput($me,$t,$true) | Out-Null; [NV]::Tap(0x12,$false); [NV]::BringWindowToTop($h) | Out-Null; [NV]::SetForegroundWindow($h) | Out-Null; [NV]::AttachThreadInput($me,$t,$false) | Out-Null
  Start-Sleep -Milliseconds 800
}
if ([NV]::GetForegroundWindow() -ne $h) { "GTA not foreground ($([NV]::GetForegroundWindow())); no keys sent"; exit 4 }
foreach ($k in $Keys) {
  $hold = 0
  if ($k -match '^(\w+):(\d+)$') { $k = $Matches[1]; $hold = [int]$Matches[2] }
  if (-not $map.ContainsKey($k)) { "unknown key $k"; continue }
  $vk = [byte]$map[$k][0]; $ext = [bool]$map[$k][1]
  if ($hold -gt 0) { [NV]::Hold($vk,$ext,$hold) } else { [NV]::Tap($vk,$ext) }
  Start-Sleep -Milliseconds $GapMs
}
"$(Get-Date -Format HH:mm:ss) sent: $($Keys -join ' ')"
if ($Shot) { Start-Sleep -Milliseconds $ShotDelayMs; & "$env:TEMP\claude\shot.ps1" -Name $Shot -DelaySec 0 }
