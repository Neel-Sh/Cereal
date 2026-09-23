import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

struct LectureExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .pdf] }
    static var writableContentTypes: [UTType] { [.markdown, .pdf] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum LectureExport {
    static func markdown(_ lecture: Lecture) -> Data {
        Data(markdownText(lecture).utf8)
    }

    /// Notes only, without the transcript — what you'd paste into a doc or message.
    static func notesText(_ lecture: Lecture) -> String {
        markdownText(lecture, includeTranscript: false)
    }

    static func markdownText(_ lecture: Lecture, includeTranscript: Bool = true) -> String {
        var lines = ["# \(lecture.displayTitle)", ""]
        if !lecture.course.isEmpty { lines += ["Course: \(lecture.course)"] }
        if !lecture.topic.isEmpty { lines += ["Topic: \(lecture.topic)"] }
        lines += ["Recorded: \(lecture.recordedAt.formatted(date: .abbreviated, time: .shortened))",
                  "Duration: \(lecture.duration.formattedDuration)", ""]
        if !lecture.summary.isEmpty { lines += ["## Summary", lecture.summary, ""] }
        if !lecture.actionItems.isEmpty {
            lines += ["## \(lecture.template.actionItemsTitle)", ""]
            lines += lecture.actionItems.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }
            lines.append("")
        }
        lines += ["## My notes", lecture.notes.isEmpty ? "(None)" : lecture.notes, ""]
        if !lecture.enhancedBlocks.isEmpty {
            lines += ["## Enhanced notes", ""]
            var currentSection: String?
            for block in lecture.enhancedBlocks {
                if let section = block.section, section != currentSection {
                    lines += ["", "### \(section)", ""]
                    currentSection = section
                }
                let source = lecture.transcriptSegments.indices.contains(block.sourceIndex)
                    ? " [\(lecture.transcriptSegments[block.sourceIndex].start.formattedDuration)]" : ""
                lines.append("- \(block.text)\(source)")
            }
            lines.append("")
        } else if !lecture.enhancedNotes.isEmpty {
            lines += ["## Enhanced notes", lecture.enhancedNotes, ""]
        }
        if !lecture.studyItems.isEmpty {
            lines += ["## Study material", ""]
            for kind in StudyKind.allCases {
                let items = lecture.studyItems.filter { $0.kind == kind }
                if !items.isEmpty {
                    lines += ["### \(kind.title)", ""]
                    for item in items {
                        let source = lecture.transcriptSegments.indices.contains(item.sourceIndex)
                            ? " [\(lecture.transcriptSegments[item.sourceIndex].start.formattedDuration)]" : ""
                        lines += ["- **\(item.title)** — \(item.detail)\(source)"]
                    }
                    lines.append("")
                }
            }
        }
        if includeTranscript {
            lines += ["## Transcript", ""]
            if lecture.transcriptSegments.isEmpty {
                lines.append(lecture.transcript)
            } else {
                lines += lecture.transcriptSegments.map { "[\($0.start.formattedDuration)] \($0.text)" }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func pdf(_ lecture: Lecture) -> Data? {
        guard let source = String(data: markdown(lecture), encoding: .utf8) else { return nil }
        let printable = source
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "**", with: "")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attributed = NSAttributedString(string: printable, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.black
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return nil }
        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else { return nil }
        let contentRect = CGRect(x: 48, y: 48, width: 516, height: 696)
        let path = CGPath(rect: contentRect, transform: nil)
        var offset = 0
        while offset < attributed.length {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(offset, 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { break }
            offset += visible.length
        }
        context.closePDF()
        return output as Data
    }
}
