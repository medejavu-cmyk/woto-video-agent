package wotoagent

import std.process.*

public class CommandResult {
    public let code: Int64
    public let stdout: String
    public let stderr: String

    public init(code!: Int64, stdout!: String, stderr!: String) {
        this.code = code
        this.stdout = stdout
        this.stderr = stderr
    }

    public func ok(): Bool {
        return code == 0
    }
}

public func runCommand(command: String, args: Array<String>): CommandResult {
    let (code, stdoutBytes, stderrBytes) = executeWithOutput(command, args)
    return CommandResult(
        code: code,
        stdout: String.fromUtf8(stdoutBytes),
        stderr: String.fromUtf8(stderrBytes)
    )
}

public func extractAudio(config: AppConfig, videoPath: String, audioPath: String): CommandResult {
    let args = [
        "-y",
        "-i", videoPath,
        "-vn",
        "-ac", "1",
        "-ar", "16000",
        "-f", "wav",
        audioPath
    ]
    return runCommand(config.ffmpegPath, args)
}

public func transcribeWithWhisperCpp(config: AppConfig, audioPath: String, transcriptPath: String, language: String): CommandResult {
    let args = [
        "-m", config.whisperModelPath,
        "-f", audioPath,
        "-l", language,
        "-otxt",
        "-of", transcriptPath
    ]
    return runCommand(config.whisperCliPath, args)
}
