import SwingTwistKusudama

open SwingTwistKusudama

/-- The same Fibonacci sphere the godot MCP ground-truth dump used (N=200 per joint). -/
def fibSphere (n : Nat) : Array V3 := Id.run do
  let ga : R := pi * (3.0 - Float.sqrt 5.0)
  let mut out := #[]
  for i in [0:n] do
    let y := 1.0 - (Float.ofNat i / Float.ofNat (n-1)) * 2.0
    let rad := Float.sqrt (let q := 1.0 - y*y; if q < 0.0 then 0.0 else q)
    let th := ga * Float.ofNat i
    out := out.push (V3.norm ⟨Float.cos th * rad, y, Float.sin th * rad⟩)
  return out

def fmt (x : R) : String := toString x

/-- Run the faithful kusudama port on the live humanoid rig's rich joints and write the port's
outputs on the 200-direction sphere, keyed by `setting,joint,i`. Lean emits text only, so this is a
transient `data/lean_out.csv`; `scripts/validate.py` ingests it into `data/lean_out.parquet` (zstd),
deletes the CSV, and joins it against `data/humanoid_ground_truth.parquet` (the C++ ground truth)
point for point. -/
def main (_args : List String) : IO Unit := do
  let dirs := fibSphere 200
  let mut csv := "setting,joint,i,in_x,in_y,in_z,lean_out_x,lean_out_y,lean_out_z\n"
  for (s, j, label, cones) in humanoidJoints do
    let mut nonzero := 0
    for i in [0:dirs.size] do
      let d := dirs[i]!
      let o := continuousProject cones d 0.22
      if V3.angle o d > d2r 0.01 then nonzero := nonzero + 1
      csv := csv ++ s!"{s},{j},{i},{fmt d.x},{fmt d.y},{fmt d.z},{fmt o.x},{fmt o.y},{fmt o.z}\n"
    IO.println s!"  s{s}/j{j} {label} ({cones.length} cones): {nonzero}/{dirs.size} directions moved by the port"
  IO.FS.writeFile "data/lean_out.csv" csv
  IO.println "wrote transient data/lean_out.csv (run scripts/validate.py to fold it into data/lean_out.parquet and compare vs data/humanoid_ground_truth.parquet)"
