import CoreGraphics
import Testing
@testable import TearsheetCore

struct SelectionGeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)

    @Test func rectNormalisesDragDirection() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 80, y: 40), to: CGPoint(x: 20, y: 10), within: bounds)
        #expect(rect == CGRect(x: 20, y: 10, width: 60, height: 30))
    }

    @Test func rectClampsToBounds() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: -10, y: 20), to: CGPoint(x: 140, y: 90), within: bounds)
        #expect(rect == CGRect(x: 0, y: 20, width: 100, height: 30))
    }

    @Test func moveStopsAtEdges() {
        let rect = CGRect(x: 10, y: 10, width: 20, height: 20)
        #expect(SelectionGeometry.move(rect, by: CGVector(dx: 500, dy: -500), within: bounds) == CGRect(x: 80, y: 0, width: 20, height: 20))
        #expect(SelectionGeometry.move(rect, by: CGVector(dx: 5, dy: 5), within: bounds) == CGRect(x: 15, y: 15, width: 20, height: 20))
    }

    @Test func pixelRectFlipsAndScales() {
        // A selection 10pt from the bottom of a 50pt-high view sits 40pt-10pt-high from the top.
        let rect = CGRect(x: 10, y: 10, width: 30, height: 20)
        let pixels = SelectionGeometry.pixelRect(for: rect, viewHeight: 50, scale: 2)
        #expect(pixels == CGRect(x: 20, y: 40, width: 60, height: 40))
    }

    @Test func pixelRectSnapsHalfPoints() {
        let rect = CGRect(x: 10.5, y: 0, width: 10.5, height: 1.5)
        let pixels = SelectionGeometry.pixelRect(for: rect, viewHeight: 50, scale: 2)
        #expect(pixels == CGRect(x: 21, y: 97, width: 21, height: 3))
    }
}
