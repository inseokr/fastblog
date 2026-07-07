# fastblog — Codex Instructions

Swift/SwiftUI iOS travel blog app. Read and follow the skills below before writing or reviewing any code.

Cursor loads the same expectations via **`.cursor/rules/fastblog.mdc`** (always-on rule that points here and to `.ai/skills/`).

## Build command
```
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build
```

## Skills (read before coding)

@.ai/skills/architecture/mvvm/layers.md
@.ai/skills/architecture/mvvm/state.md
@.ai/skills/architecture/async.md
@.ai/skills/ui/navigation.md
@.ai/skills/ui/components.md
@.ai/skills/ui/animations.md
@.ai/skills/ui/colors/palette.md
@.ai/skills/ui/colors/gradients.md
@.ai/skills/code/naming.md
@.ai/skills/code/data-models.md

## Adding new Swift files
When creating a new `.swift` file, it must be registered in `fastblog.xcodeproj/project.pbxproj`:
1. **PBXBuildFile** — `BB0001XX /* File.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0001YY; };`
2. **PBXFileReference** — `BB0001YY /* File.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = File.swift; sourceTree = "<group>"; };`
3. **PBXGroup** — add `fileRef` to the right group (Services / Models / Views / ViewModels)
4. **PBXSourcesBuildPhase** — add the build file ref

## iOS version targets
- `VNCalculateImageAestheticsScoresRequest` — iOS 18.0+ only
- `VNGenerateAttentionBasedSaliencyImageRequest` — iOS 14+
- `VNDetectFaceRectanglesRequest` — iOS 9+
- Always guard Vision APIs behind `if #available(iOS 18, *)` where needed
