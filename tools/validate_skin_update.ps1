[CmdletBinding()]
param(
    [string[]]$SkinId = @(),
    [string]$OfficialScriptsZip = "F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$modRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
$SkinId = @($SkinId | ForEach-Object { $_ -split ',' } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
    Write-Output "FAIL: $Message"
}

function Add-Warning {
    param([string]$Message)
    $warnings.Add($Message)
    Write-Output "WARN: $Message"
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

function Get-DuplicateSkinNames {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    [regex]::Matches($text, 'CreatePrefabSkin\("([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value -replace '^custom_', '' } |
        Group-Object |
        Where-Object Count -gt 1
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

function Get-DynamicAssetPaths {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        $text = Get-Content -LiteralPath $path -Raw
        [regex]::Matches($text, 'Asset\("DYNAMIC_ANIM",\s*"([^"]+)"\)') |
            ForEach-Object { $_.Groups[1].Value }
    }
}

function Get-AllAssetPaths {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        $text = Get-Content -LiteralPath $path -Raw
        [regex]::Matches($text, 'Asset\("(?:DYNAMIC_ANIM|PKGREF)",\s*"([^"]+)"\)') |
            ForEach-Object { $_.Groups[1].Value }
    }
}

function Get-BuildNameFromDynamicZip {
    param([string]$Path)

    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $archive.Entries |
            Where-Object { $_.FullName -eq 'build.bin' -or $_.FullName.EndsWith('/build.bin') } |
            Select-Object -First 1
        if (-not $entry) {
            throw "build.bin not found"
        }

        $stream = $entry.Open()
        try {
            $memory = [IO.MemoryStream]::new()
            try {
                $stream.CopyTo($memory)
                $data = $memory.ToArray()
            }
            finally {
                $memory.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }

        if ($data.Length -lt 20 -or [Text.Encoding]::ASCII.GetString($data, 0, 4) -ne 'BILD') {
            throw "invalid BILD header"
        }

        $nameLength = [BitConverter]::ToInt32($data, 0x10)
        if ($nameLength -lt 1 -or 0x14 + $nameLength -gt $data.Length) {
            throw "invalid build name length"
        }

        [Text.Encoding]::ASCII.GetString($data, 0x14, $nameLength)
    }
    finally {
        $archive.Dispose()
    }
}

Push-Location $modRoot
try {
    Write-Output "== Normalized coverage =="
    $coverageScript = Join-Path $PSScriptRoot 'compare_missing_skins.ps1'
    if (-not (Test-Path -LiteralPath $coverageScript)) {
        Add-Failure "Missing coverage script: $coverageScript"
    }
    else {
        $coverageOutput = & $coverageScript -OfficialScriptsZip $OfficialScriptsZip -ModRoot $modRoot
        $coverageOutput | ForEach-Object { Write-Output $_ }
        $coverageText = $coverageOutput -join "`n"

        if ($coverageText -notmatch 'MISSING_PREFAB_SKINS=0(?:\r?\n|$)') {
            Add-Failure "Normalized prefab coverage is not complete."
        }

        if ($coverageText -notmatch 'MISSING_CLOTHING_KEYS=5(?:\r?\n|$)') {
            Add-Failure "Clothing residual count is not the expected five structural keys."
        }

        foreach ($structuralKey in @('CLOTHING', 'CLOTHING_SFX', 'CLOTHING_SYMBOLS', 'footstep_layered', 'HIDE_SYMBOLS')) {
            if ($coverageText -notmatch "(?m)^- $([regex]::Escape($structuralKey))$") {
                Add-Failure "Expected structural clothing key is absent: $structuralKey"
            }
        }
    }

    Write-Output "`n== PREFAB_SKINS table structure =="
    $prefabSkinsPath = Join-Path $modRoot 'scripts\prefabskins.lua'
    $prefabLines = Get-Content -LiteralPath $prefabSkinsPath
    $badTableStarts = 0
    for ($index = 0; $index -lt $prefabLines.Count; $index++) {
        if ($prefabLines[$index] -notmatch '^\s*[A-Za-z_][A-Za-z0-9_]*\s*=\s*$') {
            continue
        }

        $next = $index + 1
        while ($next -lt $prefabLines.Count -and $prefabLines[$next] -match '^\s*(?:--.*)?$') {
            $next++
        }

        if ($next -ge $prefabLines.Count -or $prefabLines[$next] -notmatch '^\s*\{') {
            $badTableStarts++
            Add-Failure "Malformed table assignment near scripts/prefabskins.lua:$($index + 1)"
        }
    }
    if ($badTableStarts -eq 0) {
        Write-Output "PASS: prefabskin table starts are structurally valid."
    }

    Write-Output "`n== Duplicate prefab definitions =="
    $knownDuplicateNames = @(
        'researchlab2_science_resurrected',
        'wx78_ancient',
        'wx78_dronezap_gothic',
        'wx78_dronezap_gothic_overlay',
        'wx78_dronezap_jewelbox',
        'wx78_dronezap_jewelbox_overlay',
        'wx78_dronezapremote_gothic',
        'wx78_dronezapremote_jewelbox',
        'wx78_moduleremover_gothic',
        'wx78_moduleremover_jewelbox',
        'wx78_scanner_gothic',
        'wx78_scanner_gothic_item',
        'wx78_scanner_jewelbox',
        'wx78_scanner_jewelbox_item',
        'wx78_scanner_succeeded_gothic',
        'wx78_scanner_succeeded_jewelbox'
    )
    $prefabDefinitionFiles = @(
        (Join-Path $modRoot 'scripts\prefabs\skinprefabs.lua'),
        (Join-Path $modRoot 'scripts\prefabs\kleiskinprefabs.lua')
    )
    foreach ($path in $prefabDefinitionFiles) {
        $duplicates = @(Get-DuplicateSkinNames -Path $path)
        $unexpected = @($duplicates | Where-Object { $_.Name -notin $knownDuplicateNames -or $_.Count -ne 2 })
        if ($unexpected.Count -gt 0) {
            foreach ($duplicate in $unexpected) {
                Add-Failure "Unexpected duplicate in $([IO.Path]::GetFileName($path)): $($duplicate.Name) x$($duplicate.Count)"
            }
        }

        $knownPresent = @($duplicates | Where-Object Name -in $knownDuplicateNames)
        if ($knownPresent.Count -gt 0) {
            Add-Warning "$([IO.Path]::GetFileName($path)) retains $($knownPresent.Count) known historical duplicate names."
        }
        else {
            Write-Output "PASS: no duplicate prefab definitions in $([IO.Path]::GetFileName($path))."
        }
    }

    Write-Output "`n== Asset references =="
    $assetSourceFiles = @(
        (Join-Path $modRoot 'scripts\prefabs\kleiskinprefabs.lua'),
        (Join-Path $modRoot 'scripts\clothing_curios.lua')
    )
    $assetPaths = @(Get-AllAssetPaths -Paths $assetSourceFiles | Sort-Object -Unique)
    $missingAssets = 0
    foreach ($assetPath in $assetPaths) {
        $resolvedPath = Join-Path $modRoot ($assetPath -replace '/', '\')
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            $missingAssets++
            Add-Failure "Missing asset reference: $assetPath"
        }
    }
    if ($missingAssets -eq 0) {
        Write-Output "PASS: all $($assetPaths.Count) DYNAMIC_ANIM/PKGREF references exist."
    }

    Write-Output "`n== Dynamic zip build names =="
    $dynamicZipPaths = @(Get-DynamicAssetPaths -Paths $assetSourceFiles | Where-Object { $_.EndsWith('.zip') } | Sort-Object -Unique)
    $badBuildNames = 0
    foreach ($assetPath in $dynamicZipPaths) {
        $resolvedPath = Join-Path $modRoot ($assetPath -replace '/', '\')
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            continue
        }

        $expectedName = [IO.Path]::GetFileNameWithoutExtension($resolvedPath)
        try {
            $actualName = Get-BuildNameFromDynamicZip -Path $resolvedPath
            if ($actualName -ne $expectedName) {
                $badBuildNames++
                Add-Failure "Build name mismatch: $assetPath expected=$expectedName actual=$actualName"
            }
        }
        catch {
            $badBuildNames++
            Add-Failure "Cannot validate $assetPath ($($_.Exception.Message))"
        }
    }
    if ($badBuildNames -eq 0) {
        Write-Output "PASS: all $($dynamicZipPaths.Count) dynamic zip build names match their filenames."
    }

    if ($SkinId.Count -gt 0) {
        Write-Output "`n== Official reverse references =="
        if (-not (Test-Path -LiteralPath $OfficialScriptsZip)) {
            Add-Failure "Official scripts.zip not found: $OfficialScriptsZip"
        }
        else {
            $officialEntries = @(
                'scripts/prefabskins.lua',
                'scripts/prefabs/skinprefabs.lua',
                'scripts/clothing.lua',
                'scripts/prefabskin.lua',
                'scripts/skin_affinity_info.lua'
            )
            $officialTexts = @{}
            foreach ($entry in $officialEntries) {
                $officialTexts[$entry] = Get-ZipEntryText -ZipPath $OfficialScriptsZip -EntryPath $entry
            }

            $officialBlocks = Get-PrefabSkinBlockMap -Text $officialTexts['scripts/prefabs/skinprefabs.lua']
            $mirrorText = Get-Content -LiteralPath (Join-Path $modRoot 'scripts\prefabs\skinprefabs.lua') -Raw
            $mirrorBlocks = Get-PrefabSkinBlockMap -Text $mirrorText
            $blocksToCompare = [Collections.Generic.HashSet[string]]::new()

            foreach ($id in $SkinId) {
                Write-Output "References for ${id}:"
                $referenceCount = 0
                foreach ($entry in $officialEntries) {
                    $lines = $officialTexts[$entry] -split "`r?`n"
                    for ($index = 0; $index -lt $lines.Count; $index++) {
                        if ($lines[$index].Contains($id)) {
                            $referenceCount++
                            Write-Output "  $entry`:$($index + 1): $($lines[$index].Trim())"
                        }
                    }
                }
                if ($referenceCount -eq 0) {
                    Add-Warning "No official reverse references found for $id."
                }

                foreach ($blockName in $officialBlocks.Keys) {
                    if ($officialBlocks[$blockName].Contains($id)) {
                        [void]$blocksToCompare.Add($blockName)
                    }
                }
            }

            Write-Output "`n== Referenced existing-definition fields =="
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
                'init_fn'
            )
            foreach ($blockName in @($blocksToCompare) | Sort-Object) {
                if (-not $mirrorBlocks.ContainsKey($blockName)) {
                    Add-Failure "Official referenced skin is missing from mirror block map: $blockName"
                    continue
                }

                $blockFailuresBefore = $failures.Count
                foreach ($field in $semanticFields) {
                    $officialValue = Get-SkinFieldSignature -Block $officialBlocks[$blockName] -Field $field
                    $mirrorValue = Get-SkinFieldSignature -Block $mirrorBlocks[$blockName] -Field $field
                    if ($officialValue -ne $mirrorValue) {
                        Add-Failure "Mirror field mismatch: $blockName.$field official=[$officialValue] mirror=[$mirrorValue]"
                    }
                }
                if ($failures.Count -eq $blockFailuresBefore) {
                    Write-Output "PASS: $blockName key fields match the official definition."
                }
            }
        }
    }

    Write-Output "`n== Version and Git preflight =="
    $modInfoText = Get-Content -LiteralPath (Join-Path $modRoot 'modinfo.lua') -Raw
    $versionMatch = [regex]::Match($modInfoText, '(?m)^version\s*=\s*"(V\d+\.\d+\.\d+)"\s*$')
    if (-not $versionMatch.Success) {
        Add-Failure "modinfo.lua version must use V<major>.<minor>.<patch>."
    }
    else {
        $currentVersion = $versionMatch.Groups[1].Value
        Write-Output "Current version: $currentVersion"

        $headModInfo = git show HEAD:modinfo.lua 2>$null
        $headVersionMatch = [regex]::Match(($headModInfo -join "`n"), '(?m)^version\s*=\s*"(V\d+\.\d+\.\d+)"\s*$')
        $skinChanges = @(git status --porcelain -- scripts anim)
        if ($skinChanges.Count -gt 0 -and $headVersionMatch.Success -and $headVersionMatch.Groups[1].Value -eq $currentVersion) {
            Add-Failure "Skin/code changes exist but modinfo.lua version was not bumped from HEAD."
        }
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $diffCheck = @(git diff --check 2>&1)
    $diffCheckExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($diffCheckExitCode -ne 0) {
        $diffCheck | ForEach-Object { Write-Output $_ }
        Add-Failure "git diff --check reported whitespace errors."
    }
    else {
        Write-Output "PASS: git diff --check"
    }

    $stagedPaths = @(git diff --cached --name-only)
    $forbiddenStagedPaths = @(
        'CLAUDE_GUIDE.md',
        'blog.md'
    )
    $forbiddenStaged = @($stagedPaths | Where-Object { $_ -in $forbiddenStagedPaths })
    if ($forbiddenStaged.Count -gt 0) {
        foreach ($path in $forbiddenStaged) {
            Add-Failure "Ignored local note is staged: $path"
        }
    }
    elseif ($stagedPaths.Count -eq 0) {
        Write-Output "PASS: nothing is staged yet."
    }
    else {
        Write-Output "Staged paths:"
        $stagedPaths | ForEach-Object { Write-Output "  $_" }
    }

    Write-Output "`n== Summary =="
    Write-Output "warnings=$($warnings.Count)"
    Write-Output "failures=$($failures.Count)"
    if ($failures.Count -gt 0) {
        exit 1
    }

    Write-Output "VALIDATION_OK"
}
finally {
    Pop-Location
}
