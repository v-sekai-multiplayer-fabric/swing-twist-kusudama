import SwingTwistKusudama.Vec

/-!
# Kusudama — a FAITHFUL port of Godot's `JointLimitationKusudama3D::_continuous_project`.

Unlike the earlier `Kusudama.lean` proxy in the godot fork (which omitted the tangent bridges), this
ports the actual algorithm:

  * each cone contributes a **keep-in** soft-saturated candidate (`softCone`),
  * each consecutive cone pair contributes two **tangent circles** (`tangentCircles`), each a
    **keep-out** soft-saturated candidate (`softTangent`),
  * the candidates are blended by a one-step weighted **Karcher (spherical) mean** anchored at the
    nearest one (temperature 0.22), with an exact-identity fast path when the input is already inside.

`tangentCircles` is computed geometrically (the two points tangent to both cones), which is
equivalent to Godot's `compute_tangent_circles` plane/ray/sphere construction.
-/

namespace SwingTwistKusudama

structure KCone where
  c : V3      -- normalized center
  r : R       -- radius (radians)
deriving Repr, Inhabited

/-- A tangent-circle bridge between two consecutive cones: the two keep-out centers + their radius. -/
structure Tangent where
  t1 : V3
  t2 : V3
  r : R
deriving Repr, Inhabited

/-- Log map at `a` toward `b`: tangent at `a`, magnitude = geodesic distance. -/
def logMap (a b : V3) : V3 :=
  let d := V3.angle a b
  if d < 1e-9 then ⟨0,0,0⟩
  else V3.smul d (V3.norm (V3.sub b (V3.smul (V3.dot a b) a)))

/-- Exp map at `a` with tangent `v`. -/
def expMap (a v : V3) : V3 :=
  let n := V3.len v
  if n < 1e-9 then a
  else V3.norm (V3.add (V3.smul (Float.cos n) a) (V3.smul (Float.sin n / n) v))

def anyPerp (a : V3) : V3 :=
  let t := if Float.abs a.x ≤ Float.abs a.y && Float.abs a.x ≤ Float.abs a.z then (⟨1,0,0⟩ : V3)
           else if Float.abs a.y ≤ Float.abs a.z then (⟨0,1,0⟩ : V3) else (⟨0,0,1⟩ : V3)
  V3.norm (V3.cross a t)

/-- `SOFT_BAND = max(0.01, cushion)`; Godot defaults cushion to 0.06. -/
def softBand : R := 0.06

/-- Keep-in candidate for cone `k`: the input's angle to the center, saturated toward the radius
from BELOW (never exceeding it), rebuilt in the perp plane. Mirrors `k_soft_saturated(..., true)`. -/
def softCone (p : V3) (k : KCone) : V3 :=
  let th := V3.angle p k.c
  let thSat := if th > k.r - softBand
               then k.r - softBand * Float.exp (-(th - (k.r - softBand)) / softBand)
               else th
  let perp0 := V3.sub p (V3.smul (V3.dot p k.c) k.c)
  let perp := V3.norm (if V3.isZero perp0 then anyPerp k.c else perp0)
  V3.norm (V3.add (V3.smul (Float.cos thSat) k.c) (V3.smul (Float.sin thSat) perp))

/-- Keep-out candidate for a tangent circle centered at `center` radius `lim`: angle saturated
toward `lim` from ABOVE (never entering the forbidden lens). Mirrors `k_soft_saturated(..., false)`. -/
def softTangent (p center : V3) (lim : R) : V3 :=
  let th := V3.angle p center
  let thSat := if th < lim + softBand
               then lim + softBand * Float.exp (-((lim + softBand) - th) / softBand)
               else th
  let perp0 := V3.sub p (V3.smul (V3.dot p center) center)
  let perp := V3.norm (if V3.isZero perp0 then anyPerp center else perp0)
  V3.norm (V3.add (V3.smul (Float.cos thSat) center) (V3.smul (Float.sin thSat) perp))

