#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Destination)

$ErrorActionPreference = 'Stop'
$pin = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'autohotkey.json') -Raw | ConvertFrom-Json
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) {
    if (@(Get-ChildItem -LiteralPath $destinationPath -Force).Count) {
        throw 'Choose a new or empty destination for the portable AutoHotkey runtime.'
    }
} else {
    $null = New-Item -ItemType Directory -Path $destinationPath
}
$archive = Join-Path $destinationPath 'AutoHotkey.zip'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -Uri $pin.archiveUrl -OutFile $archive
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
if ($archiveHash -cne $pin.archiveSha256) { throw "AutoHotkey archive SHA256 mismatch: $archiveHash" }
# Extract only. Never execute Install.cmd or change the user's AHK installation.
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $destinationPath 'runtime')
$executable = Join-Path (Join-Path $destinationPath 'runtime') $pin.executable
$executableHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
if ($executableHash -cne $pin.executableSha256) { throw "AutoHotkey executable SHA256 mismatch: $executableHash" }
if ((Get-Item -LiteralPath $executable).VersionInfo.ProductVersion -ne $pin.version) {
    throw 'AutoHotkey executable version differs from the pin.'
}
[ordered]@{
    version = $pin.version
    releaseUrl = $pin.releaseUrl
    archiveSha256 = $archiveHash
    executableSha256 = $executableHash
    executable = $executable
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destinationPath 'installation.json') -Encoding UTF8
Write-Output $executable
