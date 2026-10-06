[CmdletBinding()]
param(
    [string]$OfficialScriptsZip = "F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip",
    [string]$ModRoot = ""
)

# Full-definition comparison between official `scripts/prefabs/skinprefabs.lua` and the
# mod mirror `scripts/prefabs/skinprefabs.lua`.
#
# Unlike `validate_skin_update.ps1 -SkinId`, which only inspects the blocks touched by the
# ids you name, this script compares every official definition. It reports three things:
#
#   1. name coverage      -- official names absent from the mirror, and mirror-only names
#   2. tracked field values -- value mismatches for the behaviour-bearing fields
#   3. field-name sets    -- blocks where official and mirror do not carry the same set of
#                            top-level fields at all
#
# Check 3 exists because a value comparison can only see the fields it is told about: a
# field that official has and the mirror omits entirely is invisible to check 2 unless it
# happens to be listed in `$semanticFields`. That is exactly how the `skin_sound` omission
# on `wx78_scanner_catcoon*` stayed hidden until it was looked for by name.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($ModRoot)) {
    $ModRoot = Split-Path -Parent $PSScriptRoot
}

$semanticFields = @(
    'base_prefab',
    'type',
    'rarity',
    'rarity_modifier',
    'build_name_override',
    'normal_skin',
    'ghost_skin',
    'share_bigportrait_name',
    'linked_skinname',
    'granted_items',
    'prefabs',
    'fx_prefab',
    'skin_tags',
    'skin_sound',
    'init_fn'
)

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

function Get-PrefabSkinBlockMap {
    param([string]$Text)

    $blocks = @{}
    $pattern = '(?ms)table\.insert\(prefs,\s*CreatePrefabSkin\("(?<name>[^"]+)"\s*,.*?^\s*\}\)\)\s*$'
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        # Keep the last definition because later duplicate entries are the runtime-relevant ones.
        $blocks[$match.Groups['name'].Value] = $match.Value
    }
    $blocks
}

