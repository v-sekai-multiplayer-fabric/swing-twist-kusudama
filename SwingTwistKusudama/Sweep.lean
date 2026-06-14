import Plausible
import SwingTwistKusudama.Vec
import SwingTwistKusudama.Scene
import SwingTwistKusudama.Sim

/-!
# Sweep — adversarial proof that the (0,0,5) -> (0,5,0) sweep enters the forbidden area.

Plausible-checks, for BOTH linear and cubic interpolation:
  * BUG: 'the swept target stays inside the allowed region' has a counterexample (it passes through
    +Y+Z, which is in no cone and on no bridge because the cones are authored [+Y, +X, +Z]).
  * FIX: 'the clamp projects the sweep onto the region every frame' has NO counterexample.
-/

namespace SwingTwistKusudama

/-- The failing scene, as Lean constants (identical to `data/scene.jsonld`; `Main` verifies the
JSON-LD parses to this). -/
def liveScene (interp : String) : Scene :=
  { cones := [⟨⟨0,1,0⟩, 10.0⟩, ⟨⟨1,0,0⟩, 10.0⟩, ⟨⟨0,0,1⟩, 10.0⟩]
    rightAxis := "none", endBoneLength := 6.0, restForward := yAxis, boneOrigin := ⟨0,2,0⟩, interpolation := interp
    keys := [⟨6.0, ⟨0,0,5⟩⟩, ⟨7.0, ⟨0,5,0⟩⟩] }

/-- A probe direction: the swept target at parameter `t/100`, jittered by `jEl` degrees so the band
around the sweep is covered, not just the centre line. -/
structure Probe where
  interpCubic : Bool
  t : Nat       -- 0..100
  jEl : Nat     -- 0..20 deg
  jAz : Nat     -- 0..359
deriving Repr

def probeDir (p : Probe) : V3 :=
  let sc := liveScene (if p.interpCubic then "cubic" else "linear")
  let base := V3.norm (targetAt sc (Float.ofNat p.t / 100.0))
  let el := d2r (Float.ofNat p.jEl)
  let az := d2r (Float.ofNat p.jAz)
  let e1 := V3.norm (V3.cross base (if Float.abs base.y < 0.9 then yAxis else zAxis))
  let e2 := V3.norm (V3.cross base e1)
  V3.norm (V3.add (V3.smul (Float.cos el) base)
    (V3.smul (Float.sin el) (V3.add (V3.smul (Float.cos az) e1) (V3.smul (Float.sin az) e2))))

def sceneOf (p : Probe) : Scene := liveScene (if p.interpCubic then "cubic" else "linear")

/-- BUG: claim the swept TARGET stays inside the region. Expect a counterexample (the +Y+Z gap). -/
def targetStaysInRegion (p : Probe) : Bool := inRegion (sceneOf p) (probeDir p)

/-- FIX: the clamp projects the swept target onto the region every frame. Expect no counterexample. -/
def clampedStaysInRegion (p : Probe) : Bool := inConeUnion (sceneOf p) (projectToRegion (sceneOf p) (probeDir p))

open Plausible (Gen SampleableExt Shrinkable)
instance : Shrinkable Probe := ⟨fun _ => []⟩
instance : SampleableExt Probe :=
  SampleableExt.mkSelfContained do
    let cubic ← Gen.chooseNatLt 0 2 (by omega)
    let t ← Gen.chooseNatLt 0 101 (by omega)
    let je ← Gen.chooseNatLt 0 21 (by omega)
    let ja ← Gen.chooseNatLt 0 360 (by omega)
    pure { interpCubic := cubic.val == 1, t := t.val, jEl := je.val, jAz := ja.val }

-- The adversarial `#eval` checks live in `Adversarial.lean` (run with `lake env lean Adversarial.lean`)
-- so the library itself builds clean -- a `#eval` that finds a counterexample is error-level.

end SwingTwistKusudama
