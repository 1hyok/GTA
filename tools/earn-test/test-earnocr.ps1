#Requires -Version 5.1
<#
Exercises the actual WinRT OCR helper using generated static PNGs.
No game input, window activation or screen capture. Invalid desktop bounds are
rejected before capture. Optionally also checks the earlier Vinewood screenshot.
#>
[CmdletBinding()]
param([string]$VinewoodSamplePath = '', [string]$StaffSampleDirectory = '')

$ErrorActionPreference = 'Stop'
$ocrScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Core\EarnOcr.ps1'))
$powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('gta-earn-ocr-test-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testDirectory)
$outputPath = Join-Path $testDirectory 'result.tsv'
$testCount = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-Ocr([string[]]$Arguments, [bool]$ShouldSucceed) {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powerShell
    # Paths are direct process arguments, never interpreted as PowerShell code.
    $allArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ocrScript) + $Arguments + @('-OutputPath', $outputPath)
    $startInfo.Arguments = ($allArguments | ForEach-Object {
        if ($_ -match '"') { throw 'Unexpected quote in a test argument.' }
        '"' + $_ + '"'
    }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'OCR test timed out.'
        }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($ShouldSucceed) {
            Assert-True ($process.ExitCode -eq 0 -and $stderr -eq '' -and [IO.File]::Exists($outputPath)) "OCR failed: exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
            $header = [IO.File]::ReadAllLines($outputPath)[0]
            Assert-True ($header -eq "x`ty`tw`th`ttext") 'Invalid TSV header.'
            return @(Import-Csv -LiteralPath $outputPath -Delimiter "`t" -Encoding UTF8)
        }
        Assert-True ($process.ExitCode -ne 0 -and -not [IO.File]::Exists($outputPath)) "Failure retained stale OCR output: exit=$($process.ExitCode) stderr=$stderr"
        Assert-True ($stderr -match '^EarnOcr:') "Missing OCR failure reason: $stderr"
    }
    finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

