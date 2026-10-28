import Foundation

// Gives levels without a second-star goal a score goal the solver has actually reached.
//   star_goals <levelFile> <nodeLimit>
// Finds the highest score target the solver can win with, then sets the goal to ~85% of it (any
// lower target is reachable too, since the same winning play scores at least as much).
setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let path = args[1]
let nodeLimit = Int(args[2]) ?? 150_000
let url = URL(fileURLWithPath: path)
let level = try JSONDecoder().decode(LevelDefinition.self, from: Data(contentsOf: url))

func reaches(_ target: Int) -> Bool {
    Solver(level: level, nodeLimit: nodeLimit).solve(requiring: .score(target)).isSolvable
}

var best = 0
var step = 200
var target = 200
// Grow until the solver fails, then bisect between the last success and the first failure.
while reaches(target) { best = target; step *= 2; target = best + step }
var low = best, high = target
while high - low > 50 {
    let mid = (low + high) / 2
    if reaches(mid) { low = mid } else { high = mid }
}
best = low
guard best > 0 else { print("level \(level.id): no score target reached"); exit(1) }
let goal = max(100, (best * 85 / 100) / 10 * 10)
print("level \(level.id): proven up to \(best), goal \(goal)")
let final = LevelDefinition(
    id: level.id, name: level.name, pencilSize: level.pencilSize, maxStackHeight: level.maxStackHeight,
    moveLimit: level.moveLimit, trayCount: level.trayCount, boardRadius: level.boardRadius, removed: level.removed,
    prefilled: level.prefilled, supply: level.supply, boosters: level.boosters,
    starGoal: .score(goal), artwork: level.artwork)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(final).write(to: url)
