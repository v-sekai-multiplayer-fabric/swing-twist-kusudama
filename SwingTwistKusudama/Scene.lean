import SwingTwistKusudama.Vec

/-!
# Scene — the live Godot scene as Lean constants.

The scene is **archived as Parquet (zstd)** under `data/` (`scene_cones.parquet`,
`scene_keys.parquet`, `kusudama_ground_truth.parquet`) — that is the interchange/archival form, read
back with [lean-duckdb](https://github.com/v-sekai-multiplayer-fabric/lean-duckdb) (or any DuckDB).
These constants are the same values, imported from the running editor via the godot MCP, kept inline
so the core sim builds without a native DuckDB dependency.
-/

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
  rightAxis : String      -- "none" | "plusZ"
  endBoneLength : R
  restForward : V3
  boneOrigin : V3
  interpolation : String  -- "linear" | "cubic"
  keys : List Keyframe
deriving Repr, Inhabited

/-- The live `node_3d` scene (MCP-imported): FABRIK3D/SwingTwistIK3D on Bone.002, kusudama with three
10° cones at +Y/+X/+Z (right_axis NONE), a 9-key linear Marker3D position track. -/
def liveScene (interp : String := "linear") : Scene :=
  { cones :=
      [ ⟨⟨0.0, 1.0, 0.0⟩, 9.9999997⟩
      , ⟨⟨1.0, 0.0, 0.0⟩, 9.9999997⟩
      , ⟨⟨0.0, 0.0169989205896854, 0.999855518341064⟩, 9.9999997⟩ ]
    rightAxis := "none", endBoneLength := 6.0, restForward := yAxis, boneOrigin := ⟨0, 2, 0⟩
    interpolation := interp
    keys :=
      [ ⟨0.0, ⟨0,0,0⟩⟩, ⟨1.0, ⟨5,0,0⟩⟩, ⟨2.0, ⟨0,5,0⟩⟩, ⟨3.0, ⟨5,0,0⟩⟩, ⟨4.0, ⟨0,0,5⟩⟩
      , ⟨5.0, ⟨5,0,0⟩⟩, ⟨6.0, ⟨0,0,5⟩⟩, ⟨7.0, ⟨0,5,0⟩⟩, ⟨8.0, ⟨0,0,5⟩⟩ ] }

end SwingTwistKusudama
