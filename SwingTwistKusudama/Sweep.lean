import Plausible
import SwingTwistKusudama.Vec
import SwingTwistKusudama.Scene
import SwingTwistKusudama.Kusudama
import SwingTwistKusudama.Sim

/-!
# Sweep — the accurate adversarial result: the kusudama is a NO-OP.

The faithful port of `_continuous_project` (cones keep-in + tangent-circle keep-out + Karcher mean)
matches the live C++ `JointLimitationKusudama3D.solve`, which on this 3-cone scene returns **every**
direction unchanged (verified over a 60-point sphere: 0 moves; see `data/kusudama_ground_truth.parquet`).

So the constraint never clamps — that is why the bone passes "through the forbidden area": there is
no forbidden area as far as the solver is concerned. Plausible confirms it adversarially: for random
directions, the projection moves them by ~0°. (A genuinely-forbidden direction like `-Y` SHOULD be
pulled to the region; it is not.)
-/

namespace SwingTwistKusudama

/-- World cones of the live scene as `KCone`s (fwd=+Y, right NONE -> identity make_space, so canonical). -/
def liveKCones : List KCone :=
  (liveScene "linear").cones.map (fun k => { c := V3.norm k.center, r := d2r k.radiusDeg })

/-- A random unit direction from two angles. -/
structure Dir where
  el : Nat   -- 0..180
  az : Nat   -- 0..359
deriving Repr

def dirOf (p : Dir) : V3 :=
  let e := d2r (Float.ofNat p.el); let a := d2r (Float.ofNat p.az)
  ⟨Float.sin e * Float.cos a, Float.cos e, Float.sin e * Float.sin a⟩

/-- How far (deg) the faithful kusudama projection moves a direction. -/
def moveDeg (p : Dir) : R := r2d (V3.angle (continuousProject liveKCones (dirOf p) 0.22) (V3.norm (dirOf p)))

/-- THE FINDING: the kusudama is a no-op — it moves every direction by ~0°. Plausible finds NO
counterexample to "the projection leaves the direction unchanged", proving the constraint never
constrains (the bug). -/
def projectionIsNoOp (p : Dir) : Bool := moveDeg p ≤ 0.5

open Plausible (Gen SampleableExt Shrinkable)
instance : Shrinkable Dir := ⟨fun _ => []⟩
instance : SampleableExt Dir :=
  SampleableExt.mkSelfContained do
    let e ← Gen.chooseNatLt 0 181 (by omega)
    let a ← Gen.chooseNatLt 0 360 (by omega)
    pure { el := e.val, az := a.val }

-- The adversarial `#eval` lives in `Adversarial.lean`.

end SwingTwistKusudama
