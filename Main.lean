import SwingTwistKusudama

open SwingTwistKusudama

/-- Load `data/scene.jsonld`, run the SwingTwist+kusudama sim over the sweep, and report the frames
where the (unclamped) target enters the forbidden area — for linear and cubic interpolation. -/
def main (args : List String) : IO Unit := do
  let path := args.headD "data/scene.jsonld"
  let src ← IO.FS.readFile path
  match Scene.parse src with
  | .error e => throw <| IO.userError s!"scene parse failed: {e}"
  | .ok base =>
    let length := (base.keys.getLast?.map (·.time)).getD 1.0
    IO.println s!"loaded {path}: {base.cones.length} cones, {base.keys.length} keyframes over {length}s, interp={base.interpolation}"
    -- Sweep the whole animation timeline in seconds; report each forbidden span (per interpolation).
    for interp in ["linear", "cubic"] do
      let sc := { base with interpolation := interp }
      let steps := 900
      let mut forbidden := 0
      let mut clampOk := true
      let mut prevForb := false
      let mut spanStart : R := 0.0
      IO.println s!"  [{interp}] forbidden spans (unclamped target outside the region):"
      for f in [0:steps+1] do
        let secs := Float.ofNat f / Float.ofNat steps * length
        let tnorm := if length > 1e-9 then secs / length else 0.0
        let d := V3.norm (targetAt sc tnorm)
        let forb := !(inRegion sc d)
        if !(inConeUnion sc (solve sc tnorm)) then clampOk := false
        if forb then forbidden := forbidden + 1
        if forb && !prevForb then spanStart := secs
        if !forb && prevForb then IO.println s!"      t in [{spanStart}s, {secs}s]"
        prevForb := forb
      if prevForb then IO.println s!"      t in [{spanStart}s, {length}s]"
      IO.println s!"    {interp}: {forbidden}/{steps+1} samples forbidden; kusudama clamp keeps every frame in region: {clampOk}"
