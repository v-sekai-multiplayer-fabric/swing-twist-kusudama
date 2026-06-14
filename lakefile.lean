import Lake
open Lake DSL System

package «swing_twist_kusudama» where

require plausible from git
  "https://github.com/leanprover-community/plausible" @ "main"

-- Parquet/CSV/JSON I/O for the sim, via the DuckDB FFI library. `lake update lean_duckdb` vendors the
-- DuckDB binary into the dependency checkout automatically (its post_update hook).
require lean_duckdb from git
  "https://github.com/v-sekai-multiplayer-fabric/lean-duckdb" @ "main"

-- DuckDB link args for the I/O executables. The FFI shim (extern_lib) links automatically; the shared
-- libduckdb.so lives in moreLinkArgs, which Lake does not propagate, so point at the dependency's
-- vendored copy. The rpath resolves it at run time relative to the exe in .lake/build/bin/.
def duckdbLinkArgs : Array String := #[
  "-L.lake/packages/lean_duckdb/vendor", "-lduckdb",
  "-Wl,-rpath,$ORIGIN/../../packages/lean_duckdb/vendor"
]

-- The core sim + the kusudama port (no native dependency).
@[default_target]
lean_lib «SwingTwistKusudama» where

-- Moved from godot/misc/humanoid_kusudama_rom/lean (the original "kusudama" project).
lean_lib «Kusudama» where
lean_lib «WristRom» where
lean_lib «JointRom» where
lean_lib «IKFold» where
lean_lib «IKFast» where
lean_lib «IKJerk» where
lean_lib «IKBlock» where

-- The simulation: read the humanoid scene from Parquet, run the kusudama port, write outputs +
-- validation back to Parquet.
@[default_target]
lean_exe «sim» where
  root := `Main
  moreLinkArgs := duckdbLinkArgs

-- Import an MCP-dumped scene (transient JSON) into the humanoid_*.parquet set.
lean_exe «import-scene» where
  root := `SceneImport
  moreLinkArgs := duckdbLinkArgs
