# Reviewed iOS Simulator skill

Installed October 23, 2026 at `/Users/diegodeloa/.codex/skills/ios-simulator-skill`.
Upstream v1.7.0, pinned revision `e38b3ad5cc2585140c91b9c0f974124c3add31dc`.
The local copy fixes symlink-following session deletion and Codex frontmatter compatibility.
Do not overwrite it with an unreviewed upstream refresh.

## Run the full simulator test suite

Use the existing Python 3.12 runtime; the system Python 3.9 is too old.

```bash
cd /Users/diegodeloa/AI-Projects/projects/pencil-hive
/Users/diegodeloa/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  /Users/diegodeloa/.codex/skills/ios-simulator-skill/scripts/build_and_test.py \
  --project PencilHive.xcodeproj --scheme PencilHive \
  --simulator 'iPhone 18 Pro Max' --test --json
```

Verified result: 130 tests passed, 0 failed. Three AVAudioSession runtime warnings remain.
This does not replace visual/manual testing or physical-iPhone verification.
The wrapper remembers the last simulator in `.claude/skills/ios-simulator-skill/config.json`
and stores result bundles in `~/.ios-simulator-skill/xcresults/`.

## Capability limits

Build and test tools work. `idb` and `idb-companion` are not installed, so scripts that
require them for UI interaction are not ready. Use existing Codex computer controls
for visual interaction. Do not run simulator deletion/erasure, app uninstall, media
clearing, or simulator setting changes without authorization for that specific action.
No physical phone connection is needed for simulator work.

Safety report, patches, hash manifest, environment result, and regression checks:
`/Users/diegodeloa/AI-Projects/finished works/pencil-hive/simulator-skill-2026-10-23/`.
The skill is automatically discoverable by Codex on the next turn after installation.
