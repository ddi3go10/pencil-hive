# Pencil Hive learnings

## 2026-10-22
- `swift test` on the uncommitted tree: 87 tests in 11 suites pass (~12s). The solver replay of shipped levels takes ~12s, so it dominates test time.
- Still unverified on the simulator: FAIL overlay, level 3 end-to-end, Settings, How to Play.

## 2026-10-22 (scheduled run, 12:30 PDT)
- Added `RandomPlayTests` (seeded random placement, 40 games per level): every game ends, no illegal state, stacks never exceed max height.
- Random play wins 0/40 on levels 1-3. Good: they are not luck-only. Open question: is a careless (not random) player able to win? Next, try a greedy policy (match top colours first) and compare win rates to tune difficulty.

## 2026-10-22 (scheduled run, 13:25 PDT)
- Added greedy one-move-lookahead test (20 games/level; maximises pencils then score). Wins: L1 4/20, L2 0/20, L3 0/20. Random: 0/40 everywhere.
- Reading: L1 is learnable but not trivial for a short-sighted player; L2/L3 need real planning (solver-verified solvable). Possible concern: L2 may be too steep a jump for new players; worth a 2-step lookahead policy to see if skilled-but-not-optimal play can win L2/L3.

## 2026-10-22 (attended session, ~14:30 PDT, simulator on iPhone 18 Pro / iOS 27.0)
- Verified by hand: Settings (tile-symbols toggle), How to Play (star card), level 3 (13-cell board, symbols on tiles and goal chips, move counter 12), pause card listing the three star conditions, FAIL card "Out of stacks" and its "Undo Last Move" rescue (stack returns to the tray, undo count drops 3 -> 2).
- Quirk: with simulated touches the first tap after a fresh `simctl launch` is ignored every time (6 of 6); the second tap works. Taps fired while an animation plays are dropped by design (phase `.animating`), so scripted drags need ~2-3 s between moves.
- Scripted play tip: board cell centre in points on a 402x874 screen = (201 + 50.8 q, 481 + 58.7 (r + q/2)); aim the finger ~58 pt below the cell because the dragged stack floats above the finger.
- Another session was editing level 4 and the forge at the same time, so this run touched only README and this file.

## 2026-10-22 (scheduled run, 14:30 PDT)
- Added level 4 "Moonlit Lighthouse" (forge plan 4, seed 47, 11-move solve, solver nodes only 27 so it is EASY for its slot). Only 5 of 50 valid forged seeds were solvable at 80k nodes; most candidates are unsolvable, so forging needs many trials for a harder pick.
- Level 4 starGoal is `score 600`, a placeholder: `stacks` 6 and 9 were unreachable (and the failed solver search made the star test take 290s). Tune it to a real reachable-but-hard score.
- Random 0/40, greedy 1/20 on L4.
- Forge now has level 4 in make_skeletons.py and main.swift. Not yet in README levels table.

## 2026-10-22 (scheduled run, 16:00 PDT)
- Level 4 star goal tuned from placeholder 600 to `score 1200`: solver reaches 900/1100/1200 in seconds, but 1400 is not found within 200s (likely unreachable or very hard). 1200 sits between L2 and L3 (1760) in difficulty.
- A concurrent session made SaveStore decoding lenient (wrong-typed field falls back to default instead of discarding the file). That made `anUnreadableSaveIsKeptAside` fail because its sample JSON was no longer "unreadable". Changed the sample to truncated JSON and added `aWrongTypedFieldDoesNotCostTheRestOfTheSave`. 116 tests green.
