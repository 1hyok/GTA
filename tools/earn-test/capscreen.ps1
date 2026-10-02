param([string]$Name = "cap", [int]$X = 1920, [int]$Y = 0, [int]$W = 2560, [int]$H = 1600, [double]$Scale = 0.5)
# Compatibility entry point for existing manual capture commands.
& (Join-Path $PSScriptRoot '..\..\Core\ScreenCapture.ps1') @PSBoundParameters
