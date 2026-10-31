let activeProjectId = null;
let activeTitle = "";

const projectForm = document.getElementById("projectForm");
const askForm = document.getElementById("askForm");
const projectsEl = document.getElementById("projects");
const messagesEl = document.getElementById("messages");
const activeProjectEl = document.getElementById("activeProject");
const statusEl = document.getElementById("status");
const avatarEl = document.getElementById("avatar");
const speechEnabledEl = document.getElementById("speechEnabled");
const stopSpeechEl = document.getElementById("stopSpeech");

function canSpeak() {
  return "speechSynthesis" in window && "SpeechSynthesisUtterance" in window;
}

function setStatus(text) {
  statusEl.textContent = text;
}

async function readErrorMessage(response) {
  const text = await response.text();
  try {
    const data = JSON.parse(text);
    return data.detail || data.error || text;
  } catch (_) {
    return text;
  }
}

function stopSpeaking() {
  if (!canSpeak()) return;
  window.speechSynthesis.cancel();
  avatarEl.classList.remove("speaking");
}

function speakText(text) {
  if (!canSpeak() || !speechEnabledEl.checked) return;
  stopSpeaking();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = "zh-CN";
  utterance.rate = 1;
  utterance.pitch = 1;
  utterance.onstart = () => {
    avatarEl.classList.add("speaking");
    setStatus("正在语音播报");
  };
  utterance.onend = () => {
    avatarEl.classList.remove("speaking");
    setStatus("DeepSeek 总结就绪");
  };
  utterance.onerror = () => {
    avatarEl.classList.remove("speaking");
    setStatus("语音播报失败");
  };
  window.speechSynthesis.speak(utterance);
}

function addMessage(text, type = "bot", refs = []) {
  const node = document.createElement("div");
  node.className = `message ${type}`;
  node.textContent = text;
  if (refs.length) {
    const refNode = document.createElement("div");
    refNode.className = "refs";
    refNode.textContent = "参考片段：" + refs.map((item) => item.time).join(" / ");
    node.appendChild(refNode);
  }
  if (type === "bot" && canSpeak()) {
    const button = document.createElement("button");
    button.className = "speak-button";
    button.type = "button";
    button.textContent = "播报这条回答";
    button.onclick = () => speakText(text);
    node.appendChild(button);
  }
  messagesEl.appendChild(node);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

async function loadProjects() {
  const response = await fetch("/api/projects");
  const data = await response.json();
  projectsEl.innerHTML = "";
  data.projects.forEach((project) => {
    const button = document.createElement("button");
    button.className = "project";
    button.type = "button";
    button.textContent = `${project.title} · ${project.segments} 段`;
    button.onclick = () => {
      activeProjectId = project.id;
      activeTitle = project.title;
      activeProjectEl.textContent = `当前知识库：${activeTitle}`;
    };
    projectsEl.appendChild(button);
  });
}

projectForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const formData = new FormData(projectForm);
  const file = formData.get("file");
  const fileName = file && file.name ? file.name.toLowerCase() : "";
  const pastedText = String(formData.get("transcript") || "").trim();
  if (!fileName && !pastedText) {
    setStatus("请先选择视频/字幕或粘贴文本");
    addMessage("建立知识库失败：请先选择一个视频/字幕文件，或者在文本框里粘贴视频转写内容。");
    return;
  }
  const isVideo = [".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"].some((ext) => fileName.endsWith(ext));
  setStatus(isVideo ? "正在上传并识别视频，首次可能需要几分钟" : "正在建立知识库");
  avatarEl.classList.add("speaking");
  const response = await fetch("/api/projects", { method: "POST", body: formData });
  avatarEl.classList.remove("speaking");

  if (!response.ok) {
    const text = await readErrorMessage(response);
    setStatus("建立失败");
    addMessage(`建立知识库失败：${text}\n\n请检查：1. 是否选择了视频/字幕文件；2. 是否粘贴了文本；3. 如果上传视频，是否已经配置 ffmpeg 和 whisper-cli。`);
    return;
  }

  const data = await response.json();
  activeProjectId = data.project_id;
  activeTitle = data.title;
  activeProjectEl.textContent = `当前知识库：${activeTitle}`;
  setStatus("知识库已建立");
  addMessage(`已建立知识库：${data.title}，共 ${data.segments} 个片段。`);
  projectForm.reset();
  await loadProjects();
});

askForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = document.getElementById("question");
  const question = input.value.trim();
  if (!question) return;
  if (!activeProjectId) {
    addMessage("请先创建或选择一个知识库。");
    return;
  }

  addMessage(question, "user");
  input.value = "";
  setStatus("正在思考");
  avatarEl.classList.add("speaking");

  const response = await fetch("/api/ask", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ project_id: activeProjectId, question }),
  });
  avatarEl.classList.remove("speaking");

  if (!response.ok) {
    const text = await readErrorMessage(response);
    setStatus("回答失败");
    addMessage(`回答失败：${text}`);
    return;
  }

  const data = await response.json();
  addMessage(data.answer, "bot", data.references);
  setStatus("DeepSeek 总结就绪");
  speakText(data.answer);
});

stopSpeechEl.addEventListener("click", stopSpeaking);
speechEnabledEl.addEventListener("change", () => {
  if (!speechEnabledEl.checked) {
    stopSpeaking();
  }
});

loadProjects().catch(() => setStatus("项目列表读取失败"));
