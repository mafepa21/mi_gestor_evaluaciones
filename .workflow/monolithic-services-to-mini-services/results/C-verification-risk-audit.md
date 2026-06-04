Accepted checks:
- iOS simulator build with `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- macOS build with `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`.

Results:
- Both builds passed.
