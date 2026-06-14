import SwingTwistKusudama.Vec
import SwingTwistKusudama.Scene

/-!
# Sim — the SwingTwistIK3D solve on the scene tree (skeleton omitted).

The single extended end bone aims its extension at the animated target (FABRIK-style), then the
kusudama clamps the swing into the allowed region. We model:

  * the scene-tree animation: interpolate the target position between keyframes (linear / cubic),
  * the SwingTwist aim: the solved extension direction == the target direction (before clamping),
  * the kusudama region: cone union + tangent BRIDGES between consecutive cones only,
  * the clamp: project a forbidden direction back onto the region.

This is enough to reproduce the live failure: the straight sweep +Z -> +Y passes through +Y+Z, which
is in no cone and on no bridge.
-/

namespace SwingTwistKusudama

/-- Godot CUBIC keyframe easing for two clamped endpoints (Catmull-Rom, pre=p0/post=p1):
`s(t) = 0.5*(t + 3 t^2 - 2 t^3)`, with `s(0)=0, s(1)=1`. Linear is `s(t)=t`. -/
def ease (interp : String) (t : R) : R :=
  if interp == "cubic" then 0.5 * (t + 3.0 * t * t - 2.0 * t * t * t) else t

/-- Interpolate the target position over the FULL keyframe timeline at animation time `time`
(seconds), as the Godot AnimationPlayer does: find the segment containing `time` and ease within it.
`time` is clamped to the track's `[first, last]` range. -/
partial def sampleTimeline (keys : List Keyframe) (interp : String) (time : R) : V3 :=
  match keys with
  | [] => ⟨0, 0, 0⟩
  | [k] => k.position
  | k0 :: k1 :: rest =>
    if time ≤ k0.time then k0.position
    else if time ≤ k1.time then
      let span := k1.time - k0.time
      let s := if span > 1e-9 then ease interp ((time - k0.time) / span) else 0.0
      V3.add k0.position (V3.smul s (V3.sub k1.position k0.position))
    else sampleTimeline (k1 :: rest) interp time

/-- Convenience: target position at normalized sweep `t ∈ [0,1]` mapped across the whole timeline. -/
def targetAt (sc : Scene) (t : R) : V3 :=
  let last := (sc.keys.getLast?.map (·.time)).getD 1.0
  sampleTimeline sc.keys sc.interpolation (t * last)

/-- The cone centers in WORLD space: canonical centers placed by make_space(restForward, right). On
the failing scene restForward = +Y and right = NONE -> shortest-arc(+Y,+Y) = identity, so the cones
sit at their canonical world directions. -/
def worldCone (sc : Scene) (k : Cone) : V3 :=
  let right := if sc.rightAxis == "plusZ" then zAxis else ⟨0, 0, 0⟩ -- NONE -> zero -> shortest-arc
  V3.norm (makeSpaceApply sc.restForward right k.center)

def inConeUnion (sc : Scene) (d : V3) : Bool :=
  sc.cones.any (fun k => V3.angle (worldCone sc k) d ≤ d2r k.radiusDeg)

/-- Consecutive cone pairs (the only ones a tangent bridge joins). -/
def adjacentPairs (sc : Scene) : List (Cone × Cone) :=
  (sc.cones.zip (sc.cones.drop 1))

/-- `d` lies on the tangent bridge of an adjacent pair: within `bridgeR` of the great-circle arc
between the two cone centers, and angularly between them. -/
def bridgeR : R := d2r 12.0
def onArc (a b d : V3) : Bool :=
  let n := V3.norm (V3.cross a b)
  let offArc := Float.abs (pi / 2.0 - V3.angle n d)
  let between := (V3.angle a d ≤ V3.angle a b) && (V3.angle b d ≤ V3.angle a b)
  (offArc ≤ bridgeR) && between

def inRegion (sc : Scene) (d : V3) : Bool :=
  inConeUnion sc d ||
  (adjacentPairs sc).any (fun pr => onArc (worldCone sc pr.1) (worldCone sc pr.2) d)

/-- The clamp: slerp `d` toward the nearest cone center until just inside the cone (0.95 * radius). -/
def nearestCone (sc : Scene) (d : V3) : Cone :=
  match sc.cones with
  | [] => { center := yAxis, radiusDeg := 0 }
  | c :: cs => cs.foldl (fun best k => if V3.dot (worldCone sc k) d > V3.dot (worldCone sc best) d then k else best) c

def projectToRegion (sc : Scene) (d : V3) : V3 :=
  let k := nearestCone sc d
  let c := worldCone sc k
  let th := V3.angle c d
  let r := d2r k.radiusDeg
  if th ≤ r then d
  else
    let tgt := r * 0.95
    let ax := V3.cross c d
    if V3.len ax < 1e-9 then d else rotAxis (V3.norm ax) (-(th - tgt)) d

/-- The bone's AIM direction at sweep `t`: from the bone's global origin to the target (what the
extended end bone points its extension along), before clamping. -/
def aimDir (sc : Scene) (t : R) : V3 :=
  let v := V3.sub (targetAt sc t) sc.boneOrigin
  if V3.isZero v then sc.restForward else V3.norm v

/-- The solved extension direction at sweep parameter `t`: aim at the target, then clamp. -/
def solve (sc : Scene) (t : R) : V3 := projectToRegion sc (aimDir sc t)

end SwingTwistKusudama
