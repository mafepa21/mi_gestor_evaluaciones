Accepted findings:
- `AppleFoundationContextualAIService.swift` is the clearest Swift monolith by size and mixed responsibilities.
- The physical-scale profile/catalog block is cohesive, deterministic, and low-risk to extract without call-site renames.

Decision:
- Implemented the physical-scale extraction into `kmp/iosApp/App/PhysicalScaleProfileService.swift`.
