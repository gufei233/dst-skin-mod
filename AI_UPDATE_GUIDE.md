# DST Skin Mod AI Guide

## Goal

This guide is for any future AI or engineer taking over `E:\Desktop\skin`.

It explains:

1. What this mod is doing.
2. Which files actually matter.
3. How to compare the mod against official DST skin data after a game update.
4. How to safely add newly added official skins into the mod.
5. Which mistakes are most likely to break the mod.

This guide is based on the tracked validation tools, completed update history, and direct code inspection of the current repository. It is intended to be self-contained.

## Project Summary

This mod is not a normal content-only skin pack.

It is a skin-system injector that:

- mirrors official DST skin data structures
- remaps many official skin IDs into a local `custom_` namespace
- fakes ownership checks so local skins behave like owned skins
- injects skin application into prefab spawn and reskin flow
- registers clothing and misc curios into runtime global tables

The key architectural fact is:

The mod keeps official naming semantics, but runtime-active local skins are mostly `custom_` copies or replacements of official skins.

## Official Data Location

Official source used by this project:

- `F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip`

Related asset locations:

- `F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\anim_dynamic.zip`
- `F:\SteamLibrary\steamapps\common\Don't Starve Together\data\anim\dynamic\`

The scripts use these locations as defaults. If DST is installed elsewhere, pass `-OfficialScriptsZip <path>` to either helper. `compare_missing_skins.ps1` also accepts `-ModRoot <path>`; otherwise it derives the repository root from its own `tools` directory.

## Mod Files That Matter

Core runtime entry:

- `modmain.lua`
- `localskinmain.lua`
- `skinloader\skinloader.lua`

Data files:

- `scripts\prefabskins.lua`
- `scripts\prefabs\skinprefabs.lua`
- `scripts\prefabs\kleiskinprefabs.lua`
- `scripts\clothing_curios.lua`
- `scripts\misc_curios.lua`

Assets:

- `anim\dynamic\*.zip`
- `anim\dynamic\*.dyn`

Tracked workflow files and helper scripts:

- `AI_UPDATE_GUIDE.md`
- `tools\compare_missing_skins.ps1`
- `tools\validate_skin_update.ps1`

These files are part of the public repository and must be kept synchronized with workflow changes. `CLAUDE_GUIDE.md` and `blog.md` remain local-only notes and must not be force-added.

## Runtime Model You Must Understand First

### `custom_` prefix model

The mod uses `custom_` as the canonical prefix for local replacement skin IDs.

Examples:

- official: `wilson_formal`
- mod: `custom_wilson_formal`

- official: `body_buttons_black_jet`
- mod: `custom_body_buttons_black_jet`

The prefix is stripped at several query points so the game can reuse official text, rarity, icon, and ownership semantics.

### `skinloader\skinloader.lua`

This file is the core engine hook. It does several critical things:

1. Proxies skin display lookups like `GetSkinName`, `GetSkinDescription`, `GetSkinInvIconName`.
2. Hooks ownership functions like `InventoryProxy.CheckOwnership`.
3. Registers custom clothing and misc curios into runtime global tables.
4. Hooks `CreatePrefabSkin(...)` so `custom_` skins become runtime-usable prefab skins.
5. Hooks `SpawnPrefab`, `Sim:ReskinEntity`, and `AnimState:GetSkinBuild` so local skins can actually render.

If a new skin exists in data files but is not rendering or not treated as owned, this file is where the behavior chain starts.

### `localskinmain.lua`

This file loads mod curios into `_ModdedCurios` from:

- `scripts\clothing_curios.lua`
- `scripts\misc_curios.lua`

It also sets:

- `PrefabFiles = { "kleiskinprefabs" }`

That means `kleiskinprefabs.lua` is the active custom prefab skin registry.

### Important distinction: mirror layer vs active custom layer

The mod keeps two prefab skin layers:

- `scripts\prefabs\skinprefabs.lua`
  This is the near-official mirror layer.
- `scripts\prefabs\kleiskinprefabs.lua`
  This is the active custom remap layer used by the mod.

When adding newly supported official skins, you must update **both** files, not just one.

#### Structural differences between the two layers

| Aspect | Mirror (`skinprefabs.lua`) | Custom (`kleiskinprefabs.lua`) |
|---|---|---|
| `assets` block | **None in this repo's mirror file.** Piggybacks on official game data. | Present when the custom entry uses local animation files. Reuse/variant entries may omit assets and point at another custom build. |
| `build_name_override` | Preserve the official field exactly when official uses it. Many `_p`, item, builder, and variant entries reuse another build this way. | Usually custom-prefixed when the runtime build is local custom data; reuse/variant entries should point at the custom-prefixed reused build. |
| `init_fn` signature | Usually `function(inst, skin_custom) backpack_init_fn(inst, "<name>", skin_custom) end` -- two params, forwards `skin_custom` when official does. | Usually `function(inst) backpack_init_fn(inst, "custom_<name>") end` -- one param, build name hardcoded; keep extra args only where an existing local pattern needs them. |
| `release_group` | **Hardcoded numeric literal** matching official Klei ID (e.g. `78`, `179`). | **Shared variable** `groupid` for all entries. |

The mirror layer is a lightweight catalogue that tracks official data shape. The custom layer is the mod's active runtime definition layer: many entries bundle local assets, while reuse/variant entries may instead point at an existing custom build without declaring their own `assets` block.

## Asset File Model

### `.zip` files

Contain texture atlas and build metadata (`build.bin`). The `build.bin` has an internal build name string that **must match** the runtime build name used by the mod.

When copying from official assets, the internal name is the official name (e.g. `backpack_invisible`). If the mod runtime references `custom_backpack_invisible`, the `build.bin` must be patched.

### `.dyn` files

Contain animation frame/timeline/bone data in a proprietary binary format. They do **not** embed the build name and do **not** need patching.

The mod simply copies official `.dyn` files verbatim and renames them with the `custom_` prefix. Binary comparison confirms they are byte-for-byte identical to their official counterparts.

### Pairing rules

Almost every `.dyn` has a matching `.zip` of the same name. A small number of `.dyn` files (~94) exist without a `.zip` pair (credits, quagmire food, oddments). These are animations the mod includes for reference resolution but does not reskin.

## Current Known Diff State

Last checked: 2026-08-30

- official prefab skin count (normalized): `1736`
- mod prefab skin count (normalized): `1736`
- official clothing key count: `1136`
- mod clothing key count (normalized): `1133`
- official `scripts.zip` timestamp: `2026-08-14 22:10:55`
- current update release group: `184`
- latest check result: no official prefab or clothing skin delta detected

From `compare_missing_skins.ps1` normalized-name comparison:

Missing official prefab skin names: **none** (0)

Missing official clothing-side names (non-actionable structural keys):

- `CLOTHING`
- `CLOTHING_SFX`
- `CLOTHING_SYMBOLS`
- `footstep_layered`
- `HIDE_SYMBOLS`

These five are **not** actual wearable clothing skins. They are top-level constants and utility definitions in official `clothing.lua`. They do not need to be replicated in the mod.

Important interpretation:

The static count gap between mirror and custom layers does not automatically mean the mod is missing actual skin IDs. The normalized diff is authoritative for name coverage only. It does not detect changed fields in an existing official definition.

## Current Repository Caveats

- As of 2026-07-17, the duplicate category blocks in `prefabskins.lua` have been cleaned, but duplicate `CreatePrefabSkin(...)` names still remain in `skinprefabs.lua` and `kleiskinprefabs.lua`. The validator allows the current 16-name historical baseline but fails on any new duplicate. Before editing an existing skin, search both the official name and the `custom_` name globally and modify every runtime-relevant duplicate consistently.
- The custom layer is not guaranteed to be fully self-contained per entry. Some `custom_*` entries intentionally reuse another custom build and therefore omit `assets` and/or point `build_name_override` at an existing custom build.
- For coverage checks, trust the normalized diff tooling over raw `CreatePrefabSkin(...)` counts. Raw counts can drift because of mirror/custom structure and historical duplicate blocks.
- When converting between official and custom-prefixed names, use the helper methods already used by `skinloader` (`start_with_that_prefix()` / `trip_that_prefix()`) rather than manual substring logic. Manual slicing previously caused broken string fallback lookups.

## Standard Workflow: Check Whether Official Skin Data Updated

Use this whenever DST updates.

### Step 1: Confirm official source files still exist

Check:

- `scripts.zip`
- `anim_dynamic.zip`
- `data\anim\dynamic\`

If paths changed, update local tooling before doing any diff work.

Record the `LastWriteTime` and size of `scripts.zip` and `anim_dynamic.zip` in the update notes. This identifies the exact local official data used for the comparison and prevents an older cached extraction from being mistaken for current data.

### Step 2: Re-run the normalized diff script

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\compare_missing_skins.ps1
```

