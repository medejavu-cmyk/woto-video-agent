package wotoagent

import std.collection.ArrayList
import std.fs.*
import std.net.*
import std.time.*

let CRLF = "\r\n"
let ROOT = "."
let INDEX_DIR = "data/indexes"
let UPLOAD_DIR = "data/uploads"

func response(status: String, contentType: String, body: String): String {
    return "HTTP/1.1 ${status}${CRLF}" +
        "Content-Type: ${contentType}; charset=utf-8${CRLF}" +
        "Access-Control-Allow-Origin: *${CRLF}" +
        "Access-Control-Allow-Methods: GET, POST, OPTIONS${CRLF}" +
        "Access-Control-Allow-Headers: Content-Type${CRLF}" +
        "Content-Length: ${body.toArray().size}${CRLF}${CRLF}" +
        body
}

func jsonEscape(input: String): String {
    return input
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
}

func jsonError(status: String, message: String): String {
    return response(status, "application/json", "{\"detail\":\"${jsonEscape(message)}\"}")
}

func jsonUnescape(input: String): String {
    return input
        .replace("\\n", "\n")
        .replace("\\r", "\r")
        .replace("\\\"", "\"")
        .replace("\\\\", "\\")
}

func contentType(path: String): String {
    if (path.endsWith(".html")) { return "text/html" }
    if (path.endsWith(".css")) { return "text/css" }
    if (path.endsWith(".js")) { return "application/javascript" }
    return "text/plain"
}

func serveFile(path: String): String {
    let text = String.fromUtf8(File.readFrom(path))
    return response("200 OK", contentType(path), text)
}

func headerValue(request: String, name: String): String {
    let lowerName = name.toAsciiLower()
    let lines = request.split("\r\n", removeEmpty: false)
    for (line in lines) {
        let idxOpt = line.indexOf(":")
        if (idxOpt.isNone()) { continue }
        let idx = idxOpt.getOrThrow()
        let key = line[0..idx].trimAscii().toAsciiLower()
        if (key == lowerName) {
            return line[idx + 1..].trimAscii()
        }
    }
    return ""
}

func requestBody(request: String): String {
    let mark = "\r\n\r\n"
    let idxOpt = request.indexOf(mark)
    if (idxOpt.isNone()) { return "" }
    return request[idxOpt.getOrThrow() + mark.size..]
}

func extractJsonString(text: String, key: String): String {
    let pattern = "\"${key}\""
    let idxOpt = text.indexOf(pattern)
    if (idxOpt.isNone()) { return "" }
    let idx = idxOpt.getOrThrow()
    let rest = text[idx + pattern.size..]
    let colonOpt = rest.indexOf(":")
    if (colonOpt.isNone()) { return "" }
    let afterColon = rest[colonOpt.getOrThrow() + 1..].trimAscii()
    if (afterColon.size == 0 || afterColon[0] != b'"') { return "" }
    let valueRest = afterColon[1..]
    let endOpt = valueRest.indexOf("\"")
    if (endOpt.isNone()) { return "" }
    return valueRest[0..endOpt.getOrThrow()]
}

func extractParam(headers: String, key: String): String {
    let pattern = "${key}=\""
    let idxOpt = headers.indexOf(pattern)
    if (idxOpt.isNone()) { return "" }
    let start = idxOpt.getOrThrow() + pattern.size
    let rest = headers[start..]
    let endOpt = rest.indexOf("\"")
    if (endOpt.isNone()) { return "" }
    return rest[0..endOpt.getOrThrow()]
}

func stripMultipartTail(value: String): String {
    var out = value
    while (out.endsWith("\r\n")) {
        out = out[0..out.size - 2]
    }
    if (out.endsWith("--")) {
        out = out[0..out.size - 2]
    }
    return out
}

class FormPart {
    let name: String
    let filename: String
    let content: String
    let bytes: Array<Byte>

    init(name!: String, filename!: String, content!: String, bytes!: Array<Byte>) {
        this.name = name
        this.filename = filename
        this.content = content
        this.bytes = bytes
    }
}

func bytesIndexOf(source: Array<Byte>, pattern: Array<Byte>, start: Int64): Int64 {
    if (pattern.size == 0 || source.size < pattern.size || start >= source.size) {
        return -1
    }
    var i = start
    while (i <= source.size - pattern.size) {
        var matched = true
        var j: Int64 = 0
        while (j < pattern.size) {
            if (source[i + j] != pattern[j]) {
                matched = false
                break
            }
            j += 1
        }
        if (matched) { return i }
        i += 1
    }
    return -1
}

