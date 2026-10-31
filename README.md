# 喔图 AI 视频知识库智能体

本地视频语音转写与内容问答原型。仓颉后端调度 FFmpeg、whisper.cpp，将转写文本切片并检索，再通过 DeepSeek API 生成回答。也保留了可独立启动的 Python 字幕问答 MVP。

**状态：实验原型，仓颉源码已编译通过，尚未完成端到端复现。** 当前公开候选不包含视频、用户索引、密钥、模型、二进制程序或海报。

## 实际能力与边界

- 仓颉源码包含网页服务、上传建库、语音转写调度、文本检索与问答接口。
- 处理的是视频中的语音；未实现画面理解、OCR、向量数据库或自主规划。
- Python MVP 接收字幕或转写文本；不具备自动视频转写能力。
- 未设置 API Key 时可返回检索片段；生成模型回答需要自行配置 DeepSeek。
- 仓颉 HTTP 实现每连接只读取一次、缓冲区为 12 MiB，无法保证完整接收较大或分段上传。仅供本地实验，暂不建议暴露公网。
- 配置了模型 API 后，问题和检索文本会发送至所配置的服务。

## 仓颉版：Windows

需要仓颉 SDK/runtime、PATH 中的 `ffmpeg`、`whisper-cli`、`curl`，以及自行取得的 `models/ggml-tiny.bin`。模型及工具的许可由各自发布方提供。当前 SDK、模型和工具组合尚未完成完整运行验证。

在仓库根目录使用 PowerShell：

```powershell
New-Item -ItemType Directory -Force work | Out-Null
New-Item -ItemType Directory -Force data/indexes,data/uploads | Out-Null
cjc cangjie\main.cj cangjie\config.cj cangjie\asr_task.cj cangjie\knowledge.cj cangjie\deepseek_client.cj -o work\woto_cangjie_backend.exe
if ($LASTEXITCODE -ne 0) { throw '编译失败，请先检查 SDK 和错误输出' }
$env:DEEPSEEK_API_KEY = '在本机填写，不要提交'
.\work\woto_cangjie_backend.exe
```

访问 `http://127.0.0.1:8090`，健康检查为 `/api/health`。请先在本机配置仓颉 runtime。`cangjie/config.cj` 中的模型名称需根据自己的 API 账户确认可用性。也支持本地 `config/deepseek_api_key.txt`，但推荐环境变量。

## Python MVP：字幕问答

在仓库根目录使用 PowerShell：

```powershell
cd legacy-python
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

访问 `http://127.0.0.1:8000`。粘贴 `examples/demo.txt` 的文字建立知识库，再询问“这段内容介绍了什么？”。如需生成模型回答，在启动前设置 `DEEPSEEK_API_KEY`；可用 `DEEPSEEK_MODEL` 覆盖模型名称。当前代码不自动读取 `.env`。

## 文件结构

```text
cangjie/          仓颉后端源码
static/           仓颉版网页
legacy-python/    独立的 Python 字幕问答 MVP 及其依赖
config/           配置说明，不含真实密钥
examples/         原创的最小演示文本
docs/             发布检查及主页展示计划
```

Python 依赖仅适用于 `legacy-python`，仓颉版不需要 `pip install`。首次运行生成的 `data/` 不提交。

## 许可与来源

作者：medejavu-cmyk。作者确认本项目由个人独立完成，开发过程中使用了 AI 辅助；“喔图”为自行拟定的项目名称，原项目素材为作者自有。此名称不表示与任何同名企业或产品存在关联。

本仓库代码采用 [MIT License](LICENSE)，允许复制、修改和再分发，使用时需保留许可证与版权声明。FFmpeg、whisper.cpp、仓颉 SDK、模型及 DeepSeek 服务分别遵循各自的许可证或服务条款，不包含在本项目的许可授权中。

验证记录与发布前事项见 `docs/RELEASE-CHECKLIST.md`。