This gives you the official-to-mod name diff for:

- prefab skin names
- clothing-side top-level names

This is the fastest first-pass answer to: "Did official add something we do not yet cover?"

This is a name-coverage check, not a semantic update check. A result of `MISSING_PREFAB_SKINS=0` does not prove existing definitions, helper functions, or relationships are still current.

### Step 3: Re-check structural counts

If needed, compare these again:

- top-level category count in `scripts/prefabskins.lua`
- official `CreatePrefabSkin(...)` count
- mod mirror `CreatePrefabSkin(...)` count
- mod custom `CreatePrefabSkin(...)` count
- clothing entry count or normalized clothing key count

Use counts only as a signal, not as the final truth.

Also check whether duplicate definitions are inflating the raw totals. A count increase by itself does not prove new official coverage was added.

### Step 4: Check changed existing definitions and reverse references

Official updates can change an existing skin without adding a new ID. Compare the current official definitions against the local mirror for behavior-bearing fields, especially:

- `granted_items`
- `build_name_override`
- `normal_skin`, `ghost_skin`, and `share_bigportrait_name`
- `init_fn`
- `prefabs` and `fx_prefab`
- `linked_skinname`
- `skins` and variant mappings
- helper functions in `scripts/prefabskin.lua`

For every newly missing skin ID, search the official source files for all references to that ID, not only its own `CreatePrefabSkin(...)` block. This reverse-reference check finds existing parent skins, bundles, variants, or helpers that must also change.