func trimMultipartContentBytes(source: Array<Byte>, start: Int64, end: Int64): Array<Byte> {
    var realEnd = end
    if (realEnd - start >= 2 && source[realEnd - 2] == b'\r' && source[realEnd - 1] == b'\n') {
        realEnd -= 2
    }
    return source[start..realEnd]
}

func parseMultipartBytes(requestBytes: Array<Byte>): ArrayList<FormPart> {
    let parts = ArrayList<FormPart>()
    let headerBodyMark = "\r\n\r\n".toArray()
    let requestHeaderEnd = bytesIndexOf(requestBytes, headerBodyMark, 0)
    if (requestHeaderEnd < 0) { return parts }

    let requestHeader = String.fromUtf8(requestBytes[0..requestHeaderEnd])
    let contentTypeHeader = headerValue(requestHeader, "Content-Type")
    let boundaryKey = "boundary="
    let boundaryIdxOpt = contentTypeHeader.indexOf(boundaryKey)
    if (boundaryIdxOpt.isNone()) { return parts }
    let boundary = ("--" + contentTypeHeader[boundaryIdxOpt.getOrThrow() + boundaryKey.size..].trimAscii()).toArray()
    var boundaryAt = bytesIndexOf(requestBytes, boundary, requestHeaderEnd + headerBodyMark.size)
    while (boundaryAt >= 0) {
        var partStart = boundaryAt + boundary.size
        if (partStart + 1 < requestBytes.size && requestBytes[partStart] == b'-' && requestBytes[partStart + 1] == b'-') {
            break
        }
        if (partStart + 1 < requestBytes.size && requestBytes[partStart] == b'\r' && requestBytes[partStart + 1] == b'\n') {
            partStart += 2
        }

        let splitIdx = bytesIndexOf(requestBytes, headerBodyMark, partStart)
        if (splitIdx < 0) { break }
        let headers = String.fromUtf8(requestBytes[partStart..splitIdx])
        let contentStart = splitIdx + headerBodyMark.size
        let nextBoundary = bytesIndexOf(requestBytes, boundary, contentStart)
        if (nextBoundary < 0) { break }
        let contentBytes = trimMultipartContentBytes(requestBytes, contentStart, nextBoundary)
        let name = extractParam(headers, "name")
        if (name != "") {
            let filename = extractParam(headers, "filename")
            if (filename == "") {
                var content = ""
                if (contentBytes.size > 0) {
                    content = String.fromUtf8(contentBytes)
                }
                parts.add(FormPart(name: name, filename: filename, content: content, bytes: contentBytes))
            } else {
                parts.add(FormPart(name: name, filename: filename, content: "", bytes: contentBytes))
            }
        }
        boundaryAt = nextBoundary
    }
    return parts
}

func formValue(parts: ArrayList<FormPart>, name: String): String {
    for (part in parts) {
        if (part.name == name) { return part.content }
    }
    return ""
}

func normalizeLanguage(language: String): String {
    let value = language.trimAscii()
    if (value == "zh" || value == "en" || value == "fr" || value == "auto") {
        return value
    }
    return "zh"
}

func formFile(parts: ArrayList<FormPart>): FormPart {
    for (part in parts) {
        if (part.name == "file" && part.filename != "") { return part }
    }
    return FormPart(name: "", filename: "", content: "", bytes: Array<Byte>())
}

func isVideo(filename: String): Bool {
    let lower = filename.toAsciiLower()
    return lower.endsWith(".mp4") || lower.endsWith(".mov") || lower.endsWith(".m4v") ||
        lower.endsWith(".avi") || lower.endsWith(".mkv") || lower.endsWith(".webm")
}

func projectId(): String {
    let now = DateTime.now()
    let t = now.time
    return "cj${t[0]}${t[1]}${t[2]}${now.nanosecond}"
}

func formatTime(seconds: Int64): String {
    let minutes = seconds / 60
    let sec = seconds % 60
    if (sec < 10) {
        return "${minutes}:0${sec}"
    }
    return "${minutes}:${sec}"
}

func projectIndexPath(id: String): String {
    return "${INDEX_DIR}/${id}.json"
}

func countSegments(text: String): Int64 {
    var count: Int64 = 0
    var rest = text
    while (true) {
        let idxOpt = rest.indexOf("\"text\"")
        if (idxOpt.isNone()) { break }
        count += 1
        rest = rest[idxOpt.getOrThrow() + 6..]
    }
    return count
}

