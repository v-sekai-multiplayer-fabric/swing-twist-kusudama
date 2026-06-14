# swing-twist-kusudama

A **Lean 4 + [Plausible](https://github.com/leanprover-community/plausible)** simulation of
`SwingTwistIK3D` with a `JointLimitationKusudama3D` on a Godot Engine **scene tree**, driven by a
**JSON-LD** scene description. It reproduces — and adversarially proves — a real failure:

> Going from target keyframe position `(0,0,5)` to `(0,5,0)` breaks during **linear and cubic**
> interpolation because the swing passes through the **forbidden area** between two cones that are
> not directly bridged.

Part of the sim-first workflow for the v-sekai multiplayer fabric IK work: we make a change work in
Lean/Plausible **first** (seconds) before rebuilding the Godot engine (minutes).

## Importing your own scene

`data/scene.jsonld` was produced from the running editor with the godot MCP bridge (`run_script`),
reading the IK node's cones / `right_axis` / extension, the bone's global rest origin, and the
`AnimationPlayer` track's keys + interpolation. Drop in any scene with the same shape and the sim
runs over its whole timeline.
