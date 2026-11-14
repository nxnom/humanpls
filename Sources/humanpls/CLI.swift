import Foundation
import HumanplsCore

let version = "0.1.1"

let usage = """
humanpls \(version): ask a human to pick between options, or just look at files. A native macOS popup.

Usage:
  humanpls pick --id ID [options] OPTION...      ask a question (a popup opens)
  humanpls show [--id ID] [--compare] FILE_OR_FOLDER...   look at images, video, audio, text, markdown, code
                                                 --compare opens the first two images side by side
  humanpls reopen [ID]                           open the last popup again (or one from the history)
  humanpls list                                  recent popups
  humanpls quit                                  quit the menu bar app
  humanpls install-cli [DIR]                     link `humanpls` into DIR (default /usr/local/bin, else ~/.local/bin)
  humanpls doctor                                show how an answer would get back to your chat, and what is missing
  humanpls serve                                 run the app in this terminal (for development)

OPTION is a file, "file::label", "text:Aung", "text:Aung::note". A leading * marks it recommended.

pick options:
  --id ID               short id, shown in the answer (required)
  --title TEXT          window title (default: the id)
  --question TEXT       what to decide
  --section TITLE OPTION...   one more question (repeatable)
  --items FILE.json     options from JSON: a list, {"items": [...]} or {"sections": [...]}
  --slice auto|4x3      cut ONE image sheet (logos, contact sheet) into cells you can pick;
                        auto finds the grid from the empty space, 4x3 = 4 columns x 3 rows
  --multi               allow several picks
  --recommend KEY       mark option KEY (A, B...) recommended (repeatable)
  --default KEY         pre-pick option KEY (repeatable)
  --no-preselect        do not pre-pick recommended options
  --wait                wait for the answer and print it (nothing is pasted into the chat)
  --timeout SECONDS     with --wait: give up after this time
  --dump-job            print the job as JSON and exit (no popup)

Without --wait, Send pastes the answer into the terminal that ran this command and presses Enter.
"""

struct CLIFailure: Error { let message: String; let code: Int32 }

func fail(_ m: String, _ code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("humanpls: \(m)\n".utf8))
    exit(code)
}

// MARK: environment of the caller