func listProjectsJson(): String {
    let items = ArrayList<String>()
    for (entry in Directory.readFrom(INDEX_DIR)) {
        let path = "${INDEX_DIR}/${entry.name}"
        if (entry.name.endsWith(".json")) {
            let text = String.fromUtf8(File.readFrom(path))
            let id = extractJsonString(text, "id")
            let title = extractJsonString(text, "title")
            let filename = extractJsonString(text, "filename")
            let segments = countSegments(text)
            items.add("{\"id\":\"${jsonEscape(id)}\",\"title\":\"${jsonEscape(title)}\",\"filename\":\"${jsonEscape(filename)}\",\"segments\":${segments},\"created_at\":0}")
        }
    }
    var out = "{\"projects\":["
    for (i in 0..items.size) {
        if (i > 0) { out += "," }
        out += items[i]
    }
    out += "]}"
    return out
}

func saveProject(id: String, title: String, filename: String, segments: ArrayList<Segment>): Unit {
    var json = "{\n"
    json += "  \"id\": \"${jsonEscape(id)}\",\n"
    json += "  \"title\": \"${jsonEscape(title)}\",\n"
    json += "  \"filename\": \"${jsonEscape(filename)}\",\n"
    json += "  \"created_at\": 0,\n"
    json += "  \"segments\": [\n"
    for (i in 0..segments.size) {
        let s = segments[i]
        if (i > 0) { json += ",\n" }
        json += "    {\"start\": ${s.start}, \"end\": ${s.end}, \"text\": \"${jsonEscape(s.text)}\"}"
    }
    json += "\n  ]\n}"
    File.writeTo(projectIndexPath(id), json.toArray())
}

func transcribeUploadedVideo(config: AppConfig, id: String, filename: String, content: Array<Byte>, language: String): String {
    let videoPath = "${UPLOAD_DIR}/${id}_${filename}"
    let audioPath = "${UPLOAD_DIR}/${id}.wav"
    let transcriptBase = "${UPLOAD_DIR}/${id}_transcript"
    let transcriptTextPath = "${transcriptBase}.txt"

    File.writeTo(videoPath, content)
    let audio = extractAudio(config, videoPath, audioPath)
    if (!audio.ok()) {
        return "视频音频提取失败：${audio.stderr}"
    }
    let transcript = transcribeWithWhisperCpp(config, audioPath, transcriptBase, language)
    if (!transcript.ok()) {
        return "视频已上传并提取音频，但 whisper-cli 转写失败。请确认 whisper-cli.exe 和模型文件存在。\n${transcript.stderr}"
    }
    return String.fromUtf8(File.readFrom(transcriptTextPath))
}

func createProject(requestBytes: Array<Byte>): String {
    let config = AppConfig()
    let parts = parseMultipartBytes(requestBytes)
    var title = formValue(parts, "title")
    if (title == "") { title = "未命名视频" }
    var transcript = formValue(parts, "transcript")
    let language = normalizeLanguage(formValue(parts, "language"))
    var filename = "pasted.txt"
    let file = formFile(parts)
    let id = projectId()

    if (file.filename != "") {
        filename = file.filename
        if (isVideo(filename)) {
            transcript = transcribeUploadedVideo(config, id, filename, file.bytes, language)
            filename = "${filename}.transcript.txt"
        } else {
            transcript = String.fromUtf8(file.bytes)
        }
    }

    if (transcript.trimAscii() == "") {
        return jsonError("400 Bad Request", "没有可读取的视频转写文本或字幕内容")
    }

    let segments = splitTranscript(transcript)
    if (segments.size == 0) {
        return jsonError("400 Bad Request", "没有生成知识库片段")
    }
    saveProject(id, title, filename, segments)
    return response("200 OK", "application/json", "{\"project_id\":\"${id}\",\"title\":\"${jsonEscape(title)}\",\"segments\":${segments.size}}")
}

func loadProjectSegments(projectId: String): ArrayList<Segment> {
    let text = String.fromUtf8(File.readFrom(projectIndexPath(projectId)))
    let segments = ArrayList<Segment>()
    var rest = text
    var index: Int64 = 0
    while (true) {
        let textIdxOpt = rest.indexOf("\"text\"")
        if (textIdxOpt.isNone()) { break }
        let textIdx = textIdxOpt.getOrThrow()
        let afterText = rest[textIdx..]
        let value = extractJsonString(afterText, "text")
        if (value == "") { break }
        segments.add(Segment(start: index * 30, end: (index + 1) * 30, text: value))
        index += 1
        rest = afterText[6..]
    }
    return segments
}

