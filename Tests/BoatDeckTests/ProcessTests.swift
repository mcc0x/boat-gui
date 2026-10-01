import Foundation

func testProcesses() async throws {
    let start = Date()
    let timed = BoatCLI.runSync("/bin/sh", ["-c", "exec >/dev/null 2>&1; exec sleep 10"], timeout: 0.1)
    try expectEqual(timed.exitCode, 124)
    try expect(Date().timeIntervalSince(start) < 2, "Closed output pipes defeated the process deadline")
    let ignored = BoatCLI.runSync("/bin/sh", ["-c", "trap '' TERM; while :; do sleep 0.1; done"], timeout: 0.1)
    try expectEqual(ignored.exitCode, 124)
    let input = BoatCLI.runSync("/bin/sh", ["-c", "sleep 10"], stdin: String(repeating: "x", count: 2_000_000), timeout: 0.1)
    try expectEqual(input.exitCode, 124)
    let echo = BoatCLI.runSync("/bin/cat", [], stdin: String(repeating: "é", count: 100_000), timeout: 3)
    try expectEqual(echo.exitCode, 0)
    try expectEqual(echo.stdout, String(repeating: "é", count: 100_000))
    let big = BoatCLI.runSync("/bin/sh", ["-c", "head -c 2000000 /dev/zero; head -c 2000000 /dev/zero >&2"], timeout: 3)
    try expectEqual(big.exitCode, 0)
    try expect(big.stdout.utf8.count < ProcessRunner.outputLimit + 100)
    try expect(big.stderr.utf8.count < ProcessRunner.outputLimit + 100)
    let task = Task { await BoatCLI.run("/bin/sh", ["-c", "sleep 10"], timeout: 10) }
    try await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()
    let cancelled = await task.value
    try expectEqual(cancelled.exitCode, 130)
    var decoder = UTF8Chunks()
    let bytes = Array("A😀éB".utf8)
    var text = ""
    for byte in bytes { text += decoder.decode(Data([byte])) }
    text += decoder.finish()
    try expectEqual(text, "A😀éB")
}
