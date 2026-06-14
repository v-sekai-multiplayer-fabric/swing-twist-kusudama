import LeanDuckDB

open DuckDB

/-!
# import-scene — fold an MCP-dumped scene into the humanoid_*.parquet set.

The godot MCP bridge (`run_script`) writes the rig as transient JSON next to the data (`FileAccess`,
one file per table). This exe converts each `data/humanoid_<t>.json` to `data/humanoid_<t>.parquet`
(zstd) via DuckDB `read_json_auto`, then deletes the JSON, so `data/` stays Parquet-only. No Python.
-/

def tables : List String := ["meta", "joints", "cones", "targets", "ground_truth"]

def main (_args : List String) : IO Unit := do
  for t in tables do
    let js := s!"data/humanoid_{t}.json"
    let pq := s!"data/humanoid_{t}.parquet"
    if ← System.FilePath.pathExists js then
      let _ ← query s!"COPY (SELECT * FROM read_json_auto('{js}')) TO '{pq}' (FORMAT PARQUET, COMPRESSION ZSTD)"
      IO.FS.removeFile js
      let n ← rowCount pq
      IO.println s!"imported {pq} ({n} rows) from transient {js}"
    else
      IO.println s!"skip {t}: no {js} to import"
