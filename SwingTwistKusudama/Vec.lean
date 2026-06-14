/-!
# Vec — 3-vectors, make_space, and rotations on the unit sphere.

Ported from the proven `KusSweep.lean` model in the godot fork. `makeSpaceApply` matches Godot's
`JointLimitation3D::make_space` exactly (the frame the kusudama cones are placed in): the cones are
stored CANONICAL (+Y forward) and oriented by make_space(forward, right).
-/

namespace SwingTwistKusudama

abbrev R := Float
def pi : R := 3.14159265358979323846
def d2r (x : R) : R := x * pi / 180.0
def r2d (x : R) : R := x * 180.0 / pi
def clamp1 (x : R) : R := if x < -1.0 then -1.0 else if x > 1.0 then 1.0 else x

structure V3 where
  x : R
  y : R
  z : R
deriving Repr, Inhabited, BEq

namespace V3
def dot (a b : V3) : R := a.x * b.x + a.y * b.y + a.z * b.z
def cross (a b : V3) : V3 := ⟨a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x⟩
def len (a : V3) : R := Float.sqrt (dot a a)
def smul (s : R) (a : V3) : V3 := ⟨s * a.x, s * a.y, s * a.z⟩
def add (a b : V3) : V3 := ⟨a.x + b.x, a.y + b.y, a.z + b.z⟩
def sub (a b : V3) : V3 := ⟨a.x - b.x, a.y - b.y, a.z - b.z⟩
def norm (a : V3) : V3 := let l := len a; if l > 1e-12 then smul (1.0 / l) a else a
def angle (a b : V3) : R := Float.acos (clamp1 (dot (norm a) (norm b)))
def isZero (a : V3) : Bool := len a < 1e-9
end V3

def yAxis : V3 := ⟨0, 1, 0⟩
def zAxis : V3 := ⟨0, 0, 1⟩

/-- Rodrigues: rotate `v` about unit axis `k` by angle `t`. -/
def rotAxis (k : V3) (t : R) (v : V3) : V3 :=
  let c := Float.cos t; let s := Float.sin t
  V3.add (V3.add (V3.smul c v) (V3.smul s (V3.cross k v))) (V3.smul (V3.dot k v * (1.0 - c)) k)

/-- Shortest-arc rotation +Y -> fwd applied to v (make_space's fallback when right is zero/parallel). -/
def shortestArcYApply (fwd v : V3) : V3 :=
  let f := V3.norm fwd
  let ax := V3.cross yAxis f
  if V3.len ax < 1e-9 then (if V3.dot yAxis f > 0.0 then v else ⟨v.x, -v.y, -v.z⟩)
  else rotAxis (V3.norm ax) (V3.angle yAxis f) v

/-- `make_space(forward, right)` applied to a canonical vector `c`, exactly as
`joint_limitation_3d.cpp`: axis_y = forward; axis_x = right; if parallel/zero -> shortest-arc(+Y,
forward); else axis_z = (axis_x x axis_y)^, axis_x = (axis_y x axis_z)^; Basis(axis_x, axis_y, axis_z) * c. -/
def makeSpaceApply (fwd right c : V3) : V3 :=
  let ay := V3.norm fwd
  let ax0 := V3.norm right
  let parallelOrZero := (V3.len fwd < 1e-9) || (V3.len right < 1e-9) || (Float.abs (V3.dot ax0 ay) > 1.0 - 1e-6)
  if parallelOrZero then shortestArcYApply fwd c
  else
    let az := V3.norm (V3.cross ax0 ay)
    let ax := V3.norm (V3.cross ay az)
    ⟨ax.x * c.x + ay.x * c.y + az.x * c.z,
     ax.y * c.x + ay.y * c.y + az.y * c.z,
     ax.z * c.x + ay.z * c.y + az.z * c.z⟩

end SwingTwistKusudama
