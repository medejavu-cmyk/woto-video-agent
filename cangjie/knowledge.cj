package wotoagent

import std.collection.ArrayList
import std.fs.*

public class Segment {
    public let start: Int64
    public let end: Int64
    public let text: String

    public init(start!: Int64, end!: Int64, text!: String) {
        this.start = start
        this.end = end
        this.text = text
    }
}

public class KnowledgeProject {
    public let id: String
    public let title: String
    public let segments: ArrayList<Segment>

    public init(id!: String, title!: String, segments!: ArrayList<Segment>) {
        this.id = id
        this.title = title
        this.segments = segments
    }
}

public func splitTranscript(text: String): ArrayList<Segment> {
    let segments = ArrayList<Segment>()
    let chunkSize = 500
    let overlap = 80
    var start = 0
    var index: Int64 = 0
    while (start < text.size) {
        var end = start + chunkSize
        if (end > text.size) {
            end = text.size
        }
        segments.add(Segment(start: index * 30, end: (index + 1) * 30, text: text[start..end]))
        if (end == text.size) {
            break
        }
        start = end - overlap
        index += 1
    }
    return segments
}

public func buildContext(question: String, segments: ArrayList<Segment>): String {
    var out = "用户问题: ${question}\n参考片段:\n"
    var count = 0
    for (segment in segments) {
        if (count >= 5) {
            break
        }
        out += "[${segment.start}-${segment.end}] ${segment.text}\n"
        count += 1
    }
    return out
}

public func saveTranscript(path: String, text: String): Unit {
    File.writeTo(path, text.toArray())
}
