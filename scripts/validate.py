#!/usr/bin/env python3
"""Validate the Lean kusudama port against the C++ ground truth, point for point, via DuckDB + Parquet.

Ground truth: `data/humanoid_ground_truth.parquet` — the live humanoid rig's four rich multi-cone
joints (LeftLowerArm, LeftHand, LeftFoot, Head), each `JointLimitationKusudama3D.solve`d over a
200-direction Fibonacci sphere (dumped from the editor via the godot MCP bridge).
Lean port: `data/lean_out.parquet` — `continuousProject` over the same joints and directions.
`lake exe sim` emits a transient `data/lean_out.csv` (Lean writes text only); this script ingests it
into `data/lean_out.parquet` (zstd) and deletes the CSV, so `data/` stays Parquet-only.

The two are joined on (setting, joint, i); the check is the per-point angular error between the C++
output and the Lean output (NOT an assumption that either is a no-op). The port is faithful when the
max error is below tolerance. A combined `data/validation.parquet` is written for archival.
"""
import os
import duckdb

TOL_DEG = 0.5
con = duckdb.connect()

# Ingest the transient Lean CSV into Parquet, then remove it (data/ stays csv-free).
LEAN_CSV = "data/lean_out.csv"
LEAN_PARQUET = "data/lean_out.parquet"
if os.path.exists(LEAN_CSV):
    con.execute(f"COPY (SELECT * FROM read_csv_auto('{LEAN_CSV}')) "
                f"TO '{LEAN_PARQUET}' (FORMAT PARQUET, COMPRESSION ZSTD)")
    os.remove(LEAN_CSV)
if not os.path.exists(LEAN_PARQUET):
    raise SystemExit(f"missing {LEAN_PARQUET} (and no {LEAN_CSV}); run `lake exe sim` first")

GT = "read_parquet('data/humanoid_ground_truth.parquet')"
LEAN = f"read_parquet('{LEAN_PARQUET}')"


def ang(a, b):
    # angular distance (deg) between two unit-ish vectors a_* and b_*
    return (f"degrees(acos(least(1.0,greatest(-1.0, "
            f"({a}_x*{b}_x+{a}_y*{b}_y+{a}_z*{b}_z)/"
            f"(sqrt({a}_x*{a}_x+{a}_y*{a}_y+{a}_z*{a}_z)*sqrt({b}_x*{b}_x+{b}_y*{b}_y+{b}_z*{b}_z))))))")


con.execute(f"""
CREATE TABLE v AS
SELECT g.setting, g.joint, g.label, g.i,
       g.in_x, g.in_y, g.in_z,
       g.cpp_out_x, g.cpp_out_y, g.cpp_out_z,
       l.lean_out_x, l.lean_out_y, l.lean_out_z,
       g.move_deg AS cpp_move_deg,
       {ang('g.in', 'l.lean_out')} AS lean_move_deg,
       {ang('g.cpp_out', 'l.lean_out')} AS err_deg
FROM {GT} g
JOIN {LEAN} l USING (setting, joint, i)
""")

n = con.execute("SELECT count(*) FROM v").fetchone()[0]
gt_rows = con.execute(f"SELECT count(*) FROM {GT}").fetchone()[0]
if n != gt_rows:
    print(f"WARNING: joined {n} rows but ground truth has {gt_rows} (key mismatch)")

print(f"joined {n} points across {con.execute('SELECT count(DISTINCT (setting,joint)) FROM v').fetchone()[0]} joints\n")
print("per joint: C++ moved / Lean moved / max |C++-Lean| error (deg)")
for r in con.execute("""
    SELECT label,
           sum(CASE WHEN cpp_move_deg  > 0.01 THEN 1 ELSE 0 END) AS cpp_moved,
           sum(CASE WHEN lean_move_deg > 0.01 THEN 1 ELSE 0 END) AS lean_moved,
           count(*) AS n,
           max(err_deg) AS max_err
    FROM v GROUP BY label, setting, joint ORDER BY setting, joint""").fetchall():
    label, cpp_moved, lean_moved, cnt, max_err = r
    print(f"  {label:14s}  C++ {cpp_moved:3d}/{cnt}   Lean {lean_moved:3d}/{cnt}   max_err {max_err:.5f}")

max_err = con.execute("SELECT max(err_deg) FROM v").fetchone()[0]
con.execute("COPY v TO 'data/validation.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)")

print(f"\noverall max |C++ - Lean| = {max_err:.5f} deg  (tolerance {TOL_DEG})")
print("PASS: Lean port reproduces the C++ ground truth point for point"
      if max_err < TOL_DEG else
      "FAIL: Lean port diverges from the C++ ground truth")
print("wrote data/validation.parquet (zstd)")
