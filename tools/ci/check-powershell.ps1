#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

$ErrorActionPreference = 'Stop'
$files = @(foreach ($directory in @('Core', 'tools')) {
    Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot $directory) -Filter '*.ps1' -Recurse -File
})
$failures = @()
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($errorItem in $parseErrors) {
        $failures += [ordered]@{ file = $file.FullName; line = $errorItem.Extent.StartLineNumber; message = $errorItem.Message }
    }
}
[ordered]@{ files = $files.Count; errors = @($failures) } | ConvertTo-Json -Depth 4
if ($failures.Count) { exit 1 }
