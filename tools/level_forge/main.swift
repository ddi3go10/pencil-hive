import Foundation

struct RNG: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct Plan { var prefilled: Int; var heights: [Int]; var slack: Int; var boosters: BoosterInventory; var limitSlack: Int?; var pickHardest: Bool; var nodeLimit: Int }

let plans: [Int: Plan] = [
    1: Plan(prefilled: 2, heights: [1, 1, 2], slack: 1, boosters: BoosterInventory(undo: 3), limitSlack: nil, pickHardest: false, nodeLimit: 20_000),
    2: Plan(prefilled: 4, heights: [1, 2, 2, 3], slack: 2, boosters: BoosterInventory(undo: 3, hammer: 1, refresh: 1), limitSlack: nil, pickHardest: true, nodeLimit: 40_000),
    4: Plan(prefilled: 5, heights: [1, 2, 2, 3], slack: 3, boosters: BoosterInventory(undo: 3, hammer: 2, refresh: 2), limitSlack: 3, pickHardest: true, nodeLimit: 80_000),
    3: Plan(prefilled: 5, heights: [1, 2, 2, 3], slack: 3, boosters: BoosterInventory(undo: 3, hammer: 2, refresh: 2), limitSlack: 2, pickHardest: true, nodeLimit: 60_000),
]

/// Levels 5+ use a formula: a bit more prefilled and fewer boosters as the levels go on.
func generatedPlan(for id: Int) -> Plan {
    // Levels 5-10 are forgiving: plenty of boosters, no spare tiles, and the easiest solvable candidate.
    let casual = id <= 10
    return Plan(prefilled: min(3 + id / 4, 6), heights: [1, 2, 2, 3], slack: casual ? 0 : 2 + id / 8,
         boosters: casual ? BoosterInventory(undo: 5, hammer: 3, refresh: 2)
                          : BoosterInventory(undo: 3, hammer: id < 10 ? 1 : 2, refresh: id < 14 ? 1 : 2),
         limitSlack: id >= 12 ? 3 : nil, pickHardest: id >= 6 && !casual, nodeLimit: 60_000)
}

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let skeletonDir = args[1], outDir = args[2]
let trials = Int(args[3]) ?? 200
let startSeed = UInt64(args.count > 4 ? args[4] : "1") ?? 1
let decoder = JSONDecoder()

func build(_ skeleton: LevelDefinition, plan: Plan, seed: UInt64) -> LevelDefinition? {
    var rng = RNG(s: seed &* 7919 &+ 13)
    // Build runs of one colour, then pair runs into stacks so matches are reachable.
    var runs: [(TileColor, Int)] = []
    for (color, regions) in skeleton.goals.sorted(by: { $0.key < $1.key }) {
        var left = regions * skeleton.pencilSize + (rng.next() % 3 == 0 ? plan.slack : 0)
        while left > 0 {
            let n = min(left, plan.heights.filter { $0 < skeleton.pencilSize }.randomElement(using: &rng) ?? 1)
            runs.append((color, n)); left -= n
        }
    }
    runs.shuffle(using: &rng)
    var stacks: [TileStack] = []
    var idx = 0
    while idx < runs.count {
        var t: [TileColor] = Array(repeating: runs[idx].0, count: runs[idx].1)
        idx += 1
        if idx < runs.count, runs[idx].0 != t.last!, t.count + runs[idx].1 <= 4, rng.next() % 3 != 0 {
            t += Array(repeating: runs[idx].0, count: runs[idx].1); idx += 1
        }
        stacks.append(TileStack(t))
    }
    if stacks.contains(where: { $0.topRunLength >= skeleton.pencilSize }) { return nil }
    stacks.shuffle(using: &rng)
    let cells = skeleton.cells
    let pre = Array(stacks.prefix(plan.prefilled))
    let supply = Array(stacks.dropFirst(plan.prefilled))
    var placed: [LevelDefinition.Prefilled] = []
    // Try several placements: touching prefilled stacks must not already share a top colour.
    for _ in 0..<30 {
        placed = []
        var pool = cells.shuffled(using: &rng)
        for stack in pre {
            guard let cell = pool.popLast() else { return nil }
            placed.append(.init(cell: cell, stack: stack))
        }
        let probe = LevelDefinition(
            id: skeleton.id, name: skeleton.name, pencilSize: skeleton.pencilSize, maxStackHeight: 10,
            moveLimit: nil, trayCount: 3, boardRadius: skeleton.boardRadius, removed: skeleton.removed,
            prefilled: placed, supply: supply, boosters: plan.boosters, starGoal: .none, artwork: skeleton.artwork)
        if probe.makeInitialBoard().isStable { break }
    }
    let level = LevelDefinition(
        id: skeleton.id, name: skeleton.name, pencilSize: skeleton.pencilSize, maxStackHeight: 10,
        moveLimit: nil, trayCount: 3, boardRadius: skeleton.boardRadius, removed: skeleton.removed,
        prefilled: placed.sorted { $0.cell < $1.cell }, supply: supply, boosters: plan.boosters,
        starGoal: .none, artwork: skeleton.artwork)
    let problems = LevelValidator.validate(level)
    if ProcessInfo.processInfo.environment["FORGE_DEBUG"] != nil, let p = problems.first { print("  rejected: \(p)") }
    return problems.isEmpty ? level : nil
}

