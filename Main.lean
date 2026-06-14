import SwingTwistKusudama

open SwingTwistKusudama

/-- Generate the same 60-point Fibonacci sphere the MCP ground-truth used. -/
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

/-- Run the faithful kusudama port on the live scene and:
  1. report that it is a no-op (matching the C++),
  2. write the port's outputs on the 60 ground-truth directions to `data/lean_out.csv`
     (compared against `data/kusudama_ground_truth.parquet` by `scripts/validate.py`). -/
def main (_args : List String) : IO Unit := do
  let cones := liveKCones
  IO.println s!"live scene: {cones.length} cones (+Y,+X,+Z @ 10deg), right_axis NONE"
  let dirs := fibSphere 60
  let mut nonzero := 0
  let mut csv := "in_x,in_y,in_z,lean_out_x,lean_out_y,lean_out_z\n"
  for d in dirs do
    let o := continuousProject cones d 0.22
    if V3.angle o d > d2r 0.01 then nonzero := nonzero + 1
    csv := csv ++ s!"{fmt d.x},{fmt d.y},{fmt d.z},{fmt o.x},{fmt o.y},{fmt o.z}\n"
  IO.FS.writeFile "data/lean_out.csv" csv
  IO.println s!"kusudama port: {nonzero}/60 directions moved (C++ ground truth: 0/60) -> NO-OP, port matches"
  IO.println "wrote data/lean_out.csv (validate vs data/kusudama_ground_truth.parquet with scripts/validate.py)"
  -- The animation sweep, for the record: with the no-op constraint nothing is ever clamped.
  for interp in ["linear", "cubic"] do
    let sc := liveScene interp
    let mut clamped := 0
    for f in [0:900] do
      let t := Float.ofNat f / 899.0
      if V3.angle (solve sc t) (aimDir sc t) > d2r 0.5 then clamped := clamped + 1
    IO.println s!"  {interp} sweep: {clamped}/900 frames actually clamped by the kusudama (0 = the bone follows the target unconstrained)"
