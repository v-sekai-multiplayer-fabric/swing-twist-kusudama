import Lean.Data.Json
import SwingTwistKusudama.Vec

/-!
# Scene — parse the Godot scene tree from JSON-LD.

Reads `data/scene.jsonld` into a typed `Scene`: the kusudama cones, the target's position keyframes,
and the interpolation mode. JSON-LD is used so the scene is self-describing linked data (the
`@context`/`@type`/`@vocab` make every node and field a resolvable term).
-/

open Lean (Json)

namespace SwingTwistKusudama

structure Cone where
  center : V3
  radiusDeg : R
deriving Repr, Inhabited

structure Keyframe where
  time : R
  position : V3
deriving Repr, Inhabited

structure Scene where
  cones : List Cone
  rightAxis : String      -- "none" | "plusZ" | ...
  endBoneLength : R
  restForward : V3        -- the bone's rest extension direction (here +Y)
  boneOrigin : V3         -- the end bone's global rest origin (the aim base)
  interpolation : String  -- "linear" | "cubic"
  keys : List Keyframe
deriving Repr, Inhabited

namespace Json'
open Lean

def num (j : Json) : R := (j.getNum?.toOption.map (·.toFloat)).getD 0.0
def field (j : Json) (k : String) : Option Json := (j.getObjVal? k).toOption
def arr (j : Json) : Array Json := (j.getArr?.toOption).getD #[]
def str (j : Json) (k : String) : String := ((j.getObjVal? k).bind (·.getStr?)).toOption.getD ""

/-- A `{ "vec": [x,y,z] }` JSON-LD list value -> V3. -/
def vec (j : Json) : V3 :=
  match field j "vec" with
  | some v => let a := arr v; ⟨num (a.getD 0 (Json.num 0)), num (a.getD 1 (Json.num 0)), num (a.getD 2 (Json.num 0))⟩
  | none => ⟨0,0,0⟩

end Json'

open Json'

/-- Find the first node of a given `@type` in the scene's `nodes` list. -/
def findNode (root : Json) (ty : String) : Option Json :=
  (arr ((field root "nodes").getD (Json.arr #[]))).find? (fun n => str n "@type" == ty)

private def note {α} (o : Option α) (msg : String) : Except String α :=
  match o with | some a => .ok a | none => .error msg

/-- Find the IK node: any node carrying a kusudama `limitation` (FABRIK3D / CCDIK3D / SwingTwistIK3D
all share the same limitation API). -/
def findIK (root : Json) : Option Json :=
  (arr ((field root "nodes").getD (Json.arr #[]))).find? (fun n => (field n "limitation").isSome)

/-- Parse a `Scene` from a parsed JSON-LD document. -/
def Scene.ofJson (root : Json) : Except String Scene := do
  let ik ← note (findIK root) "no IK node with a limitation"
  let lim ← note (field ik "limitation") "IK has no limitation"
  let cones := (arr ((field lim "cones").getD (Json.arr #[]))).toList.map fun c =>
    { center := vec ((field c "center").getD Json.null), radiusDeg := num ((field c "radiusDegrees").getD (Json.num 0)) }
  let tgtName := str ik "targetNode"
  let marker ← note ((arr ((field root "nodes").getD (Json.arr #[]))).find?
      (fun n => str n "@type" == "Marker3D" && str n "name" == tgtName)) "target Marker3D not found"
  let track ← note (field marker "positionTrack") "marker has no positionTrack"
  let keys := (arr ((field track "keys").getD (Json.arr #[]))).toList.map fun k =>
    { time := num ((field k "time").getD (Json.num 0)), position := vec ((field k "position").getD Json.null) }
  return {
    cones, rightAxis := str ik "rightAxis", endBoneLength := num ((field ik "endBoneLength").getD (Json.num 1))
    restForward := yAxis, boneOrigin := vec ((field ik "boneGlobalOrigin").getD Json.null)
    interpolation := str track "interpolation", keys
  }

/-- Parse a `Scene` from JSON-LD source text. -/
def Scene.parse (s : String) : Except String Scene := do
  let j ← Json.parse s
  Scene.ofJson j

end SwingTwistKusudama
