[CmdletBinding()]
param(
    [string]$OfficialScriptsZip = "F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip",
    [string]$ModRoot = ""
)

# Category-map comparison between official `scripts/prefabskins.lua` and the mod
# `scripts/prefabskins.lua`.
#
# The name-coverage script only proves that every official skin exists somewhere in the mod.
# It cannot see a skin that was moved between prefab categories, or a category the mod never
# created, because those changes do not alter the set of skin names. This script compares the
# category -> members mapping instead.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($ModRoot)) {
    $ModRoot = Split-Path -Parent $PSScriptRoot
}

function Get-ZipEntryText {
    param(
        [string]$ZipPath,
        [string]$EntryPath
    )

    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $archive.Entries | Where-Object FullName -eq $EntryPath | Select-Object -First 1
        if (-not $entry) {
            throw "Zip entry not found: $EntryPath"
        }

        $reader = [IO.StreamReader]::new($entry.Open())
        try {
            $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Get-CategoryMap {
    param([string[]]$Lines)

    $map = [ordered]@{}
    $current = $null
    $inBody = $false

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]

        if (-not $inBody) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*$') {
                $candidate = $Matches[1]

                # Only treat the assignment as a category when the next code line opens a table.
                $next = $index + 1
                while ($next -lt $Lines.Count -and $Lines[$next] -match '^\s*(?:--.*)?$') { $next++ }
                if ($next -lt $Lines.Count -and $Lines[$next] -match '^\s*\{') {
                    $current = $candidate
                    $inBody = $true
                }
            }
            continue
        }

        if ($line -match '^\s*\}\s*,?\s*$') {
            if ($null -ne $current -and -not $map.Contains($current)) {
                $map[$current] = [Collections.Generic.List[string]]::new()
            }
            $current = $null
            $inBody = $false
            continue
        }

        foreach ($match in [regex]::Matches($line, '"([^"]+)"')) {
            if ($null -ne $current) {
                if (-not $map.Contains($current)) {
                    $map[$current] = [Collections.Generic.List[string]]::new()
                }
                $map[$current].Add($match.Groups[1].Value)
            }
        }
    }

    $map
}

if (-not (Test-Path -LiteralPath $OfficialScriptsZip)) {
    throw "Official scripts.zip not found: $OfficialScriptsZip"
}

$officialText = Get-ZipEntryText -ZipPath $OfficialScriptsZip -EntryPath "scripts/prefabskins.lua"
$modText = Get-Content -LiteralPath (Join-Path $ModRoot 'scripts\prefabskins.lua') -Raw

$officialMap = Get-CategoryMap -Lines ($officialText -split "`r?`n")
$modMap = Get-CategoryMap -Lines ($modText -split "`r?`n")

Write-Output ("OFFICIAL_CATEGORIES=" + $officialMap.Count)
Write-Output ("MOD_CATEGORIES=" + $modMap.Count)

$problems = [Collections.Generic.List[string]]::new()

foreach ($key in $officialMap.Keys) {
    if (-not $modMap.Contains($key)) {
        $problems.Add("Category missing from mod: $key")
        Write-Output "FAIL: category missing from mod: $key"
        continue
    }

    $officialMembers = @($officialMap[$key] | Sort-Object -Unique)
    $modMembers = @($modMap[$key] | Sort-Object -Unique)

    $missing = @($officialMembers | Where-Object { $_ -notin $modMembers })
    $extra = @($modMembers | Where-Object { $_ -notin $officialMembers })

    if ($missing.Count -gt 0) {
        $problems.Add("Members missing in category ${key}: $($missing -join ', ')")
        Write-Output "FAIL: members missing in ${key}: $($missing -join ', ')"
    }
    if ($extra.Count -gt 0) {
        $problems.Add("Members not in official category ${key}: $($extra -join ', ')")
        Write-Output "FAIL: members not in official ${key}: $($extra -join ', ')"
    }
}

foreach ($key in $modMap.Keys) {
    if (-not $officialMap.Contains($key)) {
        $problems.Add("Category only in mod: $key")
        Write-Output "FAIL: category only in mod: $key"
    }
}

Write-Output "`n== Summary =="
Write-Output ("problems=" + $problems.Count)
if ($problems.Count -gt 0) {
    exit 1
}

Write-Output "CATEGORIES_OK"
