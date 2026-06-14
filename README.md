# swing-twist-kusudama

A **Lean 4 + [Plausible](https://github.com/leanprover-community/plausible)** simulation of
`SwingTwistIK3D` with a `JointLimitationKusudama3D`, driven by a real Godot scene and checked against
the engine's own output. Part of the sim-first workflow for the v-sekai multiplayer fabric IK work: a
change works in Lean/Plausible **first** (seconds) before a Godot rebuild (minutes).

## The active scene

`data/humanoid_*.parquet` holds the live humanoid rig pulled from the running editor via the godot
MCP bridge (`GeneralSkeleton/HumanoidRomIK`, a `SwingTwistIK3D`): five chains (arms, legs,
spine→head), seventeen kusudama joints, sixty-five cones, plus the goal/pole `Marker3D` transforms.
Every value is the engine's own (`get_cone_center`, `get_bone_global_rest`), so the Parquet is ground
truth.

- `humanoid_meta.parquet` — scene/node paths, iteration and distance settings.
- `humanoid_joints.parquet` — per joint: chain bones, extension, rest origin, axes, rotation offset,
  cushion, strength, twist range, blend weights, target node.
- `humanoid_cones.parquet` — per cone: unit-vector center + radius (radians), keyed (setting, joint, cone).
- `humanoid_targets.parquet` — goal/pole marker transforms (position + quaternion).
- `humanoid_ground_truth.parquet` — the four rich multi-cone joints (LeftLowerArm, LeftHand, LeftFoot,
  Head), each `solve`d over a 200-direction Fibonacci sphere: `in_xyz` → `cpp_out_xyz` + `move_deg`.

The Lean cone constants live in `SwingTwistKusudama/Humanoid.lean`, generated from
`humanoid_cones.parquet` by `scripts/gen_humanoid_lean.py` so the two stay in lockstep.

## Validating the port against C++

`lake exe sim` runs the faithful port (`continuousProject`) over the same joints and sphere. Lean
emits text only, so it writes a transient `data/lean_out.csv`; `python3 scripts/validate.py` folds
that into `data/lean_out.parquet` (zstd), deletes the CSV, then joins it to
`humanoid_ground_truth.parquet` on (setting, joint, i) and reports the per-point angular error. The
`data/` directory stays Parquet-only.

The current result: every joint is a NO-OP — `solve` returns each sphere direction unchanged, and the
port reproduces that point for point (max |C++ − Lean| = 0.00004°). The cones cover a wide keep-in
region and the tangent keep-out candidates sit at distance 0 outside their lens, so `min_dist < 1e-5`
takes the identity fast-path. So "the bone goes through the forbidden area" reflects a constraint that
never clamps over the swing sphere, not a teleport.

## Re-importing the scene

Dump the open scene from the editor with the godot MCP bridge (`run_script`), reading the IK node's
settings/joints/limitation cones and the goal markers, then `python3 scripts/scene_to_parquet.py`
writes the `humanoid_*.parquet` set (zstd) and `scripts/gen_humanoid_lean.py` regenerates the Lean
constants. The older toy scene (three 10° cones at +Y/+X/+Z) stays in `data/scene_cones.parquet` /
`data/kusudama_ground_truth.parquet` for reference.

Parquet loads back through
[lean-duckdb](https://github.com/v-sekai-multiplayer-fabric/lean-duckdb) or any DuckDB.