/-- The two tangent circles bridging cones (c1,r1) and (c2,r2). `tr = max(0, (pi-(r1+r2))/2)` (the
negative case clamped per the C++ guard). Each tangent center `t` satisfies angle(t,c1)=r1+tr and
angle(t,c2)=r2+tr; there are two, one on each side of the c1-c2 great circle. -/
def tangentCircles (c1 : V3) (r1 : R) (c2 : V3) (r2 : R) : Tangent :=
  let tr := let v := (pi - (r1 + r2)) / 2.0; if v < 0.0 then 0.0 else v
  let a1 := r1 + tr
  let a2 := r2 + tr
  let ct := V3.dot c1 c2
  let s2 := 1.0 - ct * ct
  if s2 < 1e-12 then
    -- parallel / antipodal centers: tangent circles 90deg off, on a perpendicular.
    let perp := anyPerp c1
    { t1 := rotAxis c1 tr perp, t2 := rotAxis c1 (-tr) perp, r := tr }
  else
    let alpha := (Float.cos a1 - Float.cos a2 * ct) / s2
    let beta := (Float.cos a2 - Float.cos a1 * ct) / s2
    let p := V3.add (V3.smul alpha c1) (V3.smul beta c2)
    let nHat := V3.norm (V3.cross c1 c2)
    let g2 := 1.0 - V3.dot p p
    let g := Float.sqrt (if g2 < 0.0 then 0.0 else g2)
    { t1 := V3.norm (V3.add p (V3.smul g nHat)), t2 := V3.norm (V3.sub p (V3.smul g nHat)), r := tr }

/-- Tangent bridges for consecutive cone pairs (the only ones Godot bridges). -/
def bridges (cones : List KCone) : List Tangent :=
  (cones.zip (cones.drop 1)).map (fun (a, b) => tangentCircles a.c a.r b.c b.r)

/-- Godot's `_continuous_project`: weighted Karcher mean of the cone keep-in + tangent keep-out
soft-saturated candidates, anchored at the nearest, with an exact-identity fast path. -/
def continuousProject (cones : List KCone) (p0 : V3) (temperature : R := 0.22) : V3 :=
  let p := V3.norm p0
  match cones with
  | [] => p
  | [k] =>
    -- single cone: identity inside, hard projection to the boundary outside (matches `_solve` n==1).
    let th := V3.angle p k.c
    if th ≤ k.r then p
    else
      let perp0 := V3.sub p (V3.smul (V3.dot p k.c) k.c)
      let perp := V3.norm (if V3.isZero perp0 then anyPerp k.c else perp0)
      V3.norm (V3.add (V3.smul (Float.cos k.r) k.c) (V3.smul (Float.sin k.r) perp))
  | cones =>
    let coneC := cones.map (fun k => let q := softCone p k; (q, V3.angle p q))
    let tanC := (bridges cones).flatMap (fun b =>
      [ (let q := softTangent p b.t1 b.r; (q, V3.angle p q))
      , (let q := softTangent p b.t2 b.r; (q, V3.angle p q)) ])
    let cd := coneC ++ tanC
    let dmin := cd.foldl (fun m x => if x.2 < m then x.2 else m) 1e30
    if dmin < 1e-5 then p else
      let anchor := (cd.foldl (fun (best : V3 × R) x => if x.2 < best.2 then x else best) (⟨0,1,0⟩, 1e30)).1
      let w := fun (d : R) => Float.exp (-(d - dmin) / temperature)
      let num := cd.foldl (fun (s : V3) x => V3.add s (V3.smul (w x.2) (logMap anchor x.1))) ⟨0,0,0⟩
      let den := cd.foldl (fun (s : R) x => s + w x.2) 0.0
      if den ≤ 1e-30 then p else expMap anchor (V3.smul (1.0/den) num)

end SwingTwistKusudama
