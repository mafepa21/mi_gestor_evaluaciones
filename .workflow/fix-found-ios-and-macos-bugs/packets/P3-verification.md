# P3 Verification

Objective: prove the integrated fixes build and the helper is embedded.

Checks:
- Regenerate Xcode project with `xcodegen generate`.
- Build `MiGestorKMPMac` Debug with `CODE_SIGNING_ALLOWED=NO`.
- Check the embedded helper executable exists in the built bundle.
- Verify workflow artifact completeness.

Expected output:
- Build result and helper path evidence recorded in `results/`.