Use the unified validator with the new official IDs to print relevant official references and compare key fields in every referenced `CreatePrefabSkin(...)` block against the local mirror:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate_skin_update.ps1 -SkinId walrushat_minigolf_green,walrushat_minigolf_purple,walrushat_minigolf_red
```

The July 2026 update demonstrated why this is mandatory: the three new `walrushat_minigolf_*` definitions were visible in the normalized diff, but the changed `granted_items` on the existing `tophat_minigolf_*` definitions was not.

### Step 5: Inspect official new entries directly from `scripts.zip`

If the normalized diff shows new names, inspect these official files:

- `scripts/prefabskins.lua`
- `scripts/prefabs/skinprefabs.lua`
- `scripts/clothing.lua`
- `scripts/prefabskin.lua`
- `scripts/skin_affinity_info.lua`

For each new official entry, determine:

1. Is it a prefab skin or a clothing skin?
2. Is it a base skin or item skin?
3. Does it have its own `assets` block?
4. Does it reuse another build via `build_name_override`?
5. Does it need an `init_fn`?
6. Does it reference granted items or alternate variants?
7. Does it require new `.zip` and `.dyn` files?

### Step 6: Decide whether the mod should mirror or actively support the new content

There are two different tasks:

1. Updating the official mirror structure.
2. Making the skin actually usable in this mod.

Do not assume these are the same operation.

For active support, you must update the custom layer and assets, not just copy the official mirror line.

## Standard Workflow: Add a Newly Added Official Prefab Skin

This is for entries that appear in official `scripts/prefabs/skinprefabs.lua`.

### Step 1: Locate the official definition

Read the exact official `CreatePrefabSkin(...)` entry and copy its behavior, not just its name.

You must capture:

- skin ID
- `base_prefab`
- `type`
- `rarity`
- `rarity_modifier`
- `release_group`
- `skin_tags`
- `ghost_skin`
- `normal_skin`
- `share_bigportrait_name`
- `build_name_override`
- `idle_events`
- `init_fn`
- `granted_items`
- `assets`

Before editing local files, search the exact official skin ID and the future `custom_` skin ID across:

- `scripts\prefabskins.lua`
- `scripts\prefabs\skinprefabs.lua`
- `scripts\prefabs\kleiskinprefabs.lua`

This repository still has historical duplicate definitions, so you must confirm whether you are adding a new entry or editing an existing duplicated one.

### Step 2: Add or update `scripts\prefabskins.lua` if category membership changed

If the official update introduced a brand new prefab category or added a new skin under an existing prefab category, update `scripts\prefabskins.lua` to keep the category map aligned.

The category list should keep official naming, not `custom_` names.

### Step 3: Add the mirror entry in `scripts\prefabs\skinprefabs.lua`

Add the official-shaped `CreatePrefabSkin(...)` entry at the correct alphabetical position.

The mirror entry should:

- use the official skin name (no `custom_` prefix)
- have no `assets` block in this repo's mirror file
- preserve official `build_name_override` exactly when official has one
- use the official `init_fn` shape, usually `function(inst, skin_custom) xxx_init_fn(inst, "<official_name>", skin_custom) end`
- use the official `release_group` number

### Step 4: Add the custom runtime entry in `scripts\prefabs\kleiskinprefabs.lua`

The mod active entry should be `custom_<official_id>`.

The custom entry should:

- include an `assets` block with `DYNAMIC_ANIM` (.zip) and `PKGREF` (.dyn) when it owns local animation files
- omit `assets` when it reuses another custom build and the neighboring local pattern does the same
- set `build_name_override` to the custom-prefixed runtime build name, especially for reuse/variant entries
- use `function(inst) xxx_init_fn(inst, "custom_<build_name>") end` for `init_fn` in the standard custom case
- use `groupid` for `release_group`

### Step 5: Preserve official behavior, but adapt names carefully

General rules:

- `skin_id` becomes `custom_<official_id>`
- `build_name_override` usually becomes custom-prefixed if the actual build is local custom build data
- `normal_skin` should usually point to the custom-prefixed version for the local custom chain
- `share_bigportrait_name` should stay official-style and usually not use `custom_`
- `ghost_skin` is not always custom-prefixed; see ghost rules below
- `init_fn` must stay behaviorally identical to official logic, but the build name passed into it may need the `custom_` version

### Step 6: Decide whether this skin needs its own animation assets

Do not guess.

Use the official entry to classify it.

Cases:

1. Official entry has `assets`.
2. Official entry has no `assets` and reuses another build.
3. Official entry has no `assets`, but the visible rendering still depends on databundle-only animation data.

### Step 7: Add asset files when required

Possible sources:

- `F:\...\data\anim\dynamic\` for `.dyn` (copy and rename with `custom_` prefix, no patching needed)
- `F:\...\data\databundles\anim_dynamic.zip` for `.zip` (extract, then patch `build.bin` internal name)

If copying a `.zip` from official assets into the mod, verify whether the internal build name in `build.bin` still uses the official name. If so, it must be patched to use the `custom_` build name. See the "How To Patch `build.bin`" section for the exact procedure.

### Step 8: Verify ghost rules

Do not assume every `ghost_skin` should use `custom_`.

Rules in this project:

- Most standard character ghosts remain official-style, for example `ghost_wilson_build`.
- Some special ghost assets are custom-prefixed, for example `custom_ghost_wormwood_build`.
- Woodie transformation ghost assets are special and use custom-prefixed builds in this project.

### Step 9: Verify `_d`, `_p`, and `_none` relationships

Typical project behavior:

- `_d` often has its own assets
- `_p` often reuses `_d` build and has no assets block
- `_none` is a no-skin placeholder and should not be treated like a normal skinned asset

## Standard Workflow: Add a Newly Added Official Clothing Skin

This is for entries that appear in official `scripts/clothing.lua`.

### Step 1: Locate the exact official clothing entry

Copy the exact official fields before adapting anything.

Typical important fields:

- `type`
- `skin_tags`
- `symbol_overrides`
- `symbol_hides`
- `build_name_override`
- `symbol_overrides_skinny`
- `symbol_overrides_mighty`
- `symbol_overrides_stage2`
- `symbol_overrides_stage3`
- `symbol_overrides_stage4`
- `symbol_overrides_powerup`
- `legs_cuff_size`
- `feet_cuff_size`
- `has_leg_boot`
- `has_nub`
- `torso_tuck`
- `symbol_in_base_hides`
- `symbol_overrides_by_character`
- `release_group`
- `assets`

### Step 2: Add the entry to `scripts\clothing_curios.lua`

Use the mod naming convention `custom_<official_id>`.

### Step 3: Preserve clothing type behavior

Do not change `type` casually.

Valid runtime categories include:

- `body`
- `hand`
- `legs`
- `feet`
- `loading`
- `emoji`

### Step 4: Decide whether assets are required

Same rule as prefab skins: do not guess based on appearance.

### Step 5: Handle `_p` clothing variants correctly

Many `_p` clothing variants do not have their own assets. They often reuse a `_d` build via `build_name_override`.

### Step 6: Verify symbol-related fields carefully

Most clothing rendering problems come from incomplete or incorrect symbol fields.

## How To Decide Whether You Need To Patch `build.bin`

Rule:

If the runtime passes `custom_xxx` as the build name, but the copied animation `.zip` internally still declares `xxx`, the skin may not render.

You need to patch `build.bin` when all of these are true:

1. The mod runtime uses a custom-prefixed build name.
2. The `.zip` was copied from official assets.
3. The internal build still uses the official non-custom name.

### How to patch `build.bin`

The `build.bin` inside a `.zip` uses a simple binary format starting with magic `BILD`. The build name is stored as a 4-byte little-endian length at offset `0x10`, followed by the ASCII name string.

Patching procedure:

1. Extract `build.bin` from the `.zip`.
2. Read the 4-byte length at offset `0x10`.
3. Verify the old name matches.
4. Replace: `header (0x00-0x0F)` + `new length (4 bytes LE)` + `new name bytes` + `rest of file after old name`.
5. Repack the modified `build.bin` back into the `.zip`.

Example using Python:

```python
import struct, zipfile, os, tempfile

