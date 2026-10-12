import AppKit

// `glidetab list` etc: act as a command line client of the running app, then exit.
let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first, CLI.commands.contains(command) {
    exit(CLI.run(arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
