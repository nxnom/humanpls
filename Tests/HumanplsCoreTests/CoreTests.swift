import XCTest
@testable import HumanplsCore

final class CoreTests: XCTestCase {
    var tmp: String!

    override func setUp() {
        tmp = NSTemporaryDirectory() + "humanpls-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        for n in ["a.png", "b.wav", "c.mp4", "notes.md", "x.swift", "z.bin"] {
            FileManager.default.createFile(atPath: tmp + "/" + n, contents: Data([0]))
        }
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: tmp) }

    func builder() -> JobBuilder { JobBuilder(cwd: tmp) }

    // MARK: options

    func testKeys() {
        XCTAssertEqual(JobBuilder.keys(3), ["A", "B", "C"])
        XCTAssertEqual(JobBuilder.keys(28).suffix(2), ["AA", "AB"])
    }

    func testPositionalOptionsAndLabels() throws {
        var a = JobBuilder.PickArgs(); a.id = "narrator"
        a.positional = ["a.png::Living room", "*b.wav::raspy", "text:Aung::short note", "notes.md", "x.swift"]
        let job = try builder().pick(a)
        let items = job.sections[0].items
        XCTAssertEqual(items.map { $0.kind }, [.image, .audio, .chip, .markdown, .code])
        XCTAssertEqual(items[0].label, "Living room")
        XCTAssertEqual(items[1].recommended, true)
        XCTAssertTrue(items[1].selected, "recommended options start picked")
        XCTAssertEqual(items[2].note, "short note")
        XCTAssertEqual(items[4].language, "swift")
        XCTAssertEqual(items[0].path, tmp + "/a.png")
    }

    func testLongTextBecomesText() throws {
        var a = JobBuilder.PickArgs(); a.id = "t"
        a.positional = ["text:" + String(repeating: "x", count: 100), "text:line1\nline2"]
        let job = try builder().pick(a)
        XCTAssertEqual(job.sections[0].items.map { $0.kind }, [.text, .text])
    }

    func testSinglePickKeepsOnlyFirstSelected() throws {
        var a = JobBuilder.PickArgs(); a.id = "t"
        a.positional = ["*a.png", "*b.wav"]
        let job = try builder().pick(a)
        XCTAssertEqual(job.sections[0].items.map { $0.selected }, [true, false])
        a.multi = true
        XCTAssertEqual(try builder().pick(a).sections[0].items.map { $0.selected }, [true, true])
    }

    func testNoPreselectAndDefault() throws {
        var a = JobBuilder.PickArgs(); a.id = "t"
        a.positional = ["*a.png", "b.wav"]
        a.noPreselect = true
        XCTAssertEqual(try builder().pick(a).sections[0].items.map { $0.selected }, [false, false])
        a.noPreselect = false; a.defaults = ["B"]
        XCTAssertEqual(try builder().pick(a).sections[0].items.map { $0.selected }, [false, true])
    }

    func testSections() throws {
        var a = JobBuilder.PickArgs(); a.id = "ep02"
        a.sections = [["Name", "text:Aung", "text:Maung"], ["Voice", "b.wav", "c.mp4"]]
        let job = try builder().pick(a)
        XCTAssertEqual(job.sections.map { $0.id }, ["name", "voice"])
        XCTAssertEqual(job.sections[1].items.map { $0.kind }, [.audio, .video])
    }

    func testErrors() {
        var a = JobBuilder.PickArgs()
        XCTAssertThrowsError(try builder().pick(a), "id is required")
        a.id = "t"
        XCTAssertThrowsError(try builder().pick(a), "no options")
        a.positional = ["missing.png"]
        XCTAssertThrowsError(try builder().pick(a), "missing file")
        a.positional = ["z.bin"]
        XCTAssertThrowsError(try builder().pick(a), "unsupported type")
        a.positional = ["a.png"]; a.recommend = ["Q"]
        XCTAssertThrowsError(try builder().pick(a), "recommend a key that does not exist")
        a.recommend = []; a.id = "bad id!"
        XCTAssertThrowsError(try builder().pick(a), "bad id")
    }

    func testItemsJSONSections() throws {
        let json = """
        {"sections": [
          {"id": "name", "title": "Name", "question": "What name?", "items": [{"text": "Aung"}, {"text": "Maung", "recommended": true}]},
          {"id": "plates", "title": "Plates", "multi": true, "items": [{"file": "a.png", "label": "Wide"}, {"markdown": "# Hi"}, {"code": "let x = 1", "language": "swift"}]}
        ]}
        """
        try json.write(toFile: tmp + "/q.json", atomically: true, encoding: .utf8)
        var a = JobBuilder.PickArgs(); a.id = "ep"; a.itemsFile = "q.json"
        let job = try builder().pick(a)
        XCTAssertEqual(job.sections.count, 2)
        XCTAssertEqual(job.sections[0].question, "What name?")
        XCTAssertTrue(job.sections[0].items[1].selected)
        XCTAssertTrue(job.sections[1].multi)
        XCTAssertEqual(job.sections[1].items.map { $0.kind }, [.image, .markdown, .code])
        XCTAssertEqual(job.sections[1].items[2].language, "swift")
    }

    func testItemsJSONList() throws {
        try #"[{"text":"A1"},{"file":"b.wav"}]"#.write(toFile: tmp + "/l.json", atomically: true, encoding: .utf8)
        var a = JobBuilder.PickArgs(); a.id = "t"; a.itemsFile = "l.json"
        XCTAssertEqual(try builder().pick(a).sections[0].items.count, 2)
        try "nope".write(toFile: tmp + "/bad.json", atomically: true, encoding: .utf8)
        a.itemsFile = "bad.json"
        XCTAssertThrowsError(try builder().pick(a))
    }

    func testShowExpandsFolders() throws {
        let job = try builder().show(id: nil, title: nil, paths: ["."])
        let names = job.sections[0].items.compactMap { $0.fileName }
        XCTAssertEqual(names.sorted(), ["a.png", "b.wav", "c.mp4", "notes.md", "x.swift"], "z.bin is skipped")
        XCTAssertEqual(job.mode, .show)
        XCTAssertThrowsError(try builder().show(id: nil, title: nil, paths: ["nope"]))
    }

    // MARK: answer text

    func job2() throws -> Job {
        var a = JobBuilder.PickArgs(); a.id = "ep02"
        a.sections = [["Name", "text:Aung", "text:Maung"], ["Voice", "b.wav::calm", "c.mp4"]]
        return try builder().pick(a)
    }

    func testAnswerSingleQuestion() throws {
        var a = JobBuilder.PickArgs(); a.id = "narrator-voice"
        a.positional = ["b.wav::older, raspy", "a.png"]
        let job = try builder().pick(a)
        var p = Picks(job: job); p.chosen["narrator-voice"] = ["A"]; p.feedback = "a bit slower"
        XCTAssertEqual(AnswerText.make(job: job, picks: p), "[narrator-voice] picked: A \"older, raspy\" (b.wav)\nfeedback: a bit slower")
    }

    func testAnswerSeveralQuestions() throws {
        let job = try job2()
        var p = Picks(job: job)
        p.chosen["name"] = ["B"]
        p.retry = ["voice"]
        p.sectionNotes["voice"] = "all too young"
        XCTAssertEqual(AnswerText.make(job: job, picks: p),
                       "[ep02]\nName: B \"Maung\"\nVoice: none of these: try again | note: all too young")
    }

    func testAnswerNoPickAndMulti() throws {
        var a = JobBuilder.PickArgs(); a.id = "pl"; a.multi = true
        a.positional = ["a.png::Wide", "b.wav", "c.mp4::Clip"]
        let job = try builder().pick(a)
        var p = Picks(job: job)
        XCTAssertEqual(AnswerText.make(job: job, picks: p), "[pl] no pick")
        p.chosen["pl"] = ["A", "C"]
        XCTAssertEqual(AnswerText.make(job: job, picks: p), "[pl] picked: A \"Wide\" (a.png); C \"Clip\" (c.mp4)")
    }

    // MARK: history

    func testHistory() throws {
        let h = HistoryStore(dir: tmp + "/hist")
        var j1 = try job2(); j1.createdAt = Date(timeIntervalSinceNow: -100)
        var j2 = try job2(); j2.id = "other"; j2.createdAt = Date()
        h.save(HistoryEntry(job: j1))
        h.save(HistoryEntry(job: j2, picks: Picks(job: j2), answer: "x", status: "sent"))
        XCTAssertEqual(h.all().map { $0.job.id }, ["other", "ep02"], "newest first")
        XCTAssertEqual(h.find(nil)?.job.id, "other")
        XCTAssertEqual(h.find("ep02")?.job.id, "ep02")
        XCTAssertNil(h.find("nope"))
        XCTAssertEqual(h.find("other")?.status, "sent")
        XCTAssertEqual(h.summaries().first?.count, 4)
        h.clear()
        XCTAssertTrue(h.all().isEmpty)
    }

    func testHistoryPrunesOldEntries() throws {
        var h = HistoryStore(dir: tmp + "/hist2")
        h.maxEntries = 2
        for i in 0..<4 {
            var j = try job2(); j.id = "j\(i)"; j.createdAt = Date(timeIntervalSinceNow: Double(-i))
            h.save(HistoryEntry(job: j))
        }
        XCTAssertEqual(h.all().count, 2)
    }

    // MARK: socket protocol

    func testSocketRoundTrip() throws {
        let path = tmp + "/s.sock"
        let server = try UnixSocket.listen(path: path)
        let job = try job2()
        let done = expectation(description: "server got the request")
        DispatchQueue.global().async {
            guard let c = UnixSocket.accept(server) else { return }
            let line = LineReader(fd: c).readLine()
            let req = try? Coding.decoder().decode(Request.self, from: line ?? Data())
            XCTAssertEqual(req?.cmd, "pick")
            XCTAssertEqual(req?.job?.id, "ep02")
            XCTAssertEqual(req?.env?.tmuxPane, "%5")
            _ = send(c, Response(type: "accepted"))
            _ = send(c, Response(type: "answer", answer: "[ep02]\nName: A", status: "sent"))
            close(c)
            done.fulfill()
        }
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        XCTAssertTrue(send(fd, Request(cmd: "pick", job: job, env: ClientEnv(tmuxPane: "%5"), wait: true)))
        let r = LineReader(fd: fd)
        let first = try Coding.decoder().decode(Response.self, from: try XCTUnwrap(r.readLine()))
        XCTAssertEqual(first.type, "accepted")
        let second = try Coding.decoder().decode(Response.self, from: try XCTUnwrap(r.readLine()))
        XCTAssertEqual(second.answer, "[ep02]\nName: A")
        XCTAssertNil(r.readLine(), "closed after the answer")
        wait(for: [done], timeout: 5)
        close(fd); close(server)
    }

    func testConnectFailsWhenNobodyListens() {
        XCTAssertNil(UnixSocket.connect(path: tmp + "/none.sock"))
    }
}
