param([string]$CaptureDir = (Join-Path $PSScriptRoot '..\..\docs\evidence\2026-09-27-mct'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$target = Join-Path $PSScriptRoot '..\..\Images\Earn\1920x1080'
# Rectangles refer to the observed 1920x1080 screenshots, never inferred UI.
$items = @(
 @('mansion-mct-return2','mct_bunker_card',830,228,260,26),
 @('mansion-mct-return2','mct_nightclub_card',470,228,106,25),
 @('mansion-bunker-result','bunker_page',305,24,345,87),
 @('mansion-bunker-code-fail','bunker_entry',818,619,237,33),
 @('mansion-bunker-result','bunker_resupply',318,477,135,33),
 @('mansion-bunker-result','bunker_buy',801,769,165,29),
 @('mansion-confirm2','bunker_confirm',700,463,519,31),
 @('mansion-bunker-pending','bunker_pending',682,480,555,32),
 @('mansion-dj-list','nc_dj_menu',329,744,151,32),
 @('mansion-dj-list','dj_solomun',886,246,116,30),
 @('mansion-dj-list','dj_rebook_10k',893,557,101,57),
 @('mansion-dj-confirm','dj_confirm_solomun',605,505,710,56),
 @('mansion-dj-confirm-tale','dj_confirm_tale',595,505,730,56),
 @('mansion-dj-after','dj_resident',886,572,114,28),
 @('mansion-dj-after','nc_home',328,582,80,31)
)
foreach ($item in $items) {
 $source = [Drawing.Bitmap]::FromFile((Join-Path $CaptureDir ($item[0]+'.png')))
 try {
  $rect = New-Object Drawing.Rectangle ([int]$item[2]),([int]$item[3]),([int]$item[4]),([int]$item[5])
  $crop = $source.Clone($rect, $source.PixelFormat)
  try {
   if ($item[1] -ne 'bunker_page') {
    for ($y=0; $y -lt $crop.Height; $y++) {
     for ($x=0; $x -lt $crop.Width; $x++) {
      $c = $crop.GetPixel($x,$y)
      if ([Math]::Min($c.R,[Math]::Min($c.G,$c.B)) -lt 170 -or ([Math]::Max($c.R,[Math]::Max($c.G,$c.B))-[Math]::Min($c.R,[Math]::Min($c.G,$c.B))) -gt 35) {
       $crop.SetPixel($x,$y,[Drawing.Color]::Magenta)
      }
     }
    }
   }
   $crop.Save((Join-Path $target ($item[1]+'.png')), [Drawing.Imaging.ImageFormat]::Png)
  } finally { $crop.Dispose() }
 } finally { $source.Dispose() }
}
Write-Output "Saved $($items.Count) observed MCT templates"