func findInPath(_ name: String) -> String? {
    let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
    for d in dirs {
        let p = (d as NSString).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

func callerEnv() -> ClientEnv {
    let e = ProcessInfo.processInfo.environment
    var env = ClientEnv(cwd: FileManager.default.currentDirectoryPath)
    if let pane = e["TMUX_PANE"], let tmux = e["TMUX"], !pane.isEmpty {
        env.tmuxPane = pane
        env.tmuxSocket = String(tmux.split(separator: ",", omittingEmptySubsequences: false).first ?? "")
        env.tmuxPath = findInPath("tmux")
    }
    env.bundleId = e["__CFBundleIdentifier"]
    env.autoAnswer = e["HUMANPLS_AUTOANSWER"]
    env.autoDelay = e["HUMANPLS_AUTOANSWER_DELAY"].flatMap(Double.init)
    return env
}

// MARK: talking to the app

/// The real path of this program, with symlinks resolved (the `humanpls` command is a link into the app).
func realExecutable() -> String {
    URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath().path
}

/// The .app this program is inside, found by walking up from the real path. nil when run from a build folder.
func appBundlePath() -> String? {
    var url = URL(fileURLWithPath: realExecutable())
    while url.path != "/" && !url.path.isEmpty {
        if url.pathExtension == "app" { return url.path }
        url.deleteLastPathComponent()
    }
    return nil
}

func startApp() {
    if let bundle = appBundlePath() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var a = ["-g"]
        // `open` does not pass our environment on, so forward the variables that move the app's data (tests, custom setups)
        for k in ["HUMANPLS_HOME", "HUMANPLS_SOCKET"] {
            if let v = ProcessInfo.processInfo.environment[k] { a += ["--env", "\(k)=\(v)"] }
        }
        p.arguments = a + ["-a", bundle]
        try? p.run(); p.waitUntilExit()
    } else {
        // development: run ourselves as the app, detached
        let p = Process()
        p.executableURL = URL(fileURLWithPath: realExecutable())
        p.arguments = ["serve"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        try? p.run()
    }
}

func connectOrStart() -> Int32 {
    if let fd = UnixSocket.connect() { return fd }
    startApp()
    for _ in 0..<100 {   // up to 10 seconds
        usleep(100_000)
        if let fd = UnixSocket.connect() { return fd }
    }
    fail("could not start the humanpls app (socket \(Paths.socket)). Try: humanpls serve", 5)
}

func readResponse(_ reader: LineReader) -> Response? {
    guard let line = reader.readLine() else { return nil }
    return try? Coding.decoder().decode(Response.self, from: line)
}

func roundTrip(_ req: Request, start: Bool = true) -> (Int32, LineReader) {
    let fd = start ? connectOrStart() : (UnixSocket.connect() ?? { fail("the humanpls app is not running", 5) }())
    guard send(fd, req) else { fail("could not talk to the app", 5) }
    return (fd, LineReader(fd: fd))
}

// MARK: commands

func runPick(_ argv: [String]) {
    var a = JobBuilder.PickArgs()
    var wait = false, dump = false
    var timeout: Double?
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < argv.count else { fail("\(flag) needs a value") }
        return argv[i]
    }
    while i < argv.count {
        let s = argv[i]
        switch s {
        case "--id": a.id = value(s)
        case "--title": a.title = value(s)
        case "--question": a.question = value(s)
        case "--items": a.itemsFile = value(s)
        case "--slice": a.slice = value(s)
        case "--multi": a.multi = true
        case "--recommend": a.recommend.append(value(s))
        case "--default": a.defaults = (a.defaults ?? []) + [value(s)]
        case "--no-preselect": a.noPreselect = true
        case "--wait": wait = true
        case "--timeout": timeout = Double(value(s))
        case "--dump-job": dump = true
        case "--section":
            var sec: [String] = []
            i += 1
            while i < argv.count, !(argv[i].hasPrefix("--") && argv[i].count > 2) { sec.append(argv[i]); i += 1 }
            i -= 1
            a.sections.append(sec)
        case "--open": break   // old option-picker flag: popups always open
        default:
            if s.hasPrefix("--") && s.count > 2 { fail("unknown option \(s)") }
            a.positional.append(s)
        }
        i += 1
    }
    let job: Job
    do { job = try JobBuilder().pick(a) } catch { fail("\(error)") }
    submit(job, wait: wait, timeout: timeout, dump: dump)
}

func runShow(_ argv: [String]) {
    var id: String?, title: String?
    var paths: [String] = []
    var wait = false, dump = false, compare = false
    var i = 0
    while i < argv.count {
        let s = argv[i]
        switch s {
        case "--compare": compare = true
        case "--id": i += 1; if i < argv.count { id = argv[i] }
        case "--title": i += 1; if i < argv.count { title = argv[i] }
        case "--wait": wait = true
        case "--dump-job": dump = true
        default:
            if s.hasPrefix("--") && s.count > 2 { fail("unknown option \(s)") }
            paths.append(s)
        }
        i += 1
    }
    let job: Job
    do { job = try JobBuilder().show(id: id, title: title, paths: paths, compare: compare) } catch { fail("\(error)") }
    submit(job, wait: wait, timeout: nil, dump: dump)
}

func submit(_ job: Job, wait: Bool, timeout: Double?, dump: Bool) {
    if dump {
        let e = Coding.encoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: (try? e.encode(job)) ?? Data(), encoding: .utf8) ?? "")
        exit(0)
    }
    let (fd, reader) = roundTrip(Request(cmd: job.mode.rawValue, job: job, env: callerEnv(), wait: wait))
    guard let first = readResponse(reader) else { fail("the app closed the connection", 5) }
    if first.type == "error" { fail(first.message ?? "error", 5) }
    if !wait {
        print("opened: \(job.id) (\(job.sections.flatMap { $0.items }.count) items)")
        close(fd)
        exit(0)
    }
    if let t = timeout {
        DispatchQueue.global().asyncAfter(deadline: .now() + t) {
            FileHandle.standardError.write(Data("humanpls: timed out waiting for the answer. The popup stays open; if the person answers later, the answer is pasted into the chat.\n".utf8)); exit(4)
        }
    }
    while let r = readResponse(reader) {
        switch r.type {
        case "answer":
            if r.status == "cancelled" { fail("cancelled: the person closed the popup without answering", 3) }
            print(r.answer ?? "")
            exit(0)
        case "error": fail(r.message ?? "error", 5)
        default: continue
        }
    }
    fail("the app quit before an answer came", 5)
}