function Get-SkinFieldSignature {
    param(
        [string]$Block,
        [string]$Field
    )

    $escapedField = [regex]::Escape($Field)
    $singleLineTable = [regex]::Match($Block, "(?m)^\s*$escapedField\s*=\s*\{(?<value>[^\r\n}]*)\}")
    if ($singleLineTable.Success) {
        $values = [regex]::Matches($singleLineTable.Groups['value'].Value, '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value }
        return ($values -join ',')
    }

    $multiLineTable = [regex]::Match($Block, "(?ms)^\s*$escapedField\s*=\s*\{(?<value>.*?)^\s*\},?\s*$")
    if ($multiLineTable.Success) {
        $values = [regex]::Matches($multiLineTable.Groups['value'].Value, '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value }
        return ($values -join ',')
    }

    $lineValue = [regex]::Match($Block, "(?m)^\s*$escapedField\s*=\s*(?<value>.+?)\s*$")
    if ($lineValue.Success) {
        return ($lineValue.Groups['value'].Value -replace '\s+', ' ').Trim().TrimEnd(',')
    }

    '<absent>'
}

function Get-TopLevelFieldNames {
    param([string]$Block)

    @([regex]::Matches($Block, '(?m)^\t([A-Za-z_][A-Za-z0-9_]*)\s*=') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique)
}

if (-not (Test-Path -LiteralPath $OfficialScriptsZip)) {
    throw "Official scripts.zip not found: $OfficialScriptsZip"
}

$officialText = Get-ZipEntryText -ZipPath $OfficialScriptsZip -EntryPath "scripts/prefabs/skinprefabs.lua"
$mirrorText = Get-Content -LiteralPath (Join-Path $ModRoot 'scripts\prefabs\skinprefabs.lua') -Raw
$customText = Get-Content -LiteralPath (Join-Path $ModRoot 'scripts\prefabs\kleiskinprefabs.lua') -Raw

$officialBlocks = Get-PrefabSkinBlockMap -Text $officialText
$mirrorBlocks = Get-PrefabSkinBlockMap -Text $mirrorText
$customBlocks = Get-PrefabSkinBlockMap -Text $customText

$problems = [Collections.Generic.List[string]]::new()

Write-Output ("OFFICIAL_BLOCKS=" + $officialBlocks.Count)
Write-Output ("MIRROR_BLOCKS=" + $mirrorBlocks.Count)

Write-Output "`n== Name coverage =="
$missingFromMirror = @($officialBlocks.Keys | Where-Object { -not $mirrorBlocks.ContainsKey($_) } | Sort-Object)
$mirrorOnly = @($mirrorBlocks.Keys | Where-Object { -not $officialBlocks.ContainsKey($_) } | Sort-Object)
if ($missingFromMirror.Count -eq 0 -and $mirrorOnly.Count -eq 0) {
    Write-Output "PASS: both layers define exactly the same $($officialBlocks.Count) skin names."
}
foreach ($name in $missingFromMirror) {
    $problems.Add("Official skin missing from mirror: $name")
    Write-Output "FAIL: official skin missing from mirror: $name"
}
foreach ($name in $mirrorOnly) {
    $problems.Add("Mirror-only skin name: $name")
    Write-Output "FAIL: mirror-only skin name: $name"
}

Write-Output "`n== Tracked field values =="
$fieldMismatches = 0
foreach ($name in ($officialBlocks.Keys | Sort-Object)) {
    if (-not $mirrorBlocks.ContainsKey($name)) {
        continue
    }

    foreach ($field in $semanticFields) {
        $officialValue = Get-SkinFieldSignature -Block $officialBlocks[$name] -Field $field
        $mirrorValue = Get-SkinFieldSignature -Block $mirrorBlocks[$name] -Field $field
        if ($officialValue -ne $mirrorValue) {
            $fieldMismatches++
            $problems.Add("Field mismatch: $name.$field")
            Write-Output "FAIL: $name.$field"
            Write-Output "        official=[$officialValue]"
            Write-Output "        mirror  =[$mirrorValue]"
        }
    }
}
if ($fieldMismatches -eq 0) {
    Write-Output "PASS: all $($semanticFields.Count) tracked fields match across $($officialBlocks.Count) definitions."
}

Write-Output "`n== Complete field-name sets =="
$fieldSetDiffs = [ordered]@{}
foreach ($name in ($officialBlocks.Keys | Sort-Object)) {
    if (-not $mirrorBlocks.ContainsKey($name)) {
        continue
    }

    $officialFields = Get-TopLevelFieldNames -Block $officialBlocks[$name]
    $mirrorFields = Get-TopLevelFieldNames -Block $mirrorBlocks[$name]
    foreach ($field in @($officialFields | Where-Object { $_ -notin $mirrorFields })) {
        $key = "official-only: $field"
        if (-not $fieldSetDiffs.Contains($key)) { $fieldSetDiffs[$key] = [Collections.Generic.List[string]]::new() }
        $fieldSetDiffs[$key].Add($name)
    }
    foreach ($field in @($mirrorFields | Where-Object { $_ -notin $officialFields })) {
        $key = "mirror-only: $field"
        if (-not $fieldSetDiffs.Contains($key)) { $fieldSetDiffs[$key] = [Collections.Generic.List[string]]::new() }
        $fieldSetDiffs[$key].Add($name)
    }
}
if ($fieldSetDiffs.Count -eq 0) {
    Write-Output "PASS: every mirrored block carries exactly the same top-level fields as official."
}
else {
    foreach ($key in $fieldSetDiffs.Keys) {
        $names = @($fieldSetDiffs[$key])
        $problems.Add("Field-set difference ($key) in $($names.Count) block(s)")
        Write-Output "FAIL: $key -> $($names.Count) block(s)"
        foreach ($name in $names) {
            Write-Output "        $name"
        }
    }
}

Write-Output "`n== skin_sound coverage in the custom layer =="
# A `skin_sound` on the mirror entry alone changes nothing at runtime: the custom layer is the
# active definition layer, so the sound table has to be repeated on the matching `custom_`
# entry or the sound is silently replaced by the default. Official `skin_sound` tables carry
# sound event paths, not build names, so they are copied over unchanged.
$officialWithSound = @($officialBlocks.Keys | Where-Object { $officialBlocks[$_] -match '(?m)^\tskin_sound\s*=' } | Sort-Object)
$customMissingSound = @()
$customNoCounterpart = @()
foreach ($name in $officialWithSound) {
    $customName = "custom_$name"
    if (-not $customBlocks.ContainsKey($customName)) {
        $customNoCounterpart += $name
        continue
    }
    if ($customBlocks[$customName] -notmatch '(?m)^\s*skin_sound\s*=') {
        $customMissingSound += $name
    }
}
Write-Output "official definitions declaring skin_sound: $($officialWithSound.Count)"
if ($customMissingSound.Count -eq 0) {
    Write-Output "PASS: every custom_ counterpart declares skin_sound too."
}
foreach ($name in $customMissingSound) {
    $problems.Add("Custom entry lacks skin_sound: custom_$name")
    Write-Output "FAIL: custom_$name declares no skin_sound while official does."
}
foreach ($name in $customNoCounterpart) {
    Write-Output "WARN: $name declares skin_sound but has no custom_ entry."
}

Write-Output "`n== Summary =="
Write-Output ("problems=" + $problems.Count)
if ($problems.Count -gt 0) {
    exit 1
}

Write-Output "DEFINITIONS_OK"
