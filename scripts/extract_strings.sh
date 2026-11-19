#!/bin/bash
# Re-extracts the English strings from the source into Sources/VibeCheck/Resources/Localizable.xcstrings.
# Run after adding or changing Text("…") / String(localized: "…") literals, then commit the catalog.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH=.build/extract-strings
CATALOG=Sources/VibeCheck/Resources/Localizable.xcstrings
swift build --scratch-path "$SCRATCH" -Xswiftc -emit-localized-strings
find "$SCRATCH" -name '*.stringsdata' -print0 | xargs -0 xcrun xcstringstool sync "$CATALOG" --stringsdata
echo "Updated $CATALOG"

# Give every string an explicit English value so the build emits en.lproj/Localizable.strings
# (without it, English falls back to the key and nothing is compiled, which hides missing keys from tests).
python3 - "$CATALOG" <<'PY'
import json, sys
path = sys.argv[1]
catalog = json.load(open(path))
for key in [k for k in catalog["strings"] if not k.strip()]:
    del catalog["strings"][key]
for key, entry in catalog["strings"].items():
    en = entry.setdefault("localizations", {}).setdefault("en", {"stringUnit": {"value": key}})
    unit = en.get("stringUnit")
    if unit is not None:
        unit["state"] = "translated"
        unit.setdefault("value", key)
with open(path, "w") as f:
    json.dump(catalog, f, indent=2, ensure_ascii=False, sort_keys=True)
    f.write("\n")
PY
