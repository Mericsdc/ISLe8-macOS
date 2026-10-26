import AppKit

// Started as `isle8 …` from a script or an agent hook: do that and leave.
if let status = CommandLineTool.runIfRequested(CommandLine.arguments) {
    exit(status)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
