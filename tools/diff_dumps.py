"""Parse the PhotosDatabaseInspector asset dumps and diff them field by field."""

import io
import re
import sys

ROW_RE = re.compile(r"^\[([A-Z_0-9]+)\]\s+Z_PK=(\d+)(.*)$")
COL_RE = re.compile(r"^  ([A-Za-z0-9_]+)\s+= (.*)$")
ASSET_RE = re.compile(r"^ASSET (\d+) / (\d+)\s+Z_PK=(\d+)")


def parse(path):
    """-> list of {pk, filename, uuid, rows: [(table, pk, [(col, value)])]}"""
    lines = io.open(path, encoding="utf-8", errors="replace").read().splitlines()
    assets = []
    current = None
    row = None
    for line in lines:
        m = ASSET_RE.match(line)
        if m:
            current = {"pk": m.group(3), "filename": None, "uuid": None, "rows": []}
            assets.append(current)
            row = None
            continue
        if current is not None:
            if line.startswith("  ZFILENAME=") and current["filename"] is None:
                current["filename"] = line.split("=", 1)[1].strip()
                continue
            if line.startswith("  ZUUID=") and current["uuid"] is None:
                current["uuid"] = line.split("=", 1)[1].strip()
                continue
        m = ROW_RE.match(line)
        if m and current is not None:
            row = (m.group(1), m.group(2), [])
            current["rows"].append(row)
            continue
        m = COL_RE.match(line)
        if m and row is not None:
            row[2].append((m.group(1), m.group(2)))
    return assets


def flatten(asset):
    """-> {table.col: value}, tables and columns in order, multi-row tables indexed"""
    out = {}
    index = {}
    for table, pk, cols in asset["rows"]:
        n = index.get(table, 0)
        index[table] = n + 1
        prefix = table if n == 0 else "%s[%d]" % (table, n)
        for col, value in cols:
            out["%s.%s" % (prefix, col)] = value
    return out


def diff(a, b, only=None):
    keys = [k for k in a if k not in b] + [k for k in a if k in b] + [k for k in b if k not in a]
    seen = set()
    out = []
    for k in keys:
        if k in seen:
            continue
        seen.add(k)
        va, vb = a.get(k), b.get(k)
        if va != vb:
            if only and not any(p in k for p in only):
                continue
            out.append((k, va, vb))
    return out


if __name__ == "__main__":
    png = parse("logs/detail_png_original.txt")
    heif = parse("logs/detail_heif_converted.txt")
    print("png_original.txt  assets:", ["%s %s" % (a["pk"], a["filename"]) for a in png])
    print("heif_converted.txt assets:", ["%s %s" % (a["pk"], a["filename"]) for a in heif])
    print()

    # fully dumped = has a ZASSET row with columns
    full = [a for a in png if any(t == "ZASSET" and c for t, _, c in a["rows"])]
    print("fully dumped in png_original.txt:", ["%s %s" % (a["pk"], a["filename"]) for a in full])
    print()

    by_pk_png = {a["pk"]: a for a in png}
    by_pk_heif = {a["pk"]: a for a in heif}

    # ---- 1. same asset dumped twice: is the tool deterministic?
    for pk in sorted(set(by_pk_png) & set(by_pk_heif)):
        a, b = flatten(by_pk_png[pk]), flatten(by_pk_heif[pk])
        d = diff(a, b)
        print("=== 1. same asset %s (%s) dumped in both files: %d field(s) differ ===" %
              (pk, by_pk_png[pk]["filename"], len(d)))
        for k, va, vb in d:
            print("   %-46s A=%s   B=%s" % (k, va, vb))
        print()

    # ---- 2. across the fully dumped assets: which fields vary, which are constant
    flags = [flatten(a) for a in full]
    allkeys = []
    for f in flags:
        for k in f:
            if k not in allkeys:
                allkeys.append(k)
    varying, constant = [], []
    for k in allkeys:
        values = set(f.get(k, "(absent)") for f in flags)
        (varying if len(values) > 1 else constant).append((k, values))
    print("=== 2. across the %d fully dumped assets ===" % len(full))
    for a in full:
        print("   %s %s" % (a["pk"], a["filename"]))
    print("   total keys=%d  varying=%d  constant=%d" % (len(allkeys), len(varying), len(constant)))
    print()
    print("   --- fields that VARY (per-asset) ---")
    for k, values in varying:
        if k.startswith(("ZMOMENT", "ZMOMENTSHARE")):
            continue
        vals = " | ".join(sorted(values))[:150]
        print("   %-46s %s" % (k, vals))
    print()
    print("   --- fields that are CONSTANT across all of them ---")
    print("   " + ", ".join(k for k, _ in constant))

    # ---- 3. camera / lens related fields
    print()
    print("=== 3. camera / lens / source related fields ===")
    patterns = ["CAMERA", "LENS", "MAKE", "MODEL", "CAPTUREDEVICE", "IMPORTEDBY", "IMPORTSESSION",
                "DATECREATEDSOURCE", "ORIGINALFILENAME", "ORIGINALRESOURCE", "ORIGINALHASH",
                "SAVEDASSETTYPE", "KINDSUBTYPE", "ZKIND", "UTI", "MEDIAMETADATA", "DEPTHTYPE",
                "HDRTYPE", "DERIVEDCAMERA"]
    for f, a in zip(flags, full):
        print("   -- %s %s" % (a["pk"], a["filename"]))
        for k in allkeys:
            if any(p in k.upper() for p in patterns):
                print("      %-44s = %s" % (k, f.get(k, "(absent)")))
