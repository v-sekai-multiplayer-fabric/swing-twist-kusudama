import SwingTwistKusudama
/-! Adversarial: `lake env lean Adversarial.lean`. The faithful kusudama port is a NO-OP, so
"the projection leaves a random direction unchanged" has NO counterexample (matching the C++). -/
open SwingTwistKusudama
#eval "=== the faithful kusudama projection is a NO-OP for random directions (matches C++ 0/60) -- expect NO counterexample ==="
#eval Plausible.Testable.check (cfg := { numInst := 6000 }) (∀ p : Dir, projectionIsNoOp p = true)
