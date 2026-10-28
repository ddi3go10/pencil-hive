import CoreGraphics
import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Hex grid")
struct HexGridTests {
    @Test func everyCellHasSixNeighboursAtDistanceOne() {
        let origin = HexCoord(q: 0, r: 0)
        #expect(origin.neighbors.count == 6)
        #expect(Set(origin.neighbors).count == 6)
        #expect(origin.neighbors.allSatisfy { $0.distance(to: origin) == 1 })
    }

    @Test func adjacencyIsSymmetric() {
        for cell in HexCoord.hexagon(radius: 3) {
            for neighbor in cell.neighbors {
                #expect(neighbor.isAdjacent(to: cell))
                #expect(neighbor.neighbors.contains(cell))
            }
        }
    }

    @Test func distanceMatchesCubeMetric() {
        #expect(HexCoord(q: 0, r: 0).distance(to: HexCoord(q: 2, r: -1)) == 2)
        #expect(HexCoord(q: -2, r: 2).distance(to: HexCoord(q: 2, r: -2)) == 4)
        #expect(HexCoord(q: 1, r: 1).distance(to: HexCoord(q: 1, r: 1)) == 0)
        #expect(!HexCoord(q: 0, r: 0).isAdjacent(to: HexCoord(q: 1, r: 1)))
    }

    @Test func hexagonHasCentredHexNumberOfCells() {
        #expect(HexCoord.hexagon(radius: 0).count == 1)
        #expect(HexCoord.hexagon(radius: 1).count == 7)
        #expect(HexCoord.hexagon(radius: 2).count == 19)
        #expect(HexCoord.hexagon(radius: 3).count == 37)
    }

    @Test func coordinateRoundTripsThroughJSON() throws {
        let cell = HexCoord(q: -2, r: 3)
        let data = try JSONEncoder().encode(cell)
        #expect(String(decoding: data, as: UTF8.self) == "[-2,3]")
        #expect(try JSONDecoder().decode(HexCoord.self, from: data) == cell)
    }

    @Test func layoutPlacesNeighboursEvenlyApart() {
        let layout = HexLayout(size: 30)
        let centre = layout.center(of: HexCoord(q: 0, r: 0))
        for neighbor in HexCoord(q: 0, r: 0).neighbors {
            let p = layout.center(of: neighbor)
            #expect(abs(hypot(p.x - centre.x, p.y - centre.y) - 30 * HexLayout.sqrt3) < 0.001)
        }
    }

    @Test func screenPointsMapBackToTheirCell() {
        let layout = HexLayout(size: 24, origin: CGPoint(x: 200, y: 400))
        for cell in HexCoord.hexagon(radius: 3) {
            let centre = layout.center(of: cell)
            #expect(layout.cell(at: centre) == cell)
            #expect(layout.cell(at: CGPoint(x: centre.x + 5, y: centre.y - 4)) == cell)
        }
    }

    @Test func nearestCellRespectsMaximumDistance() {
        let layout = HexLayout(size: 30)
        let cells = HexCoord.hexagon(radius: 1)
        let near = layout.center(of: HexCoord(q: 1, r: 0))
        #expect(layout.nearest(to: CGPoint(x: near.x + 3, y: near.y), among: cells, maxDistance: 20) == HexCoord(q: 1, r: 0))
        #expect(layout.nearest(to: CGPoint(x: 500, y: 500), among: cells, maxDistance: 40) == nil)
    }
}
