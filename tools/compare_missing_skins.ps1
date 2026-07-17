[CmdletBinding()]
param(
    [string]$OfficialScriptsZip = "F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip",
    [string]$ModRoot = ""
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ModRoot)) {
    $ModRoot = Split-Path -Parent $PSScriptRoot
}

$modPrefabMirror = Join-Path $ModRoot "scripts\prefabs\skinprefabs.lua"
$modPrefabCustom = Join-Path $ModRoot "scripts\prefabs\kleiskinprefabs.lua"
$modClothing = Join-Path $ModRoot "scripts\clothing_curios.lua"

function Get-ZipEntryText {
    param(
        [string]$ZipPath,
        [string]$EntryPath
    )

    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq $EntryPath }
        if (-not $entry) {
            throw "Zip entry not found: $EntryPath"
        }

        $reader = New-Object IO.StreamReader($entry.Open())
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Normalize-Name {
    param([string]$Name)

    if ($Name.StartsWith("custom_")) {
        return $Name.Substring(7)
    }

    return $Name
}

function Get-PrefabSkinNamesFromText {
    param([string]$Text)

    $matches = [regex]::Matches($Text, 'CreatePrefabSkin\("([^"]+)"')
    foreach ($match in $matches) {
        $match.Groups[1].Value
    }
}

function Get-TopLevelKeysFromText {
    param([string]$Text)

    $matches = [regex]::Matches($Text, '(?m)^\s*([A-Za-z0-9_]+)\s*=')
    foreach ($match in $matches) {
        $match.Groups[1].Value
    }
}

function Get-TopLevelKeysFromFile {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    Get-TopLevelKeysFromText $text
}

function Get-PrefabSkinNamesFromFile {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    Get-PrefabSkinNamesFromText $text
}

if (-not (Test-Path -LiteralPath $OfficialScriptsZip)) {
    throw "Official scripts.zip not found: $OfficialScriptsZip"
}

$officialPrefabText = Get-ZipEntryText -ZipPath $OfficialScriptsZip -EntryPath "scripts/prefabs/skinprefabs.lua"
$officialClothingText = Get-ZipEntryText -ZipPath $OfficialScriptsZip -EntryPath "scripts/clothing.lua"

$officialPrefabNames = Get-PrefabSkinNamesFromText $officialPrefabText | Sort-Object -Unique
$modPrefabNames = @(
    Get-PrefabSkinNamesFromFile $modPrefabMirror
    Get-PrefabSkinNamesFromFile $modPrefabCustom | ForEach-Object { Normalize-Name $_ }
) | Sort-Object -Unique

$missingPrefabNames = Compare-Object -ReferenceObject $officialPrefabNames -DifferenceObject $modPrefabNames -PassThru |
    Where-Object { $_ -in $officialPrefabNames } |
    Sort-Object -Unique

$officialClothingNames = Get-TopLevelKeysFromText $officialClothingText | Sort-Object -Unique
$modClothingNames = Get-TopLevelKeysFromFile $modClothing | ForEach-Object { Normalize-Name $_ } | Sort-Object -Unique

$missingClothingNames = Compare-Object -ReferenceObject $officialClothingNames -DifferenceObject $modClothingNames -PassThru |
    Where-Object { $_ -in $officialClothingNames } |
    Sort-Object -Unique

Write-Output ("OFFICIAL_PREFAB_SKINS=" + $officialPrefabNames.Count)
Write-Output ("MOD_PREFAB_SKINS_NORMALIZED=" + $modPrefabNames.Count)
Write-Output ("MISSING_PREFAB_SKINS=" + $missingPrefabNames.Count)
Write-Output ""
Write-Output "Missing official prefab skin names:"
$missingPrefabNames | ForEach-Object { Write-Output ("- " + $_) }

Write-Output ""
Write-Output ("OFFICIAL_CLOTHING_KEYS=" + $officialClothingNames.Count)
Write-Output ("MOD_CLOTHING_KEYS_NORMALIZED=" + $modClothingNames.Count)
Write-Output ("MISSING_CLOTHING_KEYS=" + $missingClothingNames.Count)
Write-Output ""
Write-Output "Missing official clothing-side names:"
$missingClothingNames | ForEach-Object { Write-Output ("- " + $_) }