for file in try FileManager.default.contentsOfDirectory(atPath: skeletonDir).sorted() where file.hasSuffix(".json") {
    let skeleton = try decoder.decode(LevelDefinition.self, from: Data(contentsOf: URL(fileURLWithPath: "\(skeletonDir)/\(file)")))
    guard args.count < 6 || Int(args[5]) == skeleton.id else { continue }
    let plan = plans[skeleton.id] ?? generatedPlan(for: skeleton.id)
    var found: [(seed: UInt64, level: LevelDefinition, nodes: Int, moves: [Solver.Move])] = []
    var tried = 0, valid = 0
    for seed in startSeed..<(startSeed + UInt64(trials)) {
        tried += 1
        guard let level = build(skeleton, plan: plan, seed: seed) else { continue }
        valid += 1
        let t0 = Date(); let result = Solver(level: level, nodeLimit: plan.nodeLimit).solve()
        if seed % 10 == 0 { print("  seed \(seed) nodes \(result.nodesVisited) solved \(result.isSolvable) \(String(format: "%.2f", Date().timeIntervalSince(t0)))s") }
        if let moves = result.moves { found.append((seed, level, result.nodesVisited, moves)) }
    }
    print("level \(skeleton.id): tried \(tried), valid \(valid), solvable \(found.count)")
    guard !found.isEmpty else { continue }
    let sorted = found.sorted { $0.nodes < $1.nodes }
    print("  nodes range \(sorted.first!.nodes)...\(sorted.last!.nodes)")
    // Prefer a mid-to-hard candidate that still solves comfortably.
    let pick = plan.pickHardest ? sorted[min(sorted.count - 1, sorted.count * 3 / 4)] : sorted[sorted.count / (plans[skeleton.id] == nil ? 8 : 4)]
    var final = pick.level
    // Star goals for levels 1-4 are chosen by hand (see the README) and proven reachable by the tests;
    // generated levels get "finish in at most as many stacks as the solver used", reachable by construction.
    let limit = plan.limitSlack.map { pick.moves.count + $0 }.flatMap { $0 <= pick.level.supply.count ? $0 : nil }
    let generatedGoal: StarGoal = plans[skeleton.id] == nil && pick.moves.count < final.supply.count ? .stacks(pick.moves.count) : .none
    final = LevelDefinition(
        id: final.id, name: final.name, pencilSize: final.pencilSize, maxStackHeight: final.maxStackHeight,
        moveLimit: limit, trayCount: final.trayCount, boardRadius: final.boardRadius, removed: final.removed,
        prefilled: final.prefilled, supply: final.supply, boosters: final.boosters,
        starGoal: generatedGoal, artwork: final.artwork)
    print("  picked seed \(pick.seed) nodes \(pick.nodes) moves \(pick.moves.count) limit \(limit.map(String.init) ?? "none")")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(final).write(to: URL(fileURLWithPath: "\(outDir)/\(file)"))
}
