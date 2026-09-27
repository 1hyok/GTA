param([int]$Dx = 0, [int]$Dy = 0, [int]$Steps = 10, [int]$StepMs = 15)
# 상대 마우스 이동(카메라 돌리기). GTA 는 원시 입력을 읽으므로 mouse_event 상대 이동이 카메라를 돌린다.
Add-Type 'using System;using System.Runtime.InteropServices;public class MV{[DllImport("user32.dll")]public static extern void mouse_event(uint f,int dx,int dy,uint d,UIntPtr e);}'
$sx = [int]($Dx / $Steps); $sy = [int]($Dy / $Steps)
for ($i = 0; $i -lt $Steps; $i++) { [MV]::mouse_event(1, $sx, $sy, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds $StepMs }
"moved $Dx,$Dy"