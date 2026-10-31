import json
import os
import re
import time
import uuid
from pathlib import Path
from typing import Dict, List, Optional

import httpx
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel


ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
INDEX_DIR = DATA_DIR / "indexes"
UPLOAD_DIR = DATA_DIR / "uploads"
STATIC_DIR = Path(__file__).resolve().parent / "static"

# A fresh clone has no generated data directories.
INDEX_DIR.mkdir(parents=True, exist_ok=True)
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

DEEPSEEK_API_URL = os.getenv("DEEPSEEK_API_URL", "https://api.deepseek.com/chat/completions")
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat")

app = FastAPI(title="Woto Video Knowledge Agent")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


class AskRequest(BaseModel):
    project_id: str
    question: str


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("\ufeff", "")).strip()


def split_text(text: str, size: int = 500, overlap: int = 80) -> List[str]:
    clean = normalize_text(text)
    if not clean:
        return []

    chunks: List[str] = []
    start = 0
    while start < len(clean):
        end = min(len(clean), start + size)
        chunks.append(clean[start:end])
        if end == len(clean):
            break
        start = max(0, end - overlap)
    return chunks


def parse_srt_time(value: str) -> int:
    match = re.match(r"(\d{2}):(\d{2}):(\d{2}),(\d{3})", value.strip())
    if not match:
        return 0
    hours, minutes, seconds, millis = [int(part) for part in match.groups()]
    return hours * 3600 + minutes * 60 + seconds + int(millis / 1000)


def parse_srt(text: str) -> List[Dict]:
    blocks = re.split(r"\n\s*\n", text.replace("\r\n", "\n"))
    segments: List[Dict] = []
    for block in blocks:
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        if len(lines) < 2:
            continue
        time_line = next((line for line in lines if "-->" in line), "")
        if not time_line:
            continue
        start_raw, end_raw = [part.strip() for part in time_line.split("-->", 1)]
        content_lines = lines[lines.index(time_line) + 1 :]
        content = normalize_text(" ".join(content_lines))
        if content:
            segments.append(
                {
                    "start": parse_srt_time(start_raw),
                    "end": parse_srt_time(end_raw),
                    "text": content,
                }
            )
    return segments


def build_segments(text: str, filename: str) -> List[Dict]:
    if filename.lower().endswith(".srt"):
        parsed = parse_srt(text)
        if parsed:
            return parsed

    chunks = split_text(text)
    return [
        {
            "start": index * 30,
            "end": (index + 1) * 30,
            "text": chunk,
        }
        for index, chunk in enumerate(chunks)
    ]


def token_set(text: str) -> set:
    words = set(re.findall(r"[a-zA-Z0-9_]+", text.lower()))
    chinese = {text[i : i + 2] for i in range(max(0, len(text) - 1)) if "\u4e00" <= text[i] <= "\u9fff"}
    return words | chinese


def score_segment(question: str, segment_text: str) -> float:
    q_tokens = token_set(question)
    s_tokens = token_set(segment_text)
    if not q_tokens or not s_tokens:
        return 0.0
    overlap = len(q_tokens & s_tokens)
    density = overlap / max(1, len(q_tokens))
    exact_bonus = 1.0 if question.strip() and question.strip() in segment_text else 0.0
    return density + exact_bonus


def index_path(project_id: str) -> Path:
    return INDEX_DIR / f"{project_id}.json"


def load_project(project_id: str) -> Dict:
    path = index_path(project_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="project not found")
    return json.loads(path.read_text(encoding="utf-8"))


def select_context(question: str, segments: List[Dict], limit: int = 5) -> List[Dict]:
    ranked = sorted(
        segments,
        key=lambda item: score_segment(question, item["text"]),
        reverse=True,
    )
    selected = [item for item in ranked[:limit] if score_segment(question, item["text"]) > 0]
    return selected or ranked[: min(limit, len(ranked))]


def format_time(seconds: int) -> str:
    minutes = seconds // 60
    sec = seconds % 60
    return f"{minutes:02d}:{sec:02d}"


async def call_deepseek(question: str, context: List[Dict]) -> str:
    api_key = os.getenv("DEEPSEEK_API_KEY")
    if not api_key:
        context_text = "\n".join(
            f"[{format_time(item['start'])}-{format_time(item['end'])}] {item['text']}"
            for item in context
        )
        return (
            "当前没有配置 DEEPSEEK_API_KEY，因此先返回检索结果。配置 API Key 后我会基于这些片段生成完整回答。\n\n"
            + context_text
        )

    messages = [
        {
            "role": "system",
            "content": (
                "你是喔图 AI 视频知识库智能体。只能根据给定的视频片段回答。"
                "回答要简洁、可信，尽量标注相关时间点。如果资料不足，直接说明。"
            ),
        },
        {
            "role": "user",
            "content": "视频片段：\n"
            + "\n".join(
                f"[{format_time(item['start'])}-{format_time(item['end'])}] {item['text']}"
                for item in context
            )
            + f"\n\n用户问题：{question}",
        },
    ]
    payload = {"model": DEEPSEEK_MODEL, "messages": messages, "temperature": 0.2}
    async with httpx.AsyncClient(timeout=60) as client:
        response = await client.post(
            DEEPSEEK_API_URL,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json=payload,
        )
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail=response.text)
    data = response.json()
    return data["choices"][0]["message"]["content"]


@app.get("/")
def home():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
def health():
    return {"ok": True, "model": DEEPSEEK_MODEL, "has_deepseek_key": bool(os.getenv("DEEPSEEK_API_KEY"))}


@app.post("/api/projects")
async def create_project(
    title: str = Form("未命名视频"),
    transcript: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
):
    if not transcript and not file:
        raise HTTPException(status_code=400, detail="upload a transcript file or paste transcript text")

    project_id = uuid.uuid4().hex[:12]
    filename = "pasted.txt"
    text = transcript or ""

    if file:
        filename = file.filename or "transcript.txt"
        content = await file.read()
        upload_path = UPLOAD_DIR / f"{project_id}_{filename}"
        upload_path.write_bytes(content)
        try:
            text = content.decode("utf-8")
        except UnicodeDecodeError:
            text = content.decode("gb18030", errors="ignore")

    segments = build_segments(text, filename)
    if not segments:
        raise HTTPException(status_code=400, detail="no readable transcript content")

    project = {
        "id": project_id,
        "title": title,
        "filename": filename,
        "created_at": int(time.time()),
        "segments": segments,
    }
    index_path(project_id).write_text(json.dumps(project, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"project_id": project_id, "title": title, "segments": len(segments)}


@app.get("/api/projects")
def list_projects():
    projects = []
    for path in sorted(INDEX_DIR.glob("*.json"), key=lambda item: item.stat().st_mtime, reverse=True):
        data = json.loads(path.read_text(encoding="utf-8"))
        projects.append(
            {
                "id": data["id"],
                "title": data["title"],
                "filename": data["filename"],
                "segments": len(data["segments"]),
                "created_at": data["created_at"],
            }
        )
    return {"projects": projects}


@app.post("/api/ask")
async def ask(request: AskRequest):
    project = load_project(request.project_id)
    context = select_context(request.question, project["segments"])
    answer = await call_deepseek(request.question, context)
    return {
        "answer": answer,
        "references": [
            {"start": item["start"], "end": item["end"], "time": f"{format_time(item['start'])}-{format_time(item['end'])}", "text": item["text"]}
            for item in context
        ],
    }
