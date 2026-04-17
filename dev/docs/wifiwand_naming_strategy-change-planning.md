# Wifi Wand Naming Strategy

## Summary

This document outlines considerations for renaming Wifi Wand identifiers to a unified `wifiwand` form, along with impacts and migration steps.

---

## Naming Representations and Usage

| Representation | Typical Usage Context |
|---------------|---------------------|
| `wifiwand` | CLI command, binary name, branding, URLs |
| `wifi-wand` | Traditional Unix-style CLI command, package names (sometimes) |
| `wifi_wand` | Ruby require paths, file paths (`lib/wifi_wand/...`) |
| `WifiWand` | Ruby module/class names |
| `Wifiwand` | Possible but non-idiomatic Ruby constant form |

---

## Semantic Considerations

### Pros of `wifiwand`
- Single canonical identifier across contexts
- Cleaner branding (like `tmux`, `ripgrep`)
- Avoids delimiter inconsistency

### Cons
- Slightly less readable
- Less Unix-traditional than hyphenated commands

---

## Breaking Change Assessment

- Appropriate for a major version bump
- Should be bundled with other breaking changes
- Key risk is upgrade friction

---

## Practical Considerations

### CLI
- Hyphenated names are more readable
- Single token names are more modern

### Ruby Conventions
- Prefer `wifi_wand` for file paths
- Prefer `WifiWand` for modules
- Avoid changing constant names if possible

### Discoverability
- Users may search “wifi wand” or “wifi-wand”
- Ensure README includes all variants

---

## Migration Requirements

### 1. CLI Compatibility
Provide shim:
```
wifi-wand -> wifiwand
```

### 2. Require Compatibility
```
# wifi_wand.rb
require 'wifiwand'
```

### 3. Gem Naming
- Prefer keeping existing gem name to avoid ecosystem breakage

### 4. Scripts and CI
- Users may need to update scripts
- Provide migration instructions

### 5. Documentation
Update:
- README
- Help output
- Examples
- Screenshots

### 6. Package Managers
- Homebrew / apt naming decisions
- Possibly alias old name

### 7. Shell Completion
- Update or duplicate completion scripts

---

## Recommendation

- Standardize externally on `wifiwand`
- Keep internal Ruby naming idiomatic:
  - `WifiWand`
  - `wifi_wand`
- Provide backward compatibility shims
- Release as a major version change

---

## Final Note

This is a strategic cleanup improving consistency and branding. The change is justified if migration friction is handled carefully.
