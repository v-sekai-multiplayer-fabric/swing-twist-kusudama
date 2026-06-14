import SwingTwistKusudama

/-!
Adversarial demonstration. Run with:

    lake env lean Adversarial.lean

It exits non-zero on purpose: the BUG check is supposed to FIND a counterexample (the swept target
entering the forbidden area), which Plausible reports as an error. The FIX check should find none.
-/

open SwingTwistKusudama

#eval "=== BUG: the (0,0,5)->(0,5,0) sweep stays in the region (linear AND cubic) -- expect COUNTEREXAMPLE ==="
#eval Plausible.Testable.check (cfg := { numInst := 6000 }) (∀ p : Probe, targetStaysInRegion p = true)
#eval "=== FIX: the kusudama clamp projects every frame -- expect NO counterexample ==="
#eval Plausible.Testable.check (cfg := { numInst := 6000 }) (∀ p : Probe, clampedStaysInRegion p = true)
