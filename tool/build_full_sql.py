#!/usr/bin/env python3
"""Regenerates supabase/combined/dawak_full_schema.sql by concatenating supabase/migrations/*.sql in order."""
import glob, os, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
HEADER = pathlib.Path(__file__).with_name("full_sql_header.txt").read_text(encoding="utf-8")
parts = [HEADER]
for f in sorted(glob.glob(str(ROOT / "supabase" / "migrations" / "*.sql"))):
    parts.append("\n-- " + "=" * 100 + f"\n-- PART {os.path.basename(f)}\n-- " + "=" * 100 + "\n")
    parts.append(pathlib.Path(f).read_text(encoding="utf-8").rstrip() + "\n")
target = ROOT / "supabase" / "combined" / "dawak_full_schema.sql"
target.write_text("".join(parts), encoding="utf-8")
print(f"wrote {target.relative_to(ROOT)} ({target.stat().st_size} bytes)")
