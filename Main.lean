import SwingTwistKusudama
import LeanDuckDB

open SwingTwistKusudama
open DuckDB

/-!
# sim — run the faithful kusudama port on the live humanoid rig and validate against C++.

Reads the rig from Parquet (`data/humanoid_cones.parquet` for the cones, `data/humanoid_ground_truth.parquet`
for the C++ `solve` outputs over a 200-direction sphere), runs `continuousProject` on the SAME inputs,
writes the port's outputs to `data/lean_out.parquet`, then joins the two and writes
`data/validation.parquet` with the per-point angular error. All Parquet I/O goes through the vendored
DuckDB FFI (`LeanDuckDB`); no CSV, no Python.
-/

def gt : String := "data/humanoid_ground_truth.parquet"
def conesPq : String := "data/humanoid_cones.parquet"

/-- The cones of one joint, read from `humanoid_cones.parquet` (centers re-normalized; radii radians). -/
def loadJoint (s j : Nat) : IO (List KCone) := do
  let t ← query s!"SELECT cx, cy, cz, radius FROM read_parquet('{conesPq}') WHERE setting = {s} AND joint = {j} ORDER BY cone"
  let cx := t.columnFloat "cx"; let cy := t.columnFloat "cy"
  let cz := t.columnFloat "cz"; let rd := t.columnFloat "radius"
  return (List.range t.numRows).map fun i =>
    { c := V3.norm ⟨cx[i]!, cy[i]!, cz[i]!⟩, r := rd[i]! }

/-- The C++ ground-truth input directions of one joint, in `i` order (identical to the C++ sweep). -/
def loadInputs (s j : Nat) : IO (Array V3) := do
  let t ← query s!"SELECT in_x, in_y, in_z FROM read_parquet('{gt}') WHERE setting = {s} AND joint = {j} ORDER BY i"
  let xs := t.columnFloat "in_x"; let ys := t.columnFloat "in_y"; let zs := t.columnFloat "in_z"
  return (Array.range t.numRows).map fun i => (⟨xs[i]!, ys[i]!, zs[i]!⟩ : V3)

/-- `degrees(acos(clamp(dot/(|a||b|))))` between two vector columns, for the validation join. -/
def angSql (a b : String) : String :=
  s!"degrees(acos(least(1.0, greatest(-1.0, ({a}_x*{b}_x+{a}_y*{b}_y+{a}_z*{b}_z)/" ++
  s!"(sqrt({a}_x*{a}_x+{a}_y*{a}_y+{a}_z*{a}_z)*sqrt({b}_x*{b}_x+{b}_y*{b}_y+{b}_z*{b}_z))))))"

def f (x : R) : String := toString x

def main (_args : List String) : IO Unit := do
  -- the four rich joints captured in the ground truth
  let jt ← query s!"SELECT DISTINCT setting, joint, label FROM read_parquet('{gt}') ORDER BY setting, joint"
  let ss := jt.column "setting"; let js := jt.column "joint"; let ls := jt.column "label"
  -- run the port on each joint's own inputs, accumulating the VALUES rows for lean_out.parquet
  let mut values : Array String := #[]
  for k in [0:jt.numRows] do
    let s := (ss[k]!).toNat!; let j := (js[k]!).toNat!; let label := ls[k]!
    let cones ← loadJoint s j
    let inputs ← loadInputs s j
    let mut nonzero := 0
    for i in [0:inputs.size] do
      let d := inputs[i]!
      let o := continuousProject cones d 0.22
      if V3.angle o d > d2r 0.01 then nonzero := nonzero + 1
      values := values.push s!"({s},{j},{i},{f d.x},{f d.y},{f d.z},{f o.x},{f o.y},{f o.z})"
    IO.println s!"  s{s}/j{j} {label} ({cones.length} cones): {nonzero}/{inputs.size} directions moved by the port"
  -- write the port output to Parquet (zstd) directly from Lean
  let cols := "setting, joint, i, in_x, in_y, in_z, lean_out_x, lean_out_y, lean_out_z"
  let _ ← query (s!"COPY (SELECT * FROM (VALUES " ++ String.intercalate ", " values.toList ++
    s!") AS t({cols})) TO 'data/lean_out.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)")
  IO.println "wrote data/lean_out.parquet"
  -- join against the C++ ground truth and write the per-point error to validation.parquet
  let _ ← query (s!"COPY (SELECT g.setting, g.joint, g.label, g.i, g.in_x, g.in_y, g.in_z, " ++
    s!"g.cpp_out_x, g.cpp_out_y, g.cpp_out_z, l.lean_out_x, l.lean_out_y, l.lean_out_z, " ++
    s!"g.move_deg AS cpp_move_deg, {angSql "g.in" "l.lean_out"} AS lean_move_deg, " ++
    s!"{angSql "g.cpp_out" "l.lean_out"} AS err_deg " ++
    s!"FROM read_parquet('{gt}') g JOIN read_parquet('data/lean_out.parquet') l USING (setting, joint, i)) " ++
    s!"TO 'data/validation.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)")
  -- report
  let sumr ← query "SELECT label, count(*) AS n, sum(CASE WHEN cpp_move_deg > 0.01 THEN 1 ELSE 0 END) AS cpp_moved, sum(CASE WHEN lean_move_deg > 0.01 THEN 1 ELSE 0 END) AS lean_moved, max(err_deg) AS max_err FROM read_parquet('data/validation.parquet') GROUP BY label, setting, joint ORDER BY setting, joint"
  IO.println "\nper joint: C++ moved / Lean moved / max |C++-Lean| error (deg)"
  let lbl := sumr.column "label"; let nn := sumr.column "n"
  let cm := sumr.column "cpp_moved"; let lm := sumr.column "lean_moved"; let me := sumr.column "max_err"
  for k in [0:sumr.numRows] do
    IO.println s!"  {lbl[k]!}  C++ {cm[k]!}/{nn[k]!}  Lean {lm[k]!}/{nn[k]!}  max_err {me[k]!}"
  let mx ← query "SELECT max(err_deg) AS m FROM read_parquet('data/validation.parquet')"
  let maxErr := (mx.columnFloat "m")[0]!
  IO.println s!"\noverall max |C++ - Lean| = {maxErr} deg (tolerance 0.5)"
  if maxErr < 0.5 then
    IO.println "PASS: Lean port reproduces the C++ ground truth point for point"
  else
    IO.println "FAIL: Lean port diverges from the C++ ground truth"
  IO.println "wrote data/validation.parquet (zstd)"
