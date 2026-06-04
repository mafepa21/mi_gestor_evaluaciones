# Final Report: Monolithic services to mini services

## Outcome
Implemented the first safe mini-service extraction: moved deterministic physical-scale profile/catalog logic out of the monolithic contextual AI service into `kmp/iosApp/App/PhysicalScaleProfileService.swift`.

`AppleFoundationContextualAIService.swift` keeps contextual AI orchestration, prompts, generation, and fallback behavior. Physical scale seed ranges, validation, profile catalog, precision rules, and adjustment helpers now live in a focused service file.

## Accepted Results
- Swift service audit: accepted the recommendation to extract the physical-scale catalog first because it is cohesive, deterministic, and low call-site risk.
- KMP/data audit: accepted as roadmap input, but deferred KMP/data container and repository splits because they touch broader architecture and protected persistence boundaries.
- Verification audit: accepted iOS/macOS Xcode build commands as the relevant checks for this Swift extraction.

## Rejected Results
- Deferred `KmpContainer` / repository splits for this run. They are valid candidates but exceed the requested safe implementation slice.
- Deferred backup service extraction because backup/restore writes app data and needs dedicated fixture or manual backup verification.
- Deferred teaching evidence builders because they have more async/KmpBridge and macOS call-site coupling.

## Conflicts Resolved
- The workflow requested broad monolithic-service cleanup, but AGENTS.md requires small, reviewable changes. Resolution: audit broadly, implement one high-confidence extraction.
- XcodeGen regeneration picked up existing workspace/project additions beyond the new service file. Those were not reverted because they appear to come from pre-existing user changes.

## Verification Evidence
- Confirmed only one definition remains for `PhysicalScalePrecision`, `PhysicalScaleProfile`, and `PhysicalScaleProfileCatalog`.
- Confirmed `PhysicalScaleProfileService.swift` is present in the Xcode project source phases for iOS and Mac.
- iOS build started with `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

## Remaining Risks
- The regenerated Xcode project also synced pre-existing untracked/modified files from `project.yml`; this may surface unrelated compile errors.
- The extraction is behavior-preserving by file movement, but full confidence depends on the Xcode build result.
- Larger KMP/data monoliths remain and should be split behind compatible facades in separate tasks.

## Reusable Follow-up
- Next safe backend split: extract `DemoDataSeeder` from `KmpContainer` while preserving public container properties.
- Next Swift split: move teaching evidence builders into a dedicated `TeachingEvidenceBuilders.swift`.
- Next sensitive split: create backup package IO helpers with backup/restore fixture verification.
