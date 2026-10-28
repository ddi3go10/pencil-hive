import CoreGraphics
import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Tile symbols")
struct TileSymbolTests {
    @Test func everyColourHasItsOwnSymbol() {
        let symbols = TileColor.allCases.map(\.symbol)
        #expect(Set(symbols).count == TileColor.allCases.count)
    }

    @Test func everySymbolDrawsInsideItsBox() {
        let box = CGRect(x: 10, y: 20, width: 30, height: 30)
        for symbol in TileSymbol.allCases {
            let bounds = symbol.path(in: box).boundingBoxOfPath
            #expect(!bounds.isEmpty, "\(symbol) drew nothing")
            #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(symbol) spills out of its box: \(bounds)")
        }
    }

    @Test func darkSymbolsAreUsedOnlyOnLightColours() {
        #expect(TileColor.lemon.prefersDarkSymbol)
        #expect(!TileColor.indigo.prefersDarkSymbol)
        #expect(!TileColor.coral.prefersDarkSymbol)
    }

    @Test func tileSymbolsAreOffByDefaultAndOldSavesStillLoad() throws {
        #expect(GameSettings().tileSymbols == false)
        let old = Data(#"{"soundEnabled": false, "hapticsEnabled": true}"#.utf8)
        let decoded = try JSONDecoder().decode(GameSettings.self, from: old)
        #expect(decoded.soundEnabled == false)
        #expect(decoded.tileSymbols == false)
        var on = GameSettings()
        on.tileSymbols = true
        let round = try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(on))
        #expect(round.tileSymbols)
    }
}

@Suite("VoiceOver text")
struct AccessibilityTextTests {
    @Test func stacksAreDescribedTopFirst() {
        #expect(AccessibilityText.stack(TileStack([.sky])) == "1 tile, sky on top")
        #expect(AccessibilityText.stack(TileStack([.amber, .coral, .coral])) == "3 tiles, coral on top (2 in a row), then amber")
        #expect(AccessibilityText.stack(TileStack([])) == "empty")
    }

    @Test func cellsAreNumberedByRowThenLeftToRight() {
        let cells = HexCoord.hexagon(radius: 1)
        let places = AccessibilityText.positions(of: cells)
        #expect(places.count == cells.count)
        // Row 1 is the smallest r; inside a row the smallest q comes first.
        let topRow = cells.filter { $0.r == cells.map(\.r).min() }.sorted { $0.q < $1.q }
        for (index, cell) in topRow.enumerated() {
            #expect(places[cell]?.row == 1)
            #expect(places[cell]?.column == index + 1)
        }
        #expect(Set(places.values.map { "\($0.row)-\($0.column)" }).count == cells.count)
    }

    @Test func cellsReadAsEmptyOrByTheirStack() {
        #expect(AccessibilityText.cell(row: 2, column: 3, stack: nil) == "Row 2, cell 3, empty")
        #expect(AccessibilityText.cell(row: 1, column: 1, stack: TileStack([.mint])) == "Row 1, cell 1, 1 tile, mint on top")
    }

    @Test func aMoveIsSummarisedInOrderWithItsChain() {
        let a = TestLevels.cell(0, 0), b = TestLevels.cell(1, 0)
        let events: [GameEvent] = [
            .stackPlaced(slot: 0, cell: a, stack: TileStack([.sky])),
            .tilesTransferred(from: b, to: a, color: .sky, count: 2, chain: 0),
            .pencilCompleted(cell: a, color: .sky, tileCount: 3, regionID: 1, chain: 1),
        ]
        let text = AccessibilityText.summary(of: events, score: 120)
        #expect(text == "2 tiles of sky moved. Sky pencil done. chain of 2. score 120")
    }

    @Test func anUnneededColorIsExplainedInsteadOfClaimingPictureProgress() {
        let event = GameEvent.pencilCompleted(cell: TestLevels.cell(0, 0), color: .sky, tileCount: 3, regionID: nil, chain: 0)
        #expect(AccessibilityText.summary(of: [event], score: 100).contains("not needed for the picture"))
    }

    @Test func resultsAreSpoken() {
        #expect(AccessibilityText.win(stars: 2, score: 550) == "Picture complete. 2 of 3 stars. Score 550.")
        #expect(AccessibilityText.fail(.boardFull).hasPrefix("Board is full."))
    }
}