func askProject(request: String): String {
    let body = requestBody(request)
    let projectIdValue = extractJsonString(body, "project_id")
    let question = extractJsonString(body, "question")
    if (projectIdValue == "" || question == "") {
        return jsonError("400 Bad Request", "缺少 project_id 或 question")
    }
    let segments = loadProjectSegments(projectIdValue)
    if (segments.size == 0) {
        return jsonError("404 Not Found", "没有找到这个知识库")
    }
    let context = buildContext(question, segments)
    let config = AppConfig()
    let apiKey = readDeepSeekApiKey()
    var answer = ""
    if (apiKey == "") {
        answer = "还没有配置 DeepSeek API Key，先返回本地检索片段：\n\n${context}\n\n配置方法：设置 DEEPSEEK_API_KEY，或把 Key 放到 config/deepseek_api_key.txt。"
    } else {
        let payload = buildDeepSeekPayload(config, question, context)
        let payloadPath = "${UPLOAD_DIR}/${projectIdValue}_deepseek_payload.json"
        File.writeTo(payloadPath, payload.toArray())
        let result = callDeepSeekWithCurl(config, apiKey, payloadPath)
        if (result.ok()) {
            let content = extractJsonString(result.stdout, "content")
            if (content != "") {
                answer = jsonUnescape(content)
            } else {
                answer = "DeepSeek 返回了结果，但仓颉后端没有解析到回答内容。先返回本地检索片段：\n\n${context}\n\n接口原始返回：\n${result.stdout}"
            }
        } else {
            answer = "DeepSeek 调用失败，先返回本地检索片段：\n\n${context}\n\n错误信息：\n${result.stderr}"
        }
    }
    return response("200 OK", "application/json", "{\"answer\":\"${jsonEscape(answer)}\",\"references\":[]}")
}

func handle(request: String): String {
    if (request.startsWith("OPTIONS ")) {
        return response("204 No Content", "text/plain", "")
    }
    if (request.startsWith("GET /health ") || request.startsWith("GET /api/health ")) {
        return response("200 OK", "application/json", "{\"ok\":true,\"backend\":\"cangjie\",\"replaces\":\"app/main.py\",\"asr\":\"ffmpeg+whisper.cpp\"}")
    }
    if (request.startsWith("GET /api/projects ") || request.startsWith("GET /projects ")) {
        return response("200 OK", "application/json", listProjectsJson())
    }
    if (request.startsWith("POST /api/projects ")) {
        return jsonError("400 Bad Request", "项目上传接口需要二进制请求处理")
    }
    if (request.startsWith("POST /api/ask ")) {
        return askProject(request)
    }
    if (request.startsWith("GET /static/app.js ")) {
        return serveFile("static/app.js")
    }
    if (request.startsWith("GET /static/styles.css ")) {
        return serveFile("static/styles.css")
    }
    if (request.startsWith("GET / ") || request.startsWith("GET /index.html ")) {
        return serveFile("static/index.html")
    }
    return response("404 Not Found", "application/json", "{\"error\":\"not found\"}")
}

func handleBytes(requestBytes: Array<Byte>): String {
    let headerBodyMark = "\r\n\r\n".toArray()
    let requestHeaderEnd = bytesIndexOf(requestBytes, headerBodyMark, 0)
    if (requestHeaderEnd < 0) {
        return jsonError("400 Bad Request", "HTTP 请求头不完整")
    }
    let requestHeader = String.fromUtf8(requestBytes[0..requestHeaderEnd])
    if (requestHeader.startsWith("POST /api/projects ")) {
        return createProject(requestBytes)
    }
    if (requestHeader.startsWith("POST /api/ask ")) {
        return handle(String.fromUtf8(requestBytes))
    }
    return handle(requestHeader + "\r\n\r\n")
}

main() {
    let port: UInt16 = 8090
    let server = TcpServerSocket(bindAt: port)
    server.bind()
    println("Cangjie backend listening on http://127.0.0.1:${port}")

    while (true) {
        let client = server.accept()
        spawn {
            // Local demo limit: keep uploaded videos short/compressed to avoid memory pressure.
            let buffer = Array<Byte>(12 * 1024 * 1024, repeat: 0)
            let length = client.read(buffer)
            if (length > 0) {
                let res = handleBytes(buffer[0..length])
                client.write(res.toArray())
            }
            client.close()
        }
    }
}
