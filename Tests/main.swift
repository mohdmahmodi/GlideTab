import Foundation

// A tiny test harness: `./build.sh test` compiles the app sources with these files and runs them.

var checks = 0
var failures: [String] = []

func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: String = #fileID, line: Int = #line) {
    checks += 1
    if !condition() { failures.append("\(file):\(line) \(message())") }
}

func test(_ name: String, _ body: () -> Void) {
    let before = failures.count
    let start = Date()
    body()
    let ms = Date().timeIntervalSince(start) * 1000
    print("\(failures.count == before ? "✓" : "✗") \(name)\(ms > 50 ? String(format: " (%.0f ms)", ms) : "")")
}

keyStateMachineTests()
gestureTests()
gridTests()
orderingTests()
searchTests()
highlightTests()
settingsTests()
browserTests()
miscTests()

print("\n\(checks) checks, \(failures.count) failures")
failures.prefix(40).forEach { print("  ✗ \($0)") }
exit(failures.isEmpty ? 0 : 1)
