import SwingTwistKusudama
open SwingTwistKusudama
-- The live cones in world space (+Y,+X,+Z @ 10deg), faithful projection.
def kc : List KCone := [⟨⟨0,1,0⟩, d2r 10⟩, ⟨⟨1,0,0⟩, d2r 10⟩, ⟨⟨0,0,1⟩, d2r 10⟩]
def mv (d : V3) : R := r2d (V3.angle (continuousProject kc d 0.22) (V3.norm d))
#eval s!"move +Y     = {mv ⟨0,1,0⟩} deg (expect ~0, in cone)"
#eval s!"move +Y+Z   = {mv ⟨0,1,1⟩} deg (the swept gap)"
#eval s!"move +X+Y   = {mv ⟨1,1,0⟩} deg (between bridged cones +Y,+X)"
#eval s!"move -Y     = {mv ⟨0,-1,0⟩} deg (expect LARGE, genuinely forbidden)"
#eval s!"move -X-Y-Z = {mv ⟨-1,-1,-1⟩} deg (expect LARGE, opposite the cluster)"
#eval s!"tangent r (+Y,+X) = {r2d (tangentCircles ⟨0,1,0⟩ (d2r 10) ⟨1,0,0⟩ (d2r 10)).r} deg"
