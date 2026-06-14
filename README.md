# swing-twist-kusudama

A **Lean 4 + [Plausible](https://github.com/leanprover-community/plausible)** simulation of
`SwingTwistIK3D` with a `JointLimitationKusudama3D`, driven by a real Godot scene and checked against
the engine's own output. Part of the sim-first workflow for the v-sekai multiplayer fabric IK work: a
change works in Lean/Plausible **first** (seconds) before a Godot rebuild (minutes).

## Datasets

The Parquet datasets are **GitHub release artifacts**, not committed in-tree (`data/*.parquet` is
gitignored). Fetch them into `data/` with `data/fetch.sh` (or
`gh release download datasets-v1 --repo v-sekai-multiplayer-fabric/swing-twist-kusudama --dir data
--pattern '*.parquet'`). After regenerating, re-upload with `gh release upload datasets-v1
data/*.parquet --clobber`. The set includes the avatar rig (`humanoid_*`), the C++ ground truth, the
toy scene (`scene_*`), the AddBiomechanics ROM (`addbio_*_rom`), and the sim outputs
(`lean_out`/`validation`).

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

The sim reads these cones from Parquet at run time (no generated Lean source), so the Parquet is the
single source of truth.

## Validating the port against C++

The toolchain is Lean only — Parquet I/O goes through
[lean-duckdb](https://github.com/v-sekai-multiplayer-fabric/lean-duckdb) (a git dependency; its
`post_update` hook vendors the DuckDB binary on `lake update`). No Python, no CSV.

`lake exe sim` reads the cones and the C++ input directions from `data/humanoid_*.parquet`, runs the
faithful port (`continuousProject`) on the SAME inputs, writes the port output to
`data/lean_out.parquet`, then joins it against `humanoid_ground_truth.parquet` on (setting, joint, i)
and writes the per-point angular error to `data/validation.parquet`, all via DuckDB `COPY` from Lean.

The current result: every joint is a NO-OP — `solve` returns each sphere direction unchanged, and the
port reproduces that point for point (max |C++ − Lean| = 0.00004°). The cones cover a wide keep-in
region and the tangent keep-out candidates sit at distance 0 outside their lens, so `min_dist < 1e-5`
takes the identity fast-path. So "the bone goes through the forbidden area" reflects a constraint that
never clamps over the swing sphere, not a teleport.

## Re-importing the scene

Dump the open scene from the editor with the godot MCP bridge (`run_script`), writing one transient
`data/humanoid_<table>.json` per table (cones, joints, meta, targets, ground_truth). Then `lake exe
import-scene` folds each JSON into `data/humanoid_<table>.parquet` (zstd) via DuckDB `read_json_auto`
and deletes the JSON, so `data/` stays Parquet-only. The older toy scene (three 10° cones at
+Y/+X/+Z) stays in `data/scene_cones.parquet` / `data/kusudama_ground_truth.parquet` for reference.

Parquet loads back through lean-duckdb or any DuckDB.
