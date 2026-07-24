import AppKit
import Foundation
import MuesliCore
import UniformTypeIdentifiers

/// Exports a meeting as ONE self-contained HTML file: the recording (video or
/// audio) embedded as base64, notes and an interactive transcript with
/// click-to-seek — openable in any browser on any machine, fully offline.
/// Nothing ever leaves the recipient's computer, so confidentiality holds.
@MainActor
enum MeetingShareExporter {
    /// Chromium/Firefox cap data: URIs at 512 MB; past ~400 MB of media the
    /// generated file may fail to open outside Safari — warn, don't block.
    private static let mediaSizeWarningBytes = 400 * 1024 * 1024

    static func share(meeting: MeetingRecord) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.html]
        panel.nameFieldStringValue = suggestedFileName(for: meeting)
        panel.title = tr("Share Meeting", "Поделиться встречей")

        NSApp.activate()
        let onSave: (URL) -> Void = { url in
            Task.detached(priority: .userInitiated) {
                await performExport(meeting: meeting, to: url)
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                onSave(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                onSave(url)
            }
        }
    }

    /// True when the meeting has anything worth sharing.
    static func canShare(_ meeting: MeetingRecord) -> Bool {
        !meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !meeting.formattedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || meeting.savedVideoPath != nil
            || meeting.savedRecordingPath != nil
    }

    private static func suggestedFileName(for meeting: MeetingRecord) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let normalized = meeting.title.unicodeScalars.map { allowed.contains($0) ? String($0) : " " }.joined()
        let slug = normalized
            .split(whereSeparator: \.isWhitespace)
            .prefix(6)
            .joined(separator: "-")
        return (slug.isEmpty ? "meeting" : slug) + ".html"
    }

    // MARK: - Export (off-main: base64 of large media)

    private static nonisolated func performExport(meeting: MeetingRecord, to url: URL) async {
        let media = loadMedia(for: meeting)
        let html = buildHTML(meeting: meeting, media: media)
        do {
            try html.data(using: .utf8)?.write(to: url, options: .atomic)
            await MainActor.run {
                if let media, media.byteCount > mediaSizeWarningBytes {
                    let alert = NSAlert()
                    alert.messageText = tr("File saved — but it is large", "Файл сохранён, но он большой")
                    alert.informativeText = tr(
                        "The recording is over 400 MB, so the file may fail to open in Chrome or Firefox (Safari handles up to 2 GB).",
                        "Запись больше 400 МБ — файл может не открыться в Chrome и Firefox (Safari открывает до 2 ГБ)."
                    )
                    alert.runModal()
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            fputs("[share-html] exported \(url.lastPathComponent) (\(html.utf8.count / 1_048_576) MB)\n", stderr)
        } catch {
            fputs("[share-html] export failed: \(error)\n", stderr)
        }
    }

    private struct EmbeddedMedia {
        let base64: String
        let mimeType: String
        let isVideo: Bool
        let byteCount: Int
    }

    private static nonisolated func loadMedia(for meeting: MeetingRecord) -> EmbeddedMedia? {
        let candidates: [(path: String?, isVideo: Bool)] = [
            (meeting.savedVideoPath, true),
            (meeting.savedRecordingPath, false)
        ]
        for candidate in candidates {
            guard let path = candidate.path, FileManager.default.fileExists(atPath: path) else { continue }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            let mime: String
            switch URL(fileURLWithPath: path).pathExtension.lowercased() {
            case "mp4", "m4v": mime = "video/mp4"
            case "mov": mime = "video/quicktime"
            case "m4a": mime = "audio/mp4"
            case "wav": mime = "audio/wav"
            case "mp3": mime = "audio/mpeg"
            default: mime = candidate.isVideo ? "video/mp4" : "audio/mp4"
            }
            return EmbeddedMedia(
                base64: data.base64EncodedString(),
                mimeType: mime,
                isVideo: candidate.isVideo,
                byteCount: data.count
            )
        }
        return nil
    }

    // MARK: - Transcript parsing ([HH:mm:ss] Speaker: text → seek seconds)

    struct TranscriptLine {
        let seconds: Int?
        let timeLabel: String?
        let speaker: String?
        let text: String
    }

    static nonisolated func parseTranscript(_ raw: String) -> [TranscriptLine] {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var parsed: [(clock: Int?, speaker: String?, text: String)] = []
        for line in lines {
            var rest = line
            var clock: Int?
            if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = String(rest[rest.index(after: rest.startIndex)..<close])
                let parts = stamp.split(separator: ":").compactMap { Int($0) }
                if parts.count == 3 {
                    clock = parts[0] * 3600 + parts[1] * 60 + parts[2]
                } else if parts.count == 2 {
                    clock = parts[0] * 60 + parts[1]
                }
                if clock != nil {
                    rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            var speaker: String?
            if let colon = rest.firstIndex(of: ":"),
               rest.distance(from: rest.startIndex, to: colon) <= 40 {
                let head = String(rest[..<colon])
                if !head.contains("http") {
                    speaker = head.trimmingCharacters(in: .whitespaces)
                    rest = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            parsed.append((clock, speaker, rest))
        }

        // Wall-clock stamps → offsets from the first stamped line, so clicking
        // a phrase seeks the player. Midnight wrap adds a day.
        let firstClock = parsed.compactMap(\.clock).first
        return parsed.map { entry in
            var seconds: Int?
            if let clock = entry.clock, let firstClock {
                var offset = clock - firstClock
                if offset < 0 { offset += 24 * 3600 }
                seconds = offset
            }
            let label = seconds.map { value -> String in
                let h = value / 3600
                let m = (value % 3600) / 60
                let s = value % 60
                return h > 0
                    ? String(format: "%d:%02d:%02d", h, m, s)
                    : String(format: "%d:%02d", m, s)
            }
            return TranscriptLine(seconds: seconds, timeLabel: label, speaker: entry.speaker, text: entry.text)
        }
    }

    // MARK: - Markdown → HTML (headings, lists, checkboxes, bold)

    static nonisolated func htmlFromMarkdown(_ markdown: String) -> String {
        var html: [String] = []
        var inList = false
        func closeList() {
            if inList {
                html.append("</ul>")
                inList = false
            }
        }
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                closeList()
                continue
            }
            if line.hasPrefix("# ") {
                closeList()
                html.append("<h1>\(inlineHTML(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("## ") {
                closeList()
                html.append("<h2>\(inlineHTML(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("### ") {
                closeList()
                html.append("<h3>\(inlineHTML(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                if !inList { html.append("<ul>"); inList = true }
                let done = !line.hasPrefix("- [ ] ")
                html.append("<li class=\"todo\"><span class=\"box\">\(done ? "☑" : "☐")</span> \(inlineHTML(String(line.dropFirst(6))))</li>")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { html.append("<ul>"); inList = true }
                html.append("<li>\(inlineHTML(String(line.dropFirst(2))))</li>")
            } else if line == "---" {
                closeList()
                html.append("<hr>")
            } else if line.hasPrefix("> ") {
                closeList()
                html.append("<blockquote>\(inlineHTML(String(line.dropFirst(2))))</blockquote>")
            } else if let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                if !inList { html.append("<ul>"); inList = true }
                html.append("<li>\(inlineHTML(String(line[range.upperBound...])))</li>")
            } else {
                closeList()
                html.append("<p>\(inlineHTML(line))</p>")
            }
        }
        closeList()
        return html.joined(separator: "\n")
    }

    private static nonisolated func inlineHTML(_ text: String) -> String {
        var escaped = escapeHTML(text)
        escaped = escaped.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        return escaped
    }

    static nonisolated func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - HTML document

    private static nonisolated func buildHTML(meeting: MeetingRecord, media: EmbeddedMedia?) -> String {
        let isRussian = L10n.shared.isRussian
        func loc(_ en: String, _ ru: String) -> String { isRussian ? ru : en }

        let title = escapeHTML(meeting.title)
        let dateLine: String
        if let date = MeetingBrowserLogic.parseDate(meeting.startTime) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: isRussian ? "ru_RU" : "en_US")
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            var line = formatter.string(from: date)
            if meeting.durationSeconds > 0 {
                let minutes = Int(meeting.durationSeconds) / 60
                line += " · \(minutes) \(loc("min", "мин"))"
            }
            dateLine = escapeHTML(line)
        } else {
            dateLine = ""
        }

        let notesMarkdown = SummaryLayout.plainText(meeting.formattedNotes)
        let notesHTML = htmlFromMarkdown(notesMarkdown)
        let manualNotes = meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualHTML = manualNotes.isEmpty ? "" : "<h2>\(loc("Written notes", "Ваши заметки"))</h2>\n" + htmlFromMarkdown(manualNotes)

        let transcriptLines = parseTranscript(meeting.rawTranscript)
        var transcriptHTML: [String] = []
        for line in transcriptLines {
            let seek = line.seconds.map { " data-t=\"\($0)\"" } ?? ""
            let time = line.timeLabel.map { "<span class=\"tstamp\">\($0)</span>" } ?? ""
            let speaker = line.speaker.map { "<span class=\"spk\">\(escapeHTML($0))</span> " } ?? ""
            transcriptHTML.append("<div class=\"seg\"\(seek)>\(time)\(speaker)\(escapeHTML(line.text))</div>")
        }

        let hasMedia = media != nil
        let playerTag: String
        if let media {
            playerTag = media.isVideo
                ? "<video id=\"player\" controls playsinline></video>"
                : "<audio id=\"player\" controls></audio>"
        } else {
            playerTag = "<p class=\"muted\">\(loc("No recording attached.", "Запись не приложена."))</p>"
        }

        let tabRecording = loc("Recording", "Запись")
        let tabNotes = loc("Notes", "Заметки")
        let tabTranscript = loc("Transcript", "Транскрипт")
        let madeWith = loc("Exported from Pryanik — everything stays on this computer.", "Экспортировано из Pryanik — всё остаётся на этом компьютере.")

        return """
        <!DOCTYPE html>
        <html lang="\(isRussian ? "ru" : "en")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
        :root {
            --bg: #111214; --card: #1c1d20; --raised: #232528;
            --border: rgba(255,255,255,0.07);
            --text: rgba(255,255,255,0.92); --text2: rgba(255,255,255,0.62); --text3: rgba(255,255,255,0.40);
            --accent: #8b5cf6; --accent-soft: rgba(139,92,246,0.15);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: var(--bg); color: var(--text); font: 14px/1.5 -apple-system, system-ui, "Segoe UI", Roboto, sans-serif; }
        .wrap { max-width: 900px; margin: 0 auto; padding: 28px 20px 60px; }
        h1.title { font-size: 24px; font-weight: 700; }
        .date { color: var(--text2); margin-top: 4px; font-size: 13px; }
        .tabs { display: flex; gap: 6px; margin: 22px 0 18px; border-bottom: 1px solid var(--border); padding-bottom: 0; }
        .tab { background: none; border: none; color: var(--text2); font: 600 14px -apple-system, system-ui, sans-serif;
               padding: 8px 14px; cursor: pointer; border-bottom: 2px solid transparent; }
        .tab.active { color: var(--text); border-bottom-color: var(--accent); }
        .pane { display: none; }
        .pane.active { display: block; }
        video, audio { width: 100%; border-radius: 14px; background: #000; outline: none; }
        audio { border-radius: 999px; }
        .card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 18px 20px; }
        .notes h1 { font-size: 20px; margin: 14px 0 6px; }
        .notes h2 { font-size: 16px; margin: 16px 0 6px; }
        .notes h3 { font-size: 14px; margin: 12px 0 4px; }
        .notes p { color: var(--text2); margin: 6px 0; }
        .notes ul { list-style: none; margin: 6px 0; }
        .notes li { color: var(--text2); padding: 3px 0 3px 18px; position: relative; }
        .notes li::before { content: "•"; position: absolute; left: 4px; color: var(--text3); }
        .notes li.todo::before { content: ""; }
        .notes li.todo .box { position: absolute; left: 0; color: var(--accent); }
        .notes blockquote { border-left: 3px solid var(--accent); padding: 4px 12px; color: var(--text2); font-style: italic; margin: 8px 0; }
        .notes hr { border: none; border-top: 1px solid var(--border); margin: 14px 0; }
        .seg { padding: 7px 10px; border-radius: 10px; color: var(--text2); margin-bottom: 2px; }
        .seg[data-t] { cursor: pointer; }
        .seg[data-t]:hover { background: var(--raised); }
        .seg.now { background: var(--accent-soft); color: var(--text); }
        .tstamp { color: var(--accent); font-variant-numeric: tabular-nums; font-size: 12px; margin-right: 8px; }
        .spk { color: var(--text); font-weight: 600; }
        .muted { color: var(--text3); }
        .foot { margin-top: 40px; color: var(--text3); font-size: 12px; text-align: center; }
        .loading { color: var(--text3); font-size: 13px; padding: 30px; text-align: center; }
        </style>
        </head>
        <body>
        <div class="wrap">
            <h1 class="title">\(title)</h1>
            <div class="date">\(dateLine)</div>

            <div class="tabs">
                \(hasMedia ? "<button class=\"tab active\" data-pane=\"rec\">\(tabRecording)</button>" : "")
                <button class="tab\(hasMedia ? "" : " active")" data-pane="notes">\(tabNotes)</button>
                <button class="tab" data-pane="script">\(tabTranscript)</button>
            </div>

            \(hasMedia ? "<div class=\"pane active\" id=\"pane-rec\"><div class=\"loading\" id=\"loading\">…</div>\(playerTag)</div>" : "")
            <div class="pane\(hasMedia ? "" : " active")" id="pane-notes"><div class="card notes">\(notesHTML)\n\(manualHTML)</div></div>
            <div class="pane" id="pane-script"><div class="card">\(transcriptHTML.joined(separator: "\n"))</div></div>

            <div class="foot">\(madeWith)</div>
        </div>
        \(media.map { "<script type=\"text/plain\" id=\"media64\" data-mime=\"\($0.mimeType)\">\($0.base64)</script>" } ?? "")
        <script>
        (function() {
            document.querySelectorAll(".tab").forEach(function(tab) {
                tab.addEventListener("click", function() {
                    document.querySelectorAll(".tab").forEach(function(t) { t.classList.remove("active"); });
                    document.querySelectorAll(".pane").forEach(function(p) { p.classList.remove("active"); });
                    tab.classList.add("active");
                    document.getElementById("pane-" + tab.dataset.pane).classList.add("active");
                });
            });

            var player = document.getElementById("player");
            var blob = document.getElementById("media64");
            if (player && blob) {
                var mime = blob.dataset.mime;
                fetch("data:" + mime + ";base64," + blob.textContent.trim())
                    .then(function(r) { return r.blob(); })
                    .then(function(b) {
                        player.src = URL.createObjectURL(b);
                        var l = document.getElementById("loading");
                        if (l) l.remove();
                    })
                    .catch(function(e) {
                        var l = document.getElementById("loading");
                        if (l) l.textContent = "Media failed to load: " + e;
                    });
            }

            var segs = Array.prototype.slice.call(document.querySelectorAll(".seg[data-t]"));
            segs.forEach(function(seg) {
                seg.addEventListener("click", function() {
                    if (!player) return;
                    player.currentTime = parseInt(seg.dataset.t, 10);
                    var recTab = document.querySelector('.tab[data-pane="rec"]');
                    if (recTab) recTab.click();
                    player.play();
                });
            });
            if (player) {
                player.addEventListener("timeupdate", function() {
                    var t = player.currentTime;
                    var current = null;
                    for (var i = 0; i < segs.length; i++) {
                        if (parseInt(segs[i].dataset.t, 10) <= t) { current = segs[i]; } else { break; }
                    }
                    segs.forEach(function(s) { s.classList.toggle("now", s === current); });
                });
            }
        })();
        </script>
        </body>
        </html>
        """
    }
}