old_name = b"backpack_invisible"
new_name = b"custom_backpack_invisible"

with open("build.bin", "rb") as f:
    data = bytearray(f.read())

assert data[:4] == b"BILD"
old_len = struct.unpack_from("<I", data, 0x10)[0]
assert data[0x14:0x14+old_len] == old_name

new_data = data[:0x10] + struct.pack("<I", len(new_name)) + new_name + data[0x14+old_len:]

# Repack into zip
with zipfile.ZipFile("source.zip", "r") as zin:
    with zipfile.ZipFile("patched.zip", "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == "build.bin":
                zout.writestr(item, bytes(new_data))
            else:
                zout.writestr(item, zin.read(item.filename))
```

Important: On Windows, use `python` (not `python3`) and use `tempfile.gettempdir()` to resolve `/tmp/` paths correctly. The `python3` command on Windows often points to the Microsoft Store stub and will fail silently (exit code 49).

### `.dyn` files do not need patching

The `.dyn` format stores animation data only. It does not embed the build name. Simply copy the official `.dyn` and rename it with the `custom_` prefix.

## High-Risk Mistakes

- Trusting raw counts more than normalized name diff.
- Treating a zero missing-name result as proof that existing definitions did not change.
- Inspecting only a new skin's own block and missing reverse references from existing skins such as `granted_items`.
- Editing `prefabskins.lua` without validating that each category assignment opens its table before any string entries.
- Adding `assets` just because a skin is new.
- Forgetting that databundle-only assets exist.
- Copying official `.zip` without patching internal build name.
- Wrong `ghost_skin` prefix decision.
- Breaking `_p` reuse behavior.
- Incomplete `init_fn`.
- Updating mirror files only and forgetting the custom layer (or vice versa).
- Using `python3` on Windows (use `python` instead; `python3` maps to MS Store stub, exit code 49).
- Using `/tmp/` paths in Python on Windows without `tempfile.gettempdir()`.
- Forgetting to add the mirror entry in `skinprefabs.lua` alongside the custom entry in `kleiskinprefabs.lua`.
- Forgetting to bump `modinfo.lua` after an update, or bumping it before the final scope is known.
- Accidentally staging ignored local notes such as `CLAUDE_GUIDE.md` or `blog.md`.

## Recommended Update Procedure For Future AI

Use this exact order.

### Phase 1: Detect official changes

1. Record timestamps and sizes for `scripts.zip` and `anim_dynamic.zip`.
2. Re-run `tools\compare_missing_skins.ps1`.
3. Compare official `CreatePrefabSkin(...)` count and normalized missing names.
4. Inspect changed fields in existing definitions and relevant helper functions; zero missing names is not sufficient.
5. Reverse-search every new ID across the official files to find parent skins, bundles, variants, and helper references.
6. Inspect the exact official definitions for all new names.

### Phase 2: Classify each new official entry

For each new name, determine:

1. prefab or clothing
2. base or item
3. has assets or reuses build
4. needs `init_fn` or not
5. needs custom ghost handling or not
6. needs extracted animation files or not

### Phase 3: Apply data changes

1. update `scripts\prefabskins.lua` if category map changed
2. add mirror entry in `scripts\prefabs\skinprefabs.lua` (official-shaped, no custom assets, preserve official `build_name_override`)
3. add active prefab custom entries in `scripts\prefabs\kleiskinprefabs.lua` (custom_ prefix, custom build references, assets when required)
4. add clothing entries in `scripts\clothing_curios.lua`
5. add or update every reverse reference, including existing `granted_items`, variant links, `prefabs`, `fx_prefab`, and helper mappings

### Phase 4: Apply asset changes

1. copy required `.dyn` files
2. extract required `.zip` files from official assets when needed
3. patch internal build names when custom-prefixed build names are used

### Phase 5: Re-verify

1. run `tools\validate_skin_update.ps1` with the touched official skin IDs
2. confirm normalized prefab coverage is complete and the five clothing structural keys are unchanged
3. confirm `prefabskins.lua` table structure is valid
4. confirm there are no duplicates outside the documented historical baseline
5. confirm every asset reference exists and every dynamic zip internal build name matches its filename
6. manually verify the reported official reverse references and changed existing fields

### Phase 6: Version and Git preflight

1. Update `modinfo.lua` only after the final update scope and validation result are known.
2. Use a minor bump for a new official content batch and a patch bump for a focused compatibility or bug fix. Preserve the existing `V<major>.<minor>.<patch>` format.
3. Run `git diff --check` and inspect `git status --short`.
4. Stage only the intended public mod files and assets.
5. Run `git diff --cached --name-only` before committing. Confirm that ignored local notes and temporary outputs are absent. Tracked workflow files are allowed only when intentionally updated.
6. Re-run the validator after staging; it fails if a known ignored local note is staged.

## What To Do When Official Adds Only One Missing Name

At the current repository state (2026-07-17), normalized missing prefab coverage shows **zero** missing names.

If the next official update differs by one or a few names, do not perform broad regeneration. Add only the exact required entries and assets.

## What Success Looks Like

After a correct update:

1. the normalized diff script reports no newly missing intended official skin names
2. changed existing definitions and reverse references were reviewed, not only newly added IDs
3. the new custom entries match official behavior shape
4. `prefabskins.lua` passes the structural table check
5. all required animation assets exist in `anim\dynamic\`
6. build names used by runtime match internal build names in copied animation zips
7. ghost and variant chains are consistent with neighboring entries
8. `modinfo.lua` has the intended version and only public mod files are staged

## Minimal Command Reference (Windows / PowerShell)

```powershell
# Run normalized diff (fastest way to check for missing skins)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\compare_missing_skins.ps1

# Run all local validation checks and show official reverse references
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate_skin_update.ps1 -SkinId hat_ice_pengulls

# Search all relevant files for one skin before editing
rg -n 'hat_ice_pengulls|custom_hat_ice_pengulls' .\scripts\prefabskins.lua .\scripts\prefabs\skinprefabs.lua .\scripts\prefabs\kleiskinprefabs.lua

# Read key runtime files
Get-Content -Raw .\localskinmain.lua
Get-Content -Raw .\skinloader\skinloader.lua

# Final Git preflight
git diff --check
git status --short
git diff --cached --name-only
```

### Quick duplicate scan for mirror/custom prefab definitions

```powershell
@'
$content = Get-Content '.\scripts\prefabs\skinprefabs.lua' -Raw
[regex]::Matches($content, 'CreatePrefabSkin\("([^"]+)"') |
  ForEach-Object { $_.Groups[1].Value } |
  Group-Object |
  Where-Object { $_.Count -gt 1 } |
  Sort-Object Name
'@ | powershell -NoProfile -ExecutionPolicy Bypass -Command -
```

### Extracting official files from `scripts.zip`

```powershell
$dst = 'E:\Desktop\skin\_tmp\dst_scripts'
New-Item -ItemType Directory -Force $dst | Out-Null
Set-Location 'F:\SteamLibrary\steamapps\common\Don''t Starve Together\data\databundles'
7z e scripts.zip 'scripts/prefabs/skinprefabs.lua' "-o$dst" -y
```

### Extracting `.zip` from `anim_dynamic.zip`

```powershell
$dst = 'E:\Desktop\skin\_tmp\bp_extract'
New-Item -ItemType Directory -Force $dst | Out-Null
Set-Location 'F:\SteamLibrary\steamapps\common\Don''t Starve Together\data\databundles'
7z e anim_dynamic.zip 'anim/dynamic/backpack_invisible.zip' "-o$dst" -y
```

### Inspecting `build.bin` internal name

```powershell
$data = [System.IO.File]::ReadAllBytes('E:\Desktop\skin\_tmp\bp_build\build.bin')
$len = [BitConverter]::ToInt32($data, 0x10)
[Text.Encoding]::ASCII.GetString($data, 0x14, $len)
```

The build name bytes start at offset `0x14`, prefixed by a 4-byte LE length at `0x10`.

### Quick asset-reference scan for `kleiskinprefabs.lua`

```powershell
@'
$missing = 0
Get-Content '.\scripts\prefabs\kleiskinprefabs.lua' | ForEach-Object {
  if ($_ -match 'Asset\("(?:DYNAMIC_ANIM|PKGREF)",\s*"([^"]+)"\)') {
    $path = $matches[1]
    if (-not (Test-Path $path)) {
      Write-Output $path
      $missing++
    }
  }
}
"missing_refs=$missing"
'@ | powershell -NoProfile -ExecutionPolicy Bypass -Command -
```

### Patching `build.bin` (use `python`, not `python3`, on Windows)

See the Python example in the "How To Patch `build.bin`" section above.

## Final Verification Checklist

Use this before declaring an update finished:

1. `compare_missing_skins.ps1` reports `MISSING_PREFAB_SKINS=0`, or only the exact intentional residual names you have not implemented yet.
2. `MISSING_CLOTHING_KEYS=5` is unchanged and still only lists the structural official constants:
   `CLOTHING`, `CLOTHING_SFX`, `CLOTHING_SYMBOLS`, `footstep_layered`, `HIDE_SYMBOLS`.
3. Every newly touched prefab skin appears in the expected mirror/custom files, and there is no accidental extra duplicate definition for the names you edited.
4. Every new ID was reverse-searched in the official files, and any changed existing parent definition or helper was updated in both mirror/custom layers as required.
5. `scripts\prefabskins.lua` has no category assignment with skin strings outside the opening `{}`.
6. Every new `DYNAMIC_ANIM` / `PKGREF` path referenced by `kleiskinprefabs.lua` or `clothing_curios.lua` exists on disk.
7. Every copied `.zip` that was patched now reports the expected `custom_` internal build name.
8. If the update involved reuse variants (`_p`, item, builder, scanner/drone helpers, resurrected variants), `build_name_override`, `granted_items`, and `init_fn` still match the neighboring project pattern and the official behavior shape.
9. `modinfo.lua` uses the intended `V<major>.<minor>.<patch>` version and was bumped after the final scope was established.
10. `git diff --check` passes, the staged path list contains only intended public files, and no ignored local note is staged.
11. `tools\validate_skin_update.ps1` ends with `VALIDATION_OK`.

## Final Guidance

When in doubt, do not invent structure.

Take the exact official entry as the base truth, then adapt only the pieces that this mod explicitly changes:

- skin ID namespace via `custom_`
- ownership behavior via `skinloader`
- runtime build naming when custom assets are used

Everything else should stay as close to official behavior as possible.

## Completed Update Log

### 2026-04-03: Added `backpack_invisible`

Official definition:

- `base_prefab`: `backpack`
- `type`: `item`
- `rarity`: `Classy` (Woven)
- `skin_tags`: `INVISIBLE`, `BACKPACK`, `CRAFTABLE`
- `release_group`: `179`
- `init_fn`: calls `backpack_init_fn(inst, "backpack_invisible", skin_custom)` -- standard backpack init, no custom functions table
- No `assets` block in official (uses databundle-only assets)
- No `build_name_override` in official
- No `granted_items`, no `ghost_skin`, no `share_bigportrait_name`

What was done:

1. `scripts/prefabskins.lua`: added `"backpack_invisible"` to the `backpack` category list (alphabetical order between `backpack_hound` and `backpack_koalefant`).
2. `scripts/prefabs/skinprefabs.lua`: added mirror `CreatePrefabSkin("backpack_invisible", ...)` entry matching official shape.
3. `scripts/prefabs/kleiskinprefabs.lua`: added custom `CreatePrefabSkin("custom_backpack_invisible", ...)` entry with `assets`, `build_name_override`, and custom-prefixed `init_fn`.
4. `anim/dynamic/custom_backpack_invisible.dyn`: copied from official `data/anim/dynamic/backpack_invisible.dyn` (renamed only, no patching needed for `.dyn`).
5. `anim/dynamic/custom_backpack_invisible.zip`: extracted from official `anim_dynamic.zip`, then `build.bin` patched to change internal name from `backpack_invisible` to `custom_backpack_invisible`.

Asset origin:

- `.dyn`: `F:\...\data\anim\dynamic\backpack_invisible.dyn` (27,078 bytes, copied verbatim)
- `.zip`: `F:\...\data\databundles\anim_dynamic.zip` -> `anim/dynamic/backpack_invisible.zip` (1,006 bytes original -> 1,015 bytes after build.bin patch)

Verification: `compare_missing_skins.ps1` reports `MISSING_PREFAB_SKINS=0` after the change.

### 2026-04-17: Added 28 prefab skins + 3 clothing skins (release_group 180)

New entries added in this batch:

**Simple item skins (3):**

- `beebox_insect` — `base_prefab: beebox`, `rarity: Loyal`, own assets
- `magician_chest_shadow_resurrected` — `base_prefab: magician_chest`, `rarity: Resurrected`, reuses `magician_chest_shadow` build
- `researchlab2_science_resurrected` — `base_prefab: researchlab2`, `rarity: Resurrected`, reuses `researchlab2_science` build

**WX-78 base character skin (1):**

- `wx78_ancient` — `type: base`, `rarity: Elegant (Woven)`, `ghost_skin: ghost_wx78_build`, `feet_cuff_size: 3`, own assets

**WX-78 drone delivery Gothic/Jewelbox (8):**

- `wx78_dronedelivery_gothic`, `wx78_dronedelivery_item_gothic` (reuses gothic build)
- `wx78_dronedeliverysmall_gothic` (with `granted_items`), `wx78_dronedeliverysmall_item_gothic` (reuses small gothic build)
- `wx78_dronedelivery_jewelbox`, `wx78_dronedelivery_item_jewelbox` (reuses jewelbox build)
- `wx78_dronedeliverysmall_jewelbox` (with `granted_items`), `wx78_dronedeliverysmall_item_jewelbox` (reuses small jewelbox build)

**WX-78 drone scout Gothic/Jewelbox (2):**

- `wx78_dronescout_gothic`, `wx78_dronescout_jewelbox`

**WX-78 drone zap Gothic/Jewelbox (6):**

- `wx78_dronezap_gothic`, `wx78_dronezap_gothic_overlay`
- `wx78_dronezap_jewelbox`, `wx78_dronezap_jewelbox_overlay`
- `wx78_dronezapremote_gothic` (reuses `dronezap_gothic` build, with `granted_items`)
- `wx78_dronezapremote_jewelbox` (reuses `dronezap_jewelbox` build, with `granted_items`)

**WX-78 module remover Gothic/Jewelbox (2):**

- `wx78_moduleremover_gothic`, `wx78_moduleremover_jewelbox`

**WX-78 scanner Gothic/Jewelbox (6):**

- `wx78_scanner_gothic` (with `granted_items`), `wx78_scanner_gothic_item` (reuses gothic build)
- `wx78_scanner_jewelbox` (with `granted_items`), `wx78_scanner_jewelbox_item` (reuses jewelbox build)
- `wx78_scanner_succeeded_gothic` (reuses gothic build), `wx78_scanner_succeeded_jewelbox` (reuses jewelbox build)

**WX-78 ancient clothing (3):**

- `body_wx78_ancient` — `type: body`, `symbol_overrides: arm_upper, torso, torso_pelvis`, `torso_tuck: untucked`
- `feet_wx78_ancient` — `type: feet`, `symbol_overrides: foot`, `feet_cuff_size: 2`
- `hand_wx78_ancient` — `type: hand`, `symbol_overrides: arm_lower_cuff, hand`

New prefab categories added to `prefabskins.lua` (8):

- `wx78_drone_delivery`, `wx78_drone_delivery_item`, `wx78_drone_delivery_small`, `wx78_drone_delivery_small_item`
- `wx78_drone_scout`, `wx78_drone_zap`, `wx78_drone_zap_remote`, `wx78_moduleremover`

Asset files added (38 total = 19 .dyn + 19 .zip):

- `.dyn`: copied from official `data/anim/dynamic/`, renamed with `custom_` prefix
- `.zip`: extracted from official `anim_dynamic.zip`, `build.bin` patched to `custom_` prefix

Verification: `compare_missing_skins.ps1` reports `MISSING_PREFAB_SKINS=0` and `MISSING_CLOTHING_KEYS=5` (all 5 are structural constants).

### 2026-05-05: Added 5 prefab skins (release_group 181)

Normalized diff before update:

- `OFFICIAL_PREFAB_SKINS=1667`
- `MOD_PREFAB_SKINS_NORMALIZED=1662`
- `MISSING_PREFAB_SKINS=5`

New prefab skins added:

- `hat_ice_pengulls` -- `base_prefab: icehat`, `rarity: Loyal`, `skin_tags: ICEHAT, CRAFTABLE`
- `wx78_shadowdrone_debuffer_gothic` -- `base_prefab: wx78_shadowdrone_debuffer`, `rarity: Distinguished (Woven)`, `skin_tags: WX78SHADOWDRONEDEBUFFER, GOTHIC, CRAFTABLE`
- `wx78_shadowdrone_debuffer_jewelbox` -- `base_prefab: wx78_shadowdrone_debuffer`, `rarity: Distinguished (Woven)`, `skin_tags: WX78SHADOWDRONEDEBUFFER, JEWELBOX, CRAFTABLE`
- `wx78_shadowdrone_harvester_gothic` -- `base_prefab: wx78_shadowdrone_harvester`, `rarity: Distinguished (Woven)`, `skin_tags: WX78SHADOWDRONEHARVESTER, GOTHIC, CRAFTABLE`
- `wx78_shadowdrone_harvester_jewelbox` -- `base_prefab: wx78_shadowdrone_harvester`, `rarity: Distinguished (Woven)`, `skin_tags: WX78SHADOWDRONEHARVESTER, JEWELBOX, CRAFTABLE`

What was done:

1. `scripts/prefabskins.lua`: added `hat_ice_pengulls` to `icehat`, plus new `wx78_shadowdrone_debuffer` and `wx78_shadowdrone_harvester` categories.
2. `scripts/prefabs/skinprefabs.lua`: added official-shaped mirror entries for all 5 skins.
3. `scripts/prefabs/kleiskinprefabs.lua`: added `custom_` runtime entries for all 5 skins with `assets` and `build_name_override`.
4. `scripts/prefabskin.lua`: added the official WX-78 drone helper functions required by the new `shadowdrone` entries and the existing release_group 180 drone entries.
5. `anim/dynamic/custom_*.dyn`: copied from official `data/anim/dynamic/`, renamed only.
6. `anim/dynamic/custom_*.zip`: extracted from official `anim_dynamic.zip`, then `build.bin` patched from official build name to `custom_` build name.

Asset files added (10 total = 5 .dyn + 5 .zip):

- `custom_hat_ice_pengulls`
- `custom_wx78_shadowdrone_debuffer_gothic`
- `custom_wx78_shadowdrone_debuffer_jewelbox`
- `custom_wx78_shadowdrone_harvester_gothic`
- `custom_wx78_shadowdrone_harvester_jewelbox`

Verification:

- `compare_missing_skins.ps1` reports `MISSING_PREFAB_SKINS=0`.
- `MISSING_CLOTHING_KEYS=5` remains unchanged and still only contains structural constants.
- Static asset scan found `missing=0` for all `DYNAMIC_ANIM` and `PKGREF` references in `kleiskinprefabs.lua`.
- Each new `.zip` was checked after patching to confirm the internal `build.bin` name matches the `custom_` build name.

### 2026-06-12: Added 50 prefab skins + 18 clothing skins (release_group 182)

Official update source:

- `F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip`
- `F:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\anim_dynamic.zip`
- Local official resource timestamp: `2026-06-12 19:45`

Added prefab coverage:

- rose furniture/building/tool skins such as `axe_rose`, `fence_rose`, `wall_stone_rose`, `decor_*_rose`, and table/chair rose variants
- new item skins such as `beehat_ninja`, `panflute_insect`, and `succulent_potted_kleimug`
- Eets skins: `eets_e_basic`, `eets_e_basic_builder`
- character skins: `*_hazard`, `*_western`, and `*_20s` entries added by the June 2026 update

Added clothing coverage:

- `body_oni_001` through `body_oni_005`
- `body_walter_20s`, `body_winona_20s`, `feet_winona_20s`, `hand_winona_20s`
- `body_waxwell_western`, `hand_waxwell_western`, `legs_waxwell_western`
- `body_wolfgang_western`, `legs_wolfgang_western`
- `body_wurt_western`, `hand_wurt_western`, `legs_wurt_western`
- `legs_oni`

What was done:

1. `scripts/prefabskins.lua`: updated the affected official category lists.
2. `scripts/prefabs/skinprefabs.lua`: added official-shaped mirror entries for all 50 prefab skins.
3. `scripts/prefabs/kleiskinprefabs.lua`: added `custom_` runtime entries for all 50 prefab skins.
4. `scripts/clothing_curios.lua`: added `custom_` clothing entries for all 18 real clothing skins.
5. `scripts/prefabskin.lua`: added the official `critter_eets_init_fn` helper required by `eets_e_basic`.
6. `anim/dynamic/custom_*.dyn`: copied from official `data/anim/dynamic/`, renamed only.
7. `anim/dynamic/custom_*.zip`: extracted from official `anim_dynamic.zip`, then `build.bin` was patched by updating the BILD name length and internal build name to the `custom_` build name.

Verification:

- `compare_missing_skins.ps1` reports `MISSING_PREFAB_SKINS=0`.
- `MISSING_CLOTHING_KEYS=5` remains unchanged and still only contains structural constants.
- Static asset scans for `kleiskinprefabs.lua` and `clothing_curios.lua` both report `missing_refs=0`.
- All 76 newly copied `.zip` files were checked after patching; each internal `build.bin` name matches the `custom_` filename stem.

### 2026-06-28: Added minigolf/cawnival skins (release_group 183)

Added 12 prefab skins:

- `backpack_minigolf`
- `minisign_cawnival`, `minisign_cawnival_drawn`, `minisign_cawnival_item`
- `mushroom_light_cawnival`
- `researchlab4_minigolf_green`, `researchlab4_minigolf_purple`, `researchlab4_minigolf_red`
- `tophat_minigolf_green`, `tophat_minigolf_purple`, `tophat_minigolf_red`
- `torch_cawnival`

Added 12 minigolf clothing entries and their custom animation assets. Updated `modinfo.lua` from `V6.0.2` to `V6.1.0`.

### 2026-07-17: Added minigolf walrus hats and strengthened validation (release_group 183)

Normalized diff before update:

- `OFFICIAL_PREFAB_SKINS=1732`
- `MOD_PREFAB_SKINS_NORMALIZED=1729`
- `MISSING_PREFAB_SKINS=3`

Added:

- `walrushat_minigolf_green`
- `walrushat_minigolf_purple`
- `walrushat_minigolf_red`

Reverse-reference review also found that the existing `tophat_minigolf_green`, `tophat_minigolf_purple`, and `tophat_minigolf_red` definitions now grant the corresponding walrus hats. Both mirror and custom layers were updated.

The update also corrected malformed category table starts in `scripts/prefabskins.lua`, added six custom animation files, and changed the mod version from `V6.1.0` to `V6.2.0`.

Verification after update:

- normalized prefab coverage: `1732 / 1732`, missing `0`
- clothing residual: the same five non-actionable structural keys
- malformed `PREFAB_SKINS` table starts: `0`
- missing asset references: `0`
- incorrect new internal build names: `0`
- referenced mirror blocks matching official key fields: `6 / 6`

### 2026-08-11: Checked official data and hardened validator

Official source files were checked again. Their timestamps remain `2026-07-10 18:42:21`, and the normalized comparison still reports no missing prefab skin names.

No skin definitions, clothing entries, animation assets, or mod version changes were needed in this check. The validation script was adjusted to pass the repository path to Git as a temporary `safe.directory` value, so it works in environments where the workspace and current user have different Git ownership metadata. The global Git configuration is not changed.

### 2026-08-30: Added release group 184 skins and synchronized existing WX-78 tags

Official update source:

- scripts.zip: 56,175,396 bytes, timestamp 2026-08-14 22:10:55
- anim_dynamic.zip: 16,849,160 bytes, timestamp 2026-08-14 22:10:55

Normalized diff before update:

- OFFICIAL_PREFAB_SKINS=1736
- MOD_PREFAB_SKINS_NORMALIZED=1732
- MISSING_PREFAB_SKINS=4
- nine new real clothing entries beyond the five structural constants

Added prefab skins:

- parasol_polkadot
- pitchfork_fork
- shovel_spoon
- waterballoon_insect

Added clothing entries:

- body_onepiece_beach, body_onepiece2_beach, body_onepiece3_beach
- body_sailor_beach, body_sailor2_beach, body_sailor3_beach
- body_skirt_beach, body_skirt2_beach, body_skirt3_beach

The full semantic comparison also found four changed existing definitions. The official update added GOTHIC or JEWELBOX skin tags to:

- wx78_dronedeliverysmall_gothic
- wx78_dronedeliverysmall_jewelbox
- wx78_dronezapremote_gothic
- wx78_dronezapremote_jewelbox

All runtime-relevant historical duplicates were updated consistently in both mirror and custom layers.

Asset files added: 26 total (13 .dyn and 13 .zip). Every copied .zip had its internal build.bin name patched to the matching custom_ name. modinfo.lua was updated from V6.2.0 to V6.3.0.

Verification after update:

- normalized prefab coverage: 1736 / 1736, missing 0
- clothing residual: the same five non-actionable structural keys
- full semantic mirror comparison: all 1736 official definitions matched
- missing asset references: 0
- dynamic zip internal build-name mismatches: 0
- duplicate definitions: only the documented 16-name historical baseline
- git diff --check: passed
- unified validator: VALIDATION_OK
