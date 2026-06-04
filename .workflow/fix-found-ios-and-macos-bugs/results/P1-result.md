# P1 Result

Accepted:
- Added `basedOnDependencyAnalysis: false` to both KMP framework XcodeGen script phases, which generated `alwaysOutOfDate = 1` in the Xcode project.
- Added `Embed Command Center Helper` as a macOS post-build script that copies the built helper app into `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/MiGestorCommandCenter.app`.

Notes:
- Regenerating the project also reflected pre-existing `project.yml` changes and currently present source files. Those were not authored as part of this fix, but they are consistent with XcodeGen's source-directory generation.
