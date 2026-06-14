import LeanDuckDB

open DuckDB

/-!
# import-addbio — fold the AddBiomechanics ROM dumps into Parquet.

The `addb-extract` pixi tooling (`rom_from_b3d.py`, `model_limits.py`) reads the AddBiomechanics
`.b3d` corpus and dumps fitted Kusudama cones as JSON/JSONL. This exe flattens those transient dumps
into long-form `data/addbio_*_rom.parquet` (one row per subject×bone×cone) through the lean-duckdb
DuckDB binding (`COPY ... read_json`), then deletes the transient JSON, so `data/` stays Parquet-only.
No Python in the repo. Re-run after re-dumping.

Place the dumps as `data/_addbio_motion.jsonl` (rom_from_b3d motion ROM), `data/_addbio_model.jsonl`
(model_limits anatomical ROM), `data/_addbio_template.json` (the aggregated median template).
-/

-- motion ROM (per-frame FK swing, fitted cones; radius in degrees)
def motionSql : String :=
  "COPY (WITH raw AS (SELECT subject,study,sex,age_years,height_m,mass_kg,bones FROM read_json('data/_addbio_motion.jsonl', format='newline_delimited', columns={subject:'VARCHAR',study:'VARCHAR',sex:'VARCHAR',age_years:'DOUBLE',height_m:'DOUBLE',mass_kg:'DOUBLE',bones:'JSON'})), pb AS (SELECT subject,study,sex,age_years,height_m,mass_kg, bone, json_extract(bones, bone) AS bj FROM raw, UNNEST(json_keys(bones)) AS t(bone)), pc AS (SELECT pb.* EXCLUDE(bj), CAST(json_extract(bj,'$.n') AS BIGINT) n, CAST(json_extract(bj,'$.enclose_deg') AS DOUBLE) enclose_deg, CAST(json_extract(bj,'$.twist_range_deg') AS DOUBLE) twist_range_deg, g.cone_idx, CAST(json_extract(bj,'$.cones['||g.cone_idx||']') AS DOUBLE[]) cone FROM pb, range(0, CAST(json_array_length(json_extract(bj,'$.cones')) AS INTEGER)) AS g(cone_idx)) SELECT subject,study,sex,age_years,height_m,mass_kg,bone,n,enclose_deg,twist_range_deg,cone_idx, cone[1] cx,cone[2] cy,cone[3] cz,cone[4] radius_deg,radians(cone[4]) radius_rad FROM pc) TO 'data/addbio_motion_rom.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)"

-- anatomical-limit ROM (OpenSim coordinate limits, fitted cones; radius in degrees)
def modelSql : String :=
  "COPY (WITH raw AS (SELECT subject,sex,age_years,height_m,mass_kg,bones FROM read_json('data/_addbio_model.jsonl', format='newline_delimited', columns={subject:'VARCHAR',sex:'VARCHAR',age_years:'DOUBLE',height_m:'DOUBLE',mass_kg:'DOUBLE',bones:'JSON'})), pb AS (SELECT subject,sex,age_years,height_m,mass_kg, bone, json_extract(bones, bone) AS bj FROM raw, UNNEST(json_keys(bones)) AS t(bone)), pc AS (SELECT pb.* EXCLUDE(bj), CAST(json_extract(bj,'$.enclose_deg') AS DOUBLE) enclose_deg, CAST(json_extract(bj,'$.twist_range_deg') AS DOUBLE) twist_range_deg, g.cone_idx, CAST(json_extract(bj,'$.cones['||g.cone_idx||']') AS DOUBLE[]) cone FROM pb, range(0, CAST(json_array_length(json_extract(bj,'$.cones')) AS INTEGER)) AS g(cone_idx)) SELECT subject,sex,age_years,height_m,mass_kg,bone,enclose_deg,twist_range_deg,cone_idx, cone[1] cx,cone[2] cy,cone[3] cz,cone[4] radius_deg,radians(cone[4]) radius_rad FROM pc) TO 'data/addbio_model_rom.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)"

-- aggregated median template (radius in radians)
def templateSql : String :=
  "COPY (WITH raw AS (SELECT template FROM read_json('data/_addbio_template.json', columns={template:'JSON'})), pb AS (SELECT bone, json_extract(template, bone) AS bj FROM raw, UNNEST(json_keys(template)) AS t(bone)), pc AS (SELECT bone, CAST(json_extract(bj,'$.cone_count') AS BIGINT) cone_count, CAST(json_extract(bj,'$.twist_rad') AS DOUBLE) twist_rad, CAST(json_extract(bj,'$.enclose_deg') AS DOUBLE) enclose_deg, g.cone_idx, CAST(json_extract(bj,'$.cones['||g.cone_idx||']') AS DOUBLE[]) cone FROM pb, range(0, CAST(json_array_length(json_extract(bj,'$.cones')) AS INTEGER)) AS g(cone_idx)) SELECT bone,cone_idx,cone_count,cone[1] cx,cone[2] cy,cone[3] cz,cone[4] radius_rad,degrees(cone[4]) radius_deg,twist_rad,enclose_deg FROM pc) TO 'data/addbio_template_rom.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)"

def jobs : List (String × String × String) :=
  [ ("data/_addbio_motion.jsonl",  "data/addbio_motion_rom.parquet",   motionSql)
  , ("data/_addbio_model.jsonl",   "data/addbio_model_rom.parquet",    modelSql)
  , ("data/_addbio_template.json", "data/addbio_template_rom.parquet",  templateSql) ]

def main (_args : List String) : IO Unit := do
  for (src, out, sql) in jobs do
    if ← System.FilePath.pathExists src then
      let _ ← query sql
      IO.FS.removeFile src
      let n ← rowCount out
      IO.println s!"imported {out} ({n} rows) from transient {src}"
    else
      IO.println s!"skip: no {src} to import"
