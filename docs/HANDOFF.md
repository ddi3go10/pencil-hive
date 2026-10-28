# Pencil Hive: handoff for the next AI agent

Updated 2026-10-25. Read `/AGENTS.md` (repo root) and `projects/pencil-hive/README.md` first.

## What this is
An offline iPhone hex-sort puzzle (Swift, SwiftUI + SpriteKit, iOS 16+). Drag stacks of hex tiles onto a
honeycomb board; matching colours merge; a full run becomes a pencil that colours a picture. It is
*inspired by* the App Store game "Pencil Sort: Color Sorting" (Onetap Global). Copy no code, art or sounds.
The user wants the UI to look **almost identical in layout and feel** to that game, with original assets.

## State
- Branch `feature/pencil-hive-ios`, base commit `773ffc1`. This continuation is uncommitted and unpushed; preserve unrelated root-repository changes.
- 20 levels in `PencilHive/Resources/Levels/level_01..20.json`; every level has a second-star goal.
- Tests: `swift test` and
  `xcodebuild -project PencilHive.xcodeproj -scheme PencilHive -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`.
  123 Mac tests and 144 simulator tests passed. See the continuation report for logs and visual checks.
- Simulator work now includes manual touch play of levels 2, 3, 5, 8, a larger board, a completed-picture reward and a persistent Gallery.
  See the continuation report for screenshots and precise verification limits.
  NOT verified: a real iPhone, sound/haptics, VoiceOver by hand, levels 5-20 played by a human.

## Layout
`Core/` rules engine (pure Foundation, also built by `Package.swift`), `Game/` SpriteKit scene and art,
`UI/` SwiftUI screens, `App/` state, `tools/level_forge/` level generation. Details in the README.

## Level pipeline
- Levels 1-4: hand-built, then hand-tuned (do not regenerate; the forge would overwrite the edits).
- Levels 5-20: `tools/level_forge/make_more_skeletons.py` (pictures + boards) then
  `tools/level_forge/run.sh <outDir> <trials> <firstSeed> <levelID>` (deals tiles, solver-checks, picks a candidate).
  Plans live in `generatedPlan(for:)` in `tools/level_forge/main.swift`.
- Star goals: `tools/level_forge/star_goals/main.swift` sets a score goal at ~85% of the best score the solver reached.
  Build: `swiftc -O -swift-version 5 PencilHive/Core/*.swift tools/level_forge/star_goals/main.swift -o /tmp/star_goals`.
- Levels 1-10 are tuned casual (5 undos, hammer, roomy boards); `theFirstTenLevelsAreForgiving` guards this.
- Gotcha: the solver node limit (400k in tests) can fail on bigger boards even when a level is winnable. If a level
  becomes "unsolvable" in tests after you enlarge its board, lower its star goal or shrink the board.

## Continuation completed (2026-10-25)
- Added recovery stacks after the original supply: level 2 gets mint + rose, level 3 a sky single,
  level 5 lemon/coral/sky/lemon, and level 8 coral + rose. Level 3's move limit is now 13.
  Openings, artwork and star goals remain unchanged. Do not regenerate over these edits.
- Same seeded greedy bot: levels 2/3/5/8 went from 0/0/0/2 wins out of 20 to 18/19/19/20.
  Bot wins are not human playability evidence. Regression tests replay the manual dead ends.
- No picture frame on the playing board. Larger tiles, top-stack headroom and centered layout.
  Needed pencils fly to the HUD meter; the win screen reveals the completed picture.
- Gallery is accessible from the menu and win screen. It uses saved best-star records, so existing
  completed levels appear immediately. Collected pictures can be enlarged and replayed.
- Artifacts: `finished works/pencil-hive/continuation-2026-10-25/` (report, logs, screenshots, patch).

## Review fixes (2026-10-25, Luna-assisted)
- Hammer uses rendered stack-face hit testing rather than the nearest board base.
- Saved games include their level definition. Incompatible runs restart while earned progress and
  preferences remain intact; legacy saves check the moves/pending-supply invariant. Invalid Undo
  snapshots cannot reintroduce missing supply.
- HUD score/progress use one line; optional move count sits beside colour goals. Large-text reward
  actions adapt and the narrow Gallery title fits. Reward scores stay on one line and long star goals
  wrap fully.
- Evidence: `finished works/pencil-hive/fixes-2026-10-25/`. See the report for RED/GREEN logs,
  screenshots, patches and the remaining physical-device/VoiceOver limits.

## Known issues and gaps
1. Casual difficulty still needs feedback from a human; level 4 and level 7 may be future tuning targets.
2. Levels 5-10 can still be short; recovery supplies help errors but do not create a longer campaign.
3. The intermittent first tap after a fresh launch still needs physical-device verification.
4. Audio, haptics, real-phone touch/layout and manual VoiceOver remain unverified.
5. Daily/endless play and themes remain absent. No in-app purchases by design.

## Suggested next work
1. Have the user play the tuned levels 2, 3, 5, 8 and assess difficulty and reward/gallery feel.
2. Inspect level 4 and level 7 if the user reports another early difficulty spike.
3. Review and push the branch when requested; physical-phone testing needs the normal pairing,
   Developer Mode and signing/privacy discussion before any new sensitive setup.

## Rules for this repo
- Final deliverables go in `finished works/`; never edit `archive/`; never commit secrets.
- After skill changes run `python3 scripts/check-catalog.py`.
- Commit only inside this repo; `projects/deepseek-api-project/` is its own repo.
