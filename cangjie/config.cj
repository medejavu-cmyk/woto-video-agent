package wotoagent

public class AppConfig {
    public let deepseekApiKey: String
    public let deepseekModel: String
    public let deepseekApiUrl: String
    public let ffmpegPath: String
    public let whisperCliPath: String
    public let whisperModelPath: String
    public let dataDir: String

    public init() {
        deepseekApiKey = ""
        deepseekModel = "deepseek-v4-flash"
        deepseekApiUrl = "https://api.deepseek.com/chat/completions"
        ffmpegPath = "ffmpeg"
        whisperCliPath = "whisper-cli"
        whisperModelPath = "models/ggml-tiny.bin"
        dataDir = "data"
    }
}
