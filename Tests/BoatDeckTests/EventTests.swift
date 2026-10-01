import Foundation

func testEventPagination() throws {
    var pager = EventPager()
    func page(_ start: Int, _ end: Int, cursor: String?, more: Bool) -> JSON {
        let events = (start..<end).map { JSON.object(["id": .string("event-\($0)"), "text": .string("value-\($0)")]) }
        return ["events": .array(events), "pageInfo": ["nextCursor": cursor.map(JSON.string) ?? .null, "hasMore": .bool(more)]]
    }
    let first = try pager.accept(page(0, 100, cursor: "page-2", more: true))
    try expect(first.hasMore)
    try expectEqual(first.events.count, 100)
    try expectEqual(pager.cursor, "page-2")
    let second = try pager.accept(page(100, 200, cursor: "page-3", more: true))
    let third = try pager.accept(page(200, 250, cursor: nil, more: false))
    try expectEqual(first.events.count + second.events.count + third.events.count, 250)
    try expectEqual(pager.cursor, "page-3")
    // Polling a short tail doesn't replay it, and continues from its start after a null cursor.
    try expect(try pager.accept(page(200, 250, cursor: nil, more: false)).events.isEmpty)
    try expectEqual(try pager.accept(page(200, 280, cursor: nil, more: false)).events.count, 30)
    let updated: JSON = ["events": [["id": "event-279", "text": "updated partial"]],
                         "pageInfo": ["nextCursor": .null, "hasMore": false]]
    try expectEqual(try pager.accept(updated).events.count, 1)
    try expect(try pager.accept(updated).events.isEmpty)
    try expectThrows { _ = try pager.accept(page(0, 0, cursor: "page-3", more: true)) }
}
