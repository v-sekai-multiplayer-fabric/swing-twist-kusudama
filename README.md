# swing-twist-kusudama

A **Lean 4 + [Plausible](https://github.com/leanprover-community/plausible)** simulation of
`SwingTwistIK3D` with a `JointLimitationKusudama3D` on a Godot Engine **scene tree**, driven by a
**JSON-LD** scene description. It reproduces — and adversarially proves — a real failure:

> Going from target keyframe position `(0,0,5)` to `(0,5,0)` breaks during **linear and cubic**
> interpolation because the swing passes through the **forbidden area** between two cones that are
> not directly bridged.

Part of the sim-first workflow for the v-sekai multiplayer fabric IK work: we make a change work in
Lean/Plausible **first** (seconds) before rebuilding the Godot engine (minutes).

## The bug, in one paragraph

The kusudama allows a bone's forward direction inside a union of **cones** joined by **tangent-circle
bridges**. Bridges only join *consecutive* cones. The live scene authors the cones in the order
`[+Y, +X, +Z]`, so the bridges are `+Y↔+X` and `+X↔+Z` — **`+Y` and `+Z` are never directly
bridged**. The target sweep `(0,0,5)→(0,5,0)` (animation seconds **t=6→7**) drives the aim straight
from `+Z` toward `+Y`, passing through `+Y+Z`, which is in no cone and on no bridge. Without a clamp
the bone follows the target into that gap. The fix is the kusudama **clamp**: project the aim onto
the region every frame.

## Layout

| File | What |
|---|---|
| `data/scene.jsonld` | The Godot scene as JSON-LD, **imported from the live editor via the godot MCP** (`Skeleton3D`, the IK node + its cones, the `Marker3D` 9-key position track). |
| `SwingTwistKusudama/Vec.lean` | 3-vectors + `make_space` (matches `joint_limitation_3d.cpp`). |
| `SwingTwistKusudama/Scene.lean` | JSON-LD → typed `Scene` (cones, keyframes, interpolation, bone origin). |
| `SwingTwistKusudama/Sim.lean` | The scene-tree animation + SwingTwist aim (from the bone base) + kusudama region + clamp. |
| `SwingTwistKusudama/Sweep.lean` | The `Probe` generator + breakage/fix predicates. |
| `Adversarial.lean` | The Plausible `#eval` checks (run on demand). |
| `Main.lean` | Loads the JSON-LD and prints the forbidden spans per interpolation. |

## Run

```bash
lake build          # builds the library + the `sim` executable
lake exe sim        # loads data/scene.jsonld, prints forbidden spans (linear & cubic)
lake env lean Adversarial.lean   # the adversarial Plausible run (BUG -> counterexample; FIX -> none)
```

`lake exe sim` on the imported live scene prints:

```
loaded data/scene.jsonld: 3 cones, 9 keyframes over 8.000000s, interp=linear
  [linear] forbidden spans (unclamped target outside the region):
      t in [6.195556s, 6.826667s]      <- the (0,0,5)->(0,5,0) segment
      t in [7.182222s, 7.813333s]
    linear: 142/901 samples forbidden; kusudama clamp keeps every frame in region: true
  [cubic]  forbidden spans (unclamped target outside the region):
      t in [6.240000s, 6.782222s]
      t in [7.226667s, 7.768889s]
    cubic: 122/901 samples forbidden; kusudama clamp keeps every frame in region: true
```

`lake env lean Adversarial.lean`:

```
=== BUG: the (0,0,5)->(0,5,0) sweep stays in the region (linear AND cubic) -- expect COUNTEREXAMPLE ===
Found a counter-example!     p := { interpCubic := true, t := 15, ... }
=== FIX: the kusudama clamp projects every frame -- expect NO counterexample ===
Unable to find a counter-example
```

## Importing your own scene

`data/scene.jsonld` was produced from the running editor with the godot MCP bridge (`run_script`),
reading the IK node's cones / `right_axis` / extension, the bone's global rest origin, and the
`AnimationPlayer` track's keys + interpolation. Drop in any scene with the same shape and the sim
runs over its whole timeline.

## What the fix proves (and its limit)

The clamp keeps the bone inside the region for **any** interpolation — the projection is per-frame,
so linear/cubic/step all stay legal. It does **not** make the motion *smooth* across the gap: since
`+Y` and `+Z` aren't bridged, the projection snaps between cones at the medial axis (a teleport). For
smooth motion either author the swept pair adjacent (`[+Y, +Z, +X]`) or use a continuous basepoint
retraction (see `KusExp.lean` in the godot fork).
