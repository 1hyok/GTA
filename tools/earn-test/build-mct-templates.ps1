param(
 [string]$CaptureDir = (Join-Path $PSScriptRoot '..\..\docs\evidence\2026-09-27-mct'),
 [string]$OutputDir = (Join-Path $PSScriptRoot '..\..\Images\Earn\1920x1080'),
 [string[]]$Name = @()
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$target = [IO.Path]::GetFullPath($OutputDir)
if (-not [IO.Directory]::Exists($target)) { throw 'OutputDir must already exist.' }
$fixtures = Join-Path $PSScriptRoot 'mct-template-fixtures'
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
 @('mansion-dj-right','dj_rebook_10k_right',1337,557,103,57),
 @('mansion-dj-confirm','dj_confirm_solomun',605,505,710,56),
 @('mansion-dj-confirm-tale','dj_confirm_tale',595,505,730,56),
 @('mansion-dj-after','dj_resident',886,572,114,28),
 @('mansion-dj-right-after','dj_resident_right',1330,572,116,28),
 @('mansion-dj-after','nc_home',328,582,80,31),
 @('mct-seated-current','mct_seated_mansion',0,0,240,24)
)
foreach ($requested in $Name) {
 if (-not @($items | Where-Object { $_[1] -eq $requested }).Count) { throw "Unknown template: $requested" }
}
$saved = 0
foreach ($item in $items) {
 if ($Name.Count -and $Name -notcontains $item[1]) { continue }
 $sourceDirectory = if ($item[1] -eq 'mct_seated_mansion') { $fixtures } else { $CaptureDir }
 $source = [Drawing.Bitmap]::FromFile((Join-Path $sourceDirectory ($item[0]+'.png')))
 $comparison = $null
 try {
  if ($item[1] -in @('nc_dj_menu','nc_home','bunker_buy','bunker_confirm')) {
   $comparisonName = switch ($item[1]) {
    'bunker_buy' { 'bunker-buy-75000.png' }
    'bunker_confirm' { 'bunker-confirm-75000.png' }
    default { $item[1]+'-current.png' }
   }
   $comparison = [Drawing.Bitmap]::FromFile((Join-Path $fixtures $comparisonName))
  }
  $rect = New-Object Drawing.Rectangle ([int]$item[2]),([int]$item[3]),([int]$item[4]),([int]$item[5])
  $crop = $source.Clone($rect, $source.PixelFormat)
  try {
   $threshold = if ($item[1] -eq 'mct_seated_mansion') { 200 } else { 170 }
   if ($item[1] -ne 'bunker_page') {
    for ($y=0; $y -lt $crop.Height; $y++) {
     for ($x=0; $x -lt $crop.Width; $x++) {
      $c = $crop.GetPixel($x,$y)
      if ($null -ne $comparison) {
       # Stable glyph interiors across independently observed pages. Bunker
       # price widths move the centered label by a subpixel ($45,000/$75,000);
       # its antialias fringe needs variation 105. Keep both samples within 30.
       $other = $comparison.GetPixel($x,$y)
       $bright = $c.R -ge 200 -and $c.G -ge 200 -and $c.B -ge 200 -and $other.R -ge 200 -and $other.G -ge 200 -and $other.B -ge 200
       $stable = [Math]::Abs([int]$c.R-$other.R) -le 60 -and [Math]::Abs([int]$c.G-$other.G) -le 60 -and [Math]::Abs([int]$c.B-$other.B) -le 60
       if ($bright -and $stable) {
        $crop.SetPixel($x,$y,[Drawing.Color]::FromArgb([int](($c.R+$other.R)/2),[int](($c.G+$other.G)/2),[int](($c.B+$other.B)/2)))
       } else { $crop.SetPixel($x,$y,[Drawing.Color]::Magenta) }
      } elseif ([Math]::Min($c.R,[Math]::Min($c.G,$c.B)) -lt $threshold -or ([Math]::Max($c.R,[Math]::Max($c.G,$c.B))-[Math]::Min($c.R,[Math]::Min($c.G,$c.B))) -gt 35) {
       $crop.SetPixel($x,$y,[Drawing.Color]::Magenta)
      }
     }
    }
   }
   $crop.Save((Join-Path $target ($item[1]+'.png')), [Drawing.Imaging.ImageFormat]::Png)
   $saved++
  } finally { $crop.Dispose() }
 } finally { if ($null -ne $comparison) { $comparison.Dispose() }; $source.Dispose() }
}
Write-Output "Saved $saved observed MCT templates"
