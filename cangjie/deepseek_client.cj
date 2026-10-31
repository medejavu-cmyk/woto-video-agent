package wotoagent

public func buildDeepSeekPayload(config: AppConfig, question: String, context: String): String {
    let prompt = """
你是喔图AI视频知识库智能体。
只能根据给定视频片段回答问题。
回答要简洁，并尽量标注相关时间点。
如果资料不足，直接说明资料不足。

视频片段：
${context}

用户问题：
${question}
"""

    return """
{
  "model": "${config.deepseekModel}",
  "temperature": 0.2,
  "messages": [
    {"role": "user", "content": "${escapeJson(prompt)}"}
  ]
}
"""
}

public func escapeJson(input: String): String {
    return input
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
}

public func readDeepSeekApiKey(): String {
    let script = "if defined DEEPSEEK_API_KEY (echo %DEEPSEEK_API_KEY%) else if exist config\\deepseek_api_key.txt (type config\\deepseek_api_key.txt)"
    let result = runCommand("cmd", ["/c", script])
    if (!result.ok()) {
        return ""
    }
    return result.stdout.trimAscii()
}

public func callDeepSeekWithCurl(config: AppConfig, apiKey: String, payloadFile: String): CommandResult {
    if (apiKey == "") {
        return CommandResult(code: 1, stdout: "", stderr: "DEEPSEEK_API_KEY is not set")
    }
    let args = [
        "-s",
        config.deepseekApiUrl,
        "-H", "Content-Type: application/json",
        "-H", "Authorization: Bearer ${apiKey}",
        "--data-binary", "@${payloadFile}"
    ]
    return runCommand("curl", args)
}
