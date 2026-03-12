# Export Rules Addon

A Godot 4.6 editor plugin that manages game export configurations using feature tags. Define which files or folders are included in each export preset — no more manual editing of `export_presets.cfg`.

## How it works

Each rule maps a path (file or folder) to a set of **required tags**. When you apply rules, the plugin computes the exclusion list for each export preset based on the tags defined in that preset's `custom_features` field.

- **Empty tags** → path is always excluded from all presets
- **Tags set** → path is included only in presets that have all those tags

The plugin reads tag lists from `export_presets.cfg`'s `custom_features` field (comma-separated), then sets the preset's `export_filter` to `"exclude"` with the computed file list.

## Installation

1. Copy the `addons/export_rules/` folder into your project's `addons/` directory.
2. In the Godot editor, go to **Project Settings → Plugins** and enable **Export Rules**.
3. An **Export Rules** tab will appear in the editor's main screen.
4. Configuration is saved to `export_rules.json` in your project root.

## Usage

1. Click **Add Folder** or **Add File** to create a new rule.
2. In the rule editor, add required tags (e.g. `demo`, `full`, `steam`).
3. Optionally add a comment to describe the rule.
4. The preview shows which export presets will include or exclude the path.
5. Click **Update** to apply all rules to `export_presets.cfg`.

## Configuration

Rules are stored in `export_rules.json`:

```json
{
  "new_folder_policy": 0,
  "rules": [
    {
      "path": "res://test",
      "required_tags": [],
      "comment": "Never export tests"
    },
    {
      "path": "res://stages/level_demo",
      "required_tags": ["demo"],
      "comment": "Demo level only"
    },
    {
      "path": "res://stages/level_full",
      "required_tags": ["full"],
      "comment": "Full version only"
    }
  ]
}
```

### New folder policy

When the plugin detects a new folder in your project, it can:

| Value | Behavior |
|-------|----------|
| `0` — Auto Include | Automatically add to rules (included in all presets) |
| `1` — Auto Exclude | Automatically add to rules (excluded from all presets) |
| `2` — Ask | Prompt you for each new folder |

## Requirements

- Godot 4.6+
