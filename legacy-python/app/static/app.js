let activeProjectId = null;
let activeTitle = "";

const projectForm = document.getElementById("projectForm");
const askForm = document.getElementById("askForm");
const projectsEl = document.getElementById("projects");
const messagesEl = document.getElementById("messages");
const activeProjectEl = document.getElementById("activeProject");
const statusEl = document.getElementById("status");
const avatarEl = document.getElementById("avatar");

function setStatus(text) {
  statusEl.textContent = text;
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
  setStatus("正在建立知识库");
  avatarEl.classList.add("speaking");
  const formData = new FormData(projectForm);
  const response = await fetch("/api/projects", { method: "POST", body: formData });
  avatarEl.classList.remove("speaking");

  if (!response.ok) {
    const text = await response.text();
    setStatus("建立失败");
    addMessage(`建立知识库失败：${text}`);
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
    const text = await response.text();
    setStatus("回答失败");
    addMessage(`回答失败：${text}`);
    return;
  }

  const data = await response.json();
  addMessage(data.answer, "bot", data.references);
  setStatus("本地检索就绪");
});

loadProjects().catch(() => setStatus("项目列表读取失败"));
