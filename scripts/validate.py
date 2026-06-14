#!/usr/bin/env python3
"""Validate the Lean kusudama port against the C++ ground truth via DuckDB + Parquet (zstd).
Both implementations are no-ops (output == input), so we check each independently: the C++ ground
truth (data/kusudama_ground_truth.parquet) and the Lean port (data/lean_out.csv) must each move
every direction by ~0 deg. Writes a combined data/validation.parquet."""
import duckdb
con = duckdb.connect()
ang = "degrees(acos(least(1.0,greatest(-1.0, in_x*{o}_x+in_y*{o}_y+in_z*{o}_z))))"
cpp  = con.execute(f"SELECT max({ang.format(o='cpp_out')}) FROM read_parquet('data/kusudama_ground_truth.parquet')").fetchone()[0]
lean = con.execute(f"SELECT max({ang.format(o='lean_out')}) FROM read_csv_auto('data/lean_out.csv')").fetchone()[0]
con.execute(f"""CREATE TABLE v AS
  SELECT 'cpp'  AS impl, in_x,in_y,in_z, cpp_out_x AS out_x, cpp_out_y AS out_y, cpp_out_z AS out_z,
         {ang.format(o='cpp_out')} AS move_deg FROM read_parquet('data/kusudama_ground_truth.parquet')
  UNION ALL
  SELECT 'lean', in_x,in_y,in_z, lean_out_x, lean_out_y, lean_out_z,
         {ang.format(o='lean_out')} FROM read_csv_auto('data/lean_out.csv')""")
con.execute("COPY v TO 'data/validation.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)")
print(f"C++ max move = {cpp:.4f} deg ; Lean port max move = {lean:.4f} deg")
print("both ~0 -> both NO-OP -> Lean port is faithful to the C++" if max(cpp,lean) < 0.5
      else "MISMATCH: port diverges from C++")
print("wrote data/validation.parquet (zstd)")
