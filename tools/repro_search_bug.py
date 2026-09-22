"""Regression test for the asset lookup, runnable without an iOS toolchain.

Background
----------
0.2.1 built one SQL with "Z_PK = ? OR ZFILENAME LIKE '%?%'" and then applied
"ORDER BY Z_PK DESC LIMIT n". Selecting the old asset Z_PK=5 matched every file name containing a
"5", so the newest of those filled the limit and the row that was asked for was not even in the
result set. In the app that looked like "no matter which photo I select, it dumps the newest five".

The fix is a list of attempts, most precise first:
  digits            -> exact Z_PK, nothing else
  other term        -> exact ZUUID / ZFILENAME, then a fragment fallback
This file reproduces the old failure and pins the new behaviour.

Run:  python tools/repro_search_bug.py
"""

import sqlite3
import sys

# ---- the SQL that 0.2.1 generated (copied from logs/detail_heif_converted.txt) --------------
LEGACY_SQL = ('SELECT * FROM "ZASSET" WHERE (ZUUID = ? OR ZUUID LIKE ? ESCAPE \'\\\' '
              'OR ZFILENAME LIKE ? ESCAPE \'\\\' OR Z_PK = ? OR Z_PK IN '
              '(SELECT ZASSET FROM "ZADDITIONALASSETATTRIBUTES" WHERE ZORIGINALFILENAME LIKE ? ESCAPE \'\\\')) '
              'ORDER BY Z_PK DESC LIMIT 20')

# ---- the attempt list the Objective-C code now builds --------------------------------------
ORDER = " ORDER BY Z_PK DESC LIMIT 20"
EXACT_ZPK = 'SELECT * FROM "ZASSET" WHERE Z_PK = ?1' + ORDER
EXACT_NAMES = ('SELECT * FROM "ZASSET" WHERE (ZUUID = ?1 COLLATE NOCASE OR ZFILENAME = ?1 COLLATE NOCASE)'
               + ORDER)
FRAGMENT = ('SELECT * FROM "ZASSET" WHERE (ZUUID LIKE ? ESCAPE \'\\\' OR ZFILENAME LIKE ? ESCAPE \'\\\' '
            'OR Z_PK IN (SELECT ZASSET FROM "ZADDITIONALASSETATTRIBUTES" WHERE ZORIGINALFILENAME LIKE ? ESCAPE \'\\\'))'
            + ORDER)
NEWEST = 'SELECT * FROM "ZASSET"' + ORDER

OLD_PK = 5


def build():
    db = sqlite3.connect(":memory:")
    db.execute('CREATE TABLE "ZASSET" (Z_PK INTEGER PRIMARY KEY, ZUUID VARCHAR, ZFILENAME VARCHAR, '
               'ZKIND INTEGER, ZKINDSUBTYPE INTEGER, ZSAVEDASSETTYPE INTEGER)')
    db.execute('CREATE TABLE "ZADDITIONALASSETATTRIBUTES" (Z_PK INTEGER PRIMARY KEY, ZASSET INTEGER, '
               'ZORIGINALFILENAME VARCHAR)')
    db.execute("INSERT INTO ZASSET VALUES (?, 'AAAA-OLD', 'IMG_0005.PNG', 0, 10, 3)", (OLD_PK,))
    db.execute("INSERT INTO ZADDITIONALASSETATTRIBUTES VALUES (?, ?, 'IMG_0005.PNG')", (OLD_PK, OLD_PK))
    for pk in range(5600, 5700):
        name = "IMG_%04d.HEIC" % pk
        db.execute("INSERT INTO ZASSET VALUES (?, ?, ?, 0, 0, 3)", (pk, "UUID-%d" % pk, name))
        db.execute("INSERT INTO ZADDITIONALASSETATTRIBUTES VALUES (?, ?, ?)", (pk, pk, name))
    db.commit()
    return db


def pks(db, sql, binds):
    return [r[0] for r in db.execute(sql, binds).fetchall()]


def resolve(db, term):
    """Mirrors -lookupAttemptsForTerm: plus -lookupAssetsForTerm: (exact first, fragments after)."""
    if term.isdigit():
        return "exact Z_PK", pks(db, EXACT_ZPK, (int(term),))
    if not term:
        return "newest asset", pks(db, NEWEST, ())
    hits = pks(db, EXACT_NAMES, (term,))
    if hits:
        return "exact ZUUID / ZFILENAME", hits
    frag = "%" + term + "%"
    return "fragment", pks(db, FRAGMENT, (frag, frag, frag))


def main():
    db = build()
    failures = []

    def check(label, ok, detail):
        print("%-6s %-58s %s" % ("PASS" if ok else "FAIL", label, detail))
        if not ok:
            failures.append(label)

    # 1. the old behaviour, reproduced
    frag = "%5%"
    legacy = pks(db, LEGACY_SQL, ("5", frag, frag, "5", frag))
    check("0.2.1 bug reproduced: selected Z_PK=5 is absent from the first five",
          OLD_PK not in legacy[:5], "legacy first five = %s" % legacy[:5])
    check("0.2.1 bug reproduced: selected Z_PK=5 is absent from the whole result set",
          OLD_PK not in legacy, "legacy result count = %d, newest = %s" % (len(legacy), legacy[:3]))

    # 2. numeric term is an exact primary key
    mode, hits = resolve(db, "5")
    check("numeric term resolves by exact Z_PK only", mode == "exact Z_PK" and hits == [OLD_PK],
          "%s -> %s" % (mode, hits))

    # 3. exact file name still works, case-insensitively
    mode, hits = resolve(db, "IMG_0005.PNG")
    check("exact file name resolves exactly", hits == [OLD_PK], "%s -> %s" % (mode, hits))
    mode, hits = resolve(db, "aaaa-old")
    check("exact ZUUID is case-insensitive", hits == [OLD_PK], "%s -> %s" % (mode, hits))

    # 4. a real fragment still falls back, newest first, and says which path matched
    mode, hits = resolve(db, "IMG_569")
    check("fragment falls back and stays newest-first",
          mode == "fragment" and hits == sorted(hits, reverse=True) and len(hits) > 1,
          "%s -> %d hits, first %s" % (mode, len(hits), hits[:3]))

    # 4b. a fragment that matches nothing reports no match instead of inventing one
    mode, hits = resolve(db, "IMG_57")
    check("fragment with no hits stays empty", mode == "fragment" and hits == [],
          "%s -> %s" % (mode, hits))

    # 5. empty term -> newest
    mode, hits = resolve(db, "")
    check("empty term returns the newest asset", mode == "newest asset" and hits[:1] == [5699],
          "%s -> %s" % (mode, hits[:1]))

    # 6. a numeric term must never be treated as a fragment
    db.execute("INSERT INTO ZASSET VALUES (7700, 'UUID-7700', 'IMG_0005_COPY.PNG', 0, 10, 3)")
    db.commit()
    mode, hits = resolve(db, "5")
    check("numeric term ignores file names that merely contain the digits",
          hits == [OLD_PK], "%s -> %s (IMG_0005_COPY.PNG exists and must not match)" % (mode, hits))

    print()
    if failures:
        print("%d check(s) failed: %s" % (len(failures), ", ".join(failures)))
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