func runReopen(_ argv: [String]) {
    let (fd, reader) = roundTrip(Request(cmd: "reopen", env: callerEnv(), ref: argv.first))
    let r = readResponse(reader)
    close(fd)
    if r?.type == "error" { fail(r?.message ?? "error", 5) }
    print(r?.message ?? "reopened")
}

func runList() {
    let (fd, reader) = roundTrip(Request(cmd: "list"))
    let r = readResponse(reader)
    close(fd)
    let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
    for j in r?.jobs ?? [] { print("\(j.id)\t\(j.mode.rawValue)\t\(j.count) items\t\(f.string(from: j.date))\t\(j.title)") }
}

func runQuit() {
    guard let fd = UnixSocket.connect() else { print("not running"); return }
    _ = send(fd, Request(cmd: "quit")); close(fd)
    print("quit")
}

func runDoctor() {
    let env = callerEnv()
    print("humanpls \(version)")
    print("program:   \(realExecutable())")
    print("app:       \(appBundlePath() ?? "not inside an app (a build folder)")")
    var running = false, trusted = "unknown"
    if let fd = UnixSocket.connect() {
        running = true
        _ = send(fd, Request(cmd: "status"))
        if let r = readResponse(LineReader(fd: fd)), let m = r.message { trusted = m }
        close(fd)
    }
    print("app is running: \(running ? "yes" : "no (it starts by itself on the first popup)")")
    print("")
    print("Where the answer goes when you press Send (no --wait):")
    if let pane = env.tmuxPane, let t = env.tmuxPath {
        print("  tmux pane \(pane)  (tmux: \(t))")
        print("  -> the answer is pasted into that pane and Enter is pressed. No permission needed.")
    } else if let bid = env.bundleId {
        print("  terminal app \(bid)")
        print("  -> the app brings it to the front, pastes with Command-V and presses Enter.")
        print("     This needs the Accessibility permission for humanpls (now: \(trusted)).")
        print("     System Settings > Privacy & Security > Accessibility > turn humanpls on.")
        if env.tmuxPane != nil { print("  (tmux is not on the PATH, so the tmux route cannot be used)") }
    } else {
        print("  no tmux and no terminal app found in this environment")
        print("  -> the answer is only copied to the clipboard. Use --wait to get it as the command output.")
    }
    print("")
    print("With --wait the answer is printed by the command and nothing is pasted. Agents should prefer --wait.")
}

func runInstallCLI(_ argv: [String]) {
    // humanpls install-cli [DIR]   default: /usr/local/bin when it is writable, else ~/.local/bin
    MainActor.assumeIsolated {
        let dir = argv.first.map { ($0 as NSString).expandingTildeInPath }
            ?? (FileManager.default.isWritableFile(atPath: CommandLineTool.systemDir) ? CommandLineTool.systemDir : CommandLineTool.userDir)
        do {
            let l = try CommandLineTool.install(into: dir)
            print("linked \(l) -> \(CommandLineTool.executable)")
            if !CommandLineTool.isOnPath(dir) { print("note: \(dir) is not on your PATH. Add it, for example in ~/.zshrc:  export PATH=\"\(dir):$PATH\"") }
        } catch { fail("\(error)") }
    }
}
