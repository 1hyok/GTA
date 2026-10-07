# Shared read-only inventory for verification and packaging. No game scripts are loaded.
function Get-MacroInputs([string]$RepositoryRoot) {
    $files = @(Get-Item -LiteralPath (Join-Path $RepositoryRoot 'Main.ahk'), (Join-Path $RepositoryRoot 'README.md'))
    foreach ($directory in @('Core', 'Features', 'Images')) {
        $files += @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot $directory) -Recurse -File)
    }
    $inputs = @(foreach ($file in $files) {
        $relative = $file.FullName.Substring($RepositoryRoot.TrimEnd('\').Length + 1).Replace('\', '/')
        if ($relative -match '^(Main\.ahk|README\.md)$' -or
            $relative -match '^Core/.+\.(ahk|ps1)$' -or
            $relative -match '^Features/.+\.ahk$' -or
            $relative -match '^Images/.+\.(png|bmp|jpg|jpeg)$') {
            [pscustomobject]@{ path = $relative; source = $file.FullName }
        }
    })
    $inputs += [pscustomobject]@{
        path = 'Config.example.ini'; source = Join-Path $RepositoryRoot 'tools\ci\Config.example.ini'
    }
    # Sort-Object uses culture-sensitive comparison. Punctuation can compare
    # equal on Windows, leaving same-prefix paths dependent on enumeration order.
    # UTF-16 code-unit keys provide a deterministic ordinal order instead.
    return @($inputs | Sort-Object {
        $sortKey = -join ([char[]]$_.path | ForEach-Object { '{0:X4}' -f [int]$_ })
        $sortKey
    })
}

function Get-MacroHashes([string]$RepositoryRoot) {
    return @(foreach ($item in (Get-MacroInputs $RepositoryRoot)) {
        [ordered]@{ path = $item.path; sha256 = (Get-FileHash -LiteralPath $item.source -Algorithm SHA256).Hash }
    })
}
