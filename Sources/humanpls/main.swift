import Foundation

let args = Array(CommandLine.arguments.dropFirst())

// No arguments (or a macOS launch argument): run as the menu bar app. Otherwise act as the CLI.
let launchedByMac = args.first.map { $0.hasPrefix("-psn") || $0.hasPrefix("-NS") || $0.hasPrefix("-Apple") } ?? false

switch args.first {
case nil, "serve":
    MainActor.assumeIsolated { AppMain.run() }
case _ where launchedByMac:
    MainActor.assumeIsolated { AppMain.run() }
case "--version", "-v", "version":
    print(version)
case "--help", "-h", "help":
    print(usage)
case "pick":
    runPick(Array(args.dropFirst()))
case "show":
    runShow(Array(args.dropFirst()))
case "reopen":
    runReopen(Array(args.dropFirst()))
case "list":
    runList()
case "quit":
    runQuit()
case "selftest":
    MainActor.assumeIsolated { exit(SelfTest.run()) }
case "install-cli":
    runInstallCLI(Array(args.dropFirst()))
default:
    FileHandle.standardError.write(Data("humanpls: unknown command \(args[0])\n\n\(usage)\n".utf8))
    exit(2)
}
