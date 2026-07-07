#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_trace_dropzone_bug.sh
set -e

python3 - << 'PYEOF'
path = "src/components/intake/FileDropzone.tsx"
with open(path) as f:
    content = f.read()

old = """        onClick={() => {
          console.count('[dropzone] div onClick fired');
          inputRef.current?.click();
        }}"""

new = """        onClick={(e) => {
          // TEMP DIAGNOSTIC — logs whether each firing is a real physical
          // click (isTrusted: true) or code calling .click() programmatically
          // (isTrusted: false), plus the full call stack so we can see what
          // triggered it.
          console.log(
            '[dropzone] div onClick fired — isTrusted:',
            e.isTrusted,
            'target:',
            (e.target as HTMLElement)?.tagName,
            (e.target as HTMLElement)?.className
          );
          console.trace('[dropzone] call stack');
          inputRef.current?.click();
        }}"""

if "isTrusted" in content:
    print("FileDropzone.tsx: trace diagnostic already present — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("FileDropzone.tsx: added isTrusted + console.trace diagnostic.")
else:
    raise SystemExit(
        "Expected onClick block not found in "
        "src/components/intake/FileDropzone.tsx — aborting. Paste me the "
        "current file and I'll fix it by hand."
    )
PYEOF

echo ""
echo "Restart your dev server, open the browser console, reproduce the bug"
echo "(click to open the file picker), and paste back every"
echo "'[dropzone] div onClick fired' line along with its trace — including"
echo "whether isTrusted says true or false each time."
