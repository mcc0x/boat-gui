import Foundation

/// Keep the start of the last page as the polling checkpoint when the API returns a null tail cursor.
/// Refetching that page also picks up edits to streaming events with an existing ID.
struct EventPager {
    private(set) var cursor: String?
    private var seen: [String: JSON] = [:]
    private var order: [String] = []
    static let retainedEvents = 6000

    mutating func accept(_ response: JSON) throws -> (events: [JSON], hasMore: Bool) {
        let next = response["pageInfo"]?["nextCursor"]?.string
        let more = response["pageInfo"]?["hasMore"]?.bool ?? (next != nil)
        if more && (next == nil || next == cursor) {
            throw BoatError(status: 0, code: "invalid_cursor", message: "The events API returned a missing or repeated cursor.")
        }
        var changed: [JSON] = []
        for event in response.list("events") {
            let key = event.first("id", "eventId", "seq")?.string ?? event.compact
            if seen[key] != event {
                if seen[key] == nil { order.append(key) }
                seen[key] = event
                changed.append(event)
            }
        }
        while order.count > Self.retainedEvents { seen.removeValue(forKey: order.removeFirst()) }
        if more { cursor = next }
        return (changed, more)
    }
}