try {
    $parseTokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($ocrScript, [ref]$parseTokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "PowerShell syntax errors: $parseErrors"
    Add-Type -AssemblyName System.Drawing
    $fixture = Join-Path $testDirectory 'money.png'
    $bitmap = New-Object Drawing.Bitmap 1000, 450
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $font = New-Object Drawing.Font 'Segoe UI', 28, ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
    try {
        $graphics.Clear([Drawing.Color]::White)
        $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.DrawString('THE VINEWOOD CLUB APP', $font, [Drawing.Brushes]::Black, 80, 60)
        $graphics.DrawString('Nightclub Safe $250,000', $font, [Drawing.Brushes]::Black, 80, 130)
        $graphics.FillRectangle([Drawing.Brushes]::Black, 60, 200, 850, 100)
        $graphics.DrawString('Buy Supplies $75,000', $font, [Drawing.Brushes]::White, 80, 230)
        $bitmap.Save($fixture, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $font.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }

    $rows = @(Invoke-Ocr @('-ImagePath', $fixture) $true)
    $text = ($rows | ForEach-Object { $_.text }) -join ' | '
    Assert-True ($text -match 'THE VINEWOOD CLUB APP' -and $text -match '\$250,000' -and $text -match '\$75,000') "Header/amount recognition failed: $text"
    $safe = @($rows | Where-Object { $_.text -match '\$250,000' })
    Assert-True ($safe.Count -eq 1 -and [int]$safe[0].x -ge 80 -and [int]$safe[0].x -lt 600 -and [int]$safe[0].y -ge 130 -and [int]$safe[0].y -lt 170) 'Whole-image coordinates differ from the generated money line.'
    $testCount++
    Write-Output "PASS English header and black/white currency lines: $text"

    # WinRT reports word rectangles in its deskewed coordinate system. Rotating
    # the same fixture makes a missing TextAngle transform visibly displace them.
    $baseX = [double]$safe[0].x
    $baseY = [double]$safe[0].y
    $rotatedFixture = Join-Path $testDirectory 'rotated.png'
    $unrotated = [Drawing.Bitmap]::FromFile($fixture)
    $rotated = New-Object Drawing.Bitmap 1000, 450
    $rotatedGraphics = [Drawing.Graphics]::FromImage($rotated)
    try {
        $rotatedGraphics.Clear([Drawing.Color]::White)
        $rotatedGraphics.TranslateTransform(500, 225)
        $rotatedGraphics.RotateTransform(-10)
        $rotatedGraphics.TranslateTransform(-500, -225)
        $rotatedGraphics.DrawImage($unrotated, 0, 0, 1000, 450)
        $rotated.Save($rotatedFixture, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $rotatedGraphics.Dispose(); $rotated.Dispose(); $unrotated.Dispose() }
    $rows = @(Invoke-Ocr @('-ImagePath', $rotatedFixture) $true)
    $rotatedSafe = @($rows | Where-Object { $_.text -match '\$250,000' })
    $rotation = -10 * [Math]::PI / 180
    $expectedX = 500 + ($baseX - 500) * [Math]::Cos($rotation) - ($baseY - 225) * [Math]::Sin($rotation)
    $expectedY = 225 + ($baseX - 500) * [Math]::Sin($rotation) + ($baseY - 225) * [Math]::Cos($rotation)
    Assert-True ($rotatedSafe.Count -eq 1 -and [Math]::Abs([double]$rotatedSafe[0].x - $expectedX) -lt 8 -and [Math]::Abs([double]$rotatedSafe[0].y - $expectedY) -lt 8) "Rotated OCR coordinates do not map back to the image: expected $expectedX,$expectedY; actual $($rotatedSafe | ConvertTo-Json -Compress)"
    $testCount++
    Write-Output 'PASS rotated text coordinates return to original image pixels'

    $rows = @(Invoke-Ocr @('-ImagePath', $fixture, '-X', '60', '-Y', '100', '-W', '850', '-H', '220') $true)
    $safe = @($rows | Where-Object { $_.text -match '\$250,000' })
    Assert-True ($safe.Count -eq 1 -and [int]$safe[0].y -ge 130 -and [int]$safe[0].y -lt 170) 'Crop coordinates lost the original-image offset.'
    foreach ($row in $rows) {
        Assert-True ([int]$row.x -ge 60 -and [int]$row.x -le 910 -and [int]$row.y -ge 100 -and [int]$row.y -le 320 -and [int]$row.w -gt 0 -and [int]$row.h -gt 0) "Invalid OCR bounds: $row"
    }
    $testCount++
    Write-Output 'PASS cropped coordinates retain original image offsets'

    $whiteFixture = Join-Path $testDirectory 'white-footer.png'
    $bitmap = New-Object Drawing.Bitmap 900, 180
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $font = New-Object Drawing.Font 'Segoe UI', 28, ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
    $background = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(140, 150, 130))
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(50, 65, 70))
        $graphics.FillRectangle($background, 95, 0, 140, 160)
        $graphics.FillRectangle([Drawing.Brushes]::DimGray, 355, 0, 110, 160)
        $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.DrawString('Your Warehouse staff member is currently', $font, [Drawing.Brushes]::White, 30, 50)
        $graphics.DrawString('out on a job.', $font, [Drawing.Brushes]::White, 30, 95)
        $bitmap.Save($whiteFixture, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $background.Dispose(); $font.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
    $rows = @(Invoke-Ocr @('-ImagePath', $whiteFixture, '-X', '20', '-Y', '30', '-W', '850', '-H', '120', '-WhiteText') $true)
    $text = ($rows | ForEach-Object { $_.text }) -join ' '
    Assert-True ($text -ceq 'Your Warehouse staff member is currently out on a job.') "White-text footer recognition failed: $text"
    Assert-True ($rows.Count -eq 2 -and [int]$rows[0].y -ge 50 -and [int]$rows[0].y -le 85 -and [int]$rows[1].y -ge 95 -and [int]$rows[1].y -le 130) 'White-text preprocessing changed image coordinates.'
    $testCount++
    Write-Output 'PASS white footer over varied scenery with original-image coordinates'

    foreach ($failureArguments in @(
        @('-ImagePath', (Join-Path $testDirectory 'missing.png')),
        @('-ImagePath', $fixture, '-X', '990', '-Y', '0', '-W', '50', '-H', '50'),
        @('-ImagePath', $fixture, '-Scale', '0'),
        @('-X', '2147483647', '-Y', '0', '-W', '10', '-H', '10'),
        @('-X', '0', '-Y', '0', '-W', '0', '-H', '10')
    )) {
        [IO.File]::WriteAllText($outputPath, "x`ty`tw`th`ttext`n1`t1`t1`t1`tSTALE")
        Invoke-Ocr $failureArguments $false
        $testCount++
    }
    Write-Output 'PASS five invalid-input cases reject without leaving stale output'

    if ($VinewoodSamplePath) {
        $rows = @(Invoke-Ocr @('-ImagePath', $VinewoodSamplePath, '-X', '0', '-Y', '0', '-W', '470', '-H', '500') $true)
        $claim = @($rows | Where-Object { $_.text -eq 'Claim Business Earnings' })
        Assert-True ($claim.Count -eq 1 -and [int]$claim[0].x -ge 100 -and [int]$claim[0].x -le 220 -and [int]$claim[0].y -ge 165 -and [int]$claim[0].y -le 200) 'Known Vinewood screenshot did not match its Claim line and coordinates.'
        $testCount++
        Write-Output 'PASS actual Vinewood screenshot text and Claim coordinates'
    }
    if ($StaffSampleDirectory) {
        foreach ($sample in @(
            @('earn-bail-agents', 240, 'Send your Bail Office staff member out on a job.'),
            @('earn-bail-agent1-sent', 240, 'Your Bail Office staff member is currently out on a job.'),
            @('earn-cargo-warehouses', 354, 'Send your Warehouse staff member out on a job.'),
            @('earn-cargo-disabled', 354, 'There is no more room to store cargo for this property.'),
            @('earn-cargo-first-result', 354, 'Your Warehouse staff member is currently out on a job.')
        )) {
            $samplePath = Join-Path $StaffSampleDirectory ($sample[0] + '.png')
            $rows = @(Invoke-Ocr @('-ImagePath', $samplePath, '-X', '28', '-Y', [string]$sample[1], '-W', '434', '-H', '75', '-WhiteText') $true)
            $text = ($rows | ForEach-Object { $_.text }) -join ' '
            Assert-True ($text -ceq $sample[2]) "Actual staff footer mismatch ($($sample[0])): $text"
            Assert-True ($rows.Count -eq 2 -and [int]$rows[0].y -ge $sample[1] -and [int]$rows[1].y -lt $sample[1]+75) 'Actual staff footer coordinates escaped crop.'
            $testCount++
            Write-Output "PASS actual white-text footer: $($sample[0])"
        }
    }
    Write-Output "PASS EarnOcr cases=$testCount (no game input)"
}
finally {
    # Only explicit files created in this unique test directory are removed.
    foreach ($name in @('money.png', 'rotated.png', 'white-footer.png', 'result.tsv')) {
        $createdFile = Join-Path $testDirectory $name
        if ([IO.File]::Exists($createdFile)) { [IO.File]::Delete($createdFile) }
    }
    if ([IO.Directory]::Exists($testDirectory)) { [IO.Directory]::Delete($testDirectory, $false) }
}
