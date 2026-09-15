// sidepanel.js — The chat UI for the browser extension's side panel.
//
// This runs in the extension's side panel context. It talks to the
// content script (via the background service worker) to send chat
// requests and receive streamed responses.

const $ = (sel) => document.querySelector(sel);

// ---- State ----
let currentChat = []; // [{role, content, reasoning}]
let currentModel = 'glm-4.7';
let availableModels = [];

// ---- Init ----
document.addEventListener('DOMContentLoaded', async () => {
  // Load saved model preference.
  const saved = await chrome.storage.local.get(['lagestroemia_model']);
  if (saved.lagestroemia_model) {
    currentModel = saved.lagestroemia_model;
  }

  // Fetch model list.
  await loadModels();

  // Set up event listeners.
  $('#send-btn').addEventListener('click', sendMessage);
  $('#msg-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });
  $('#model-select').addEventListener('change', (e) => {
    currentModel = e.target.value;
    chrome.storage.local.set({ lagestroemia_model: currentModel });
  });

  // Listen for streaming chunks.
  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === 'chatChunk') {
      onChunk(message.chunk);
    } else if (message.type === 'chatStatus') {
      onStatus(message.status);
    }
  });

  // Clear chat button.
  $('#clear-btn').addEventListener('click', () => {
    currentChat = [];
    renderChat();
  });
});

// ---- Load models ----
async function loadModels() {
  try {
    // Ask the content script for the model list.
    const resp = await chrome.runtime.sendMessage({ type: 'getModels' });
    if (resp.ok) {
      availableModels = resp.models;
    }
  } catch (e) {
    console.error('Failed to load models:', e);
  }

  // Populate the model selector.
  const select = $('#model-select');
  select.innerHTML = '';
  const fallbackModels = [
    { id: 'glm-4.7', name: 'GLM-4.7' },
    { id: 'x-preview-l', name: 'GLM-5.3-Flash' },
    { id: 'glm-5.3', name: 'GLM-5.3' },
    { id: 'glm-5.2', name: 'GLM-5.2' },
    { id: 'glm-4.6v', name: 'GLM-4.6V' },
    { id: 'GLM-4.1V-Thinking-FlashX', name: 'GLM-4.1V-Thinking' },
    { id: 'deep-research', name: 'Z1-Rumination' },
    { id: 'zero', name: 'Z1-32B' },
  ];
  const models = availableModels.length > 0
    ? availableModels.map(m => ({ id: m.id, name: m.name || m.id }))
    : fallbackModels;

  for (const m of models) {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = m.name;
    if (m.id === currentModel) opt.selected = true;
    select.appendChild(opt);
  }
}

// ---- Send message ----
async function sendMessage() {
  const input = $('#msg-input');
  const text = input.value.trim();
  if (!text) return;

  // Add user message to chat.
  currentChat.push({ role: 'user', content: text });
  renderChat();
  input.value = '';

  // Add empty assistant message for streaming.
  const assistantMsg = { role: 'assistant', content: '', reasoning: '' };
  currentChat.push(assistantMsg);
  renderChat();

  // Build the messages payload (only role + content).
  const messages = currentChat
    .filter(m => m.content) // skip empty assistant placeholder
    .map(m => ({ role: m.role, content: m.content }));

  // Send via the background script → content script.
  setStatus('Sending…');
  $('#send-btn').disabled = true;

  try {
    const resp = await chrome.runtime.sendMessage({
      type: 'sendChat',
      messages: messages,
      model: currentModel,
      options: {},
    });

    if (!resp.ok) {
      assistantMsg.content = `Error: ${resp.error}`;
      renderChat();
    }
  } catch (e) {
    assistantMsg.content = `Error: ${e.message}`;
    renderChat();
  } finally {
    $('#send-btn').disabled = false;
    setStatus('');
  }
}

// ---- Streaming chunk handler ----
function onChunk(chunk) {
  // Update the last assistant message.
  if (currentChat.length > 0 && currentChat[currentChat.length - 1].role === 'assistant') {
    const msg = currentChat[currentChat.length - 1];
    if (chunk.content) msg.content += chunk.content;
    if (chunk.reasoning) msg.reasoning += chunk.reasoning;
    renderChat();
  }
}

// ---- Status handler ----
function setStatus(status) {
  $('#status').textContent = status;
}

function onStatus(status) {
  setStatus(status);
}

// ---- Render chat ----
function renderChat() {
  const container = $('#chat-container');
  container.innerHTML = '';

  for (const msg of currentChat) {
    const div = document.createElement('div');
    div.className = `msg msg-${msg.role}`;

    if (msg.role === 'user') {
      div.innerHTML = `<div class="msg-bubble user-bubble">${escapeHtml(msg.content)}</div>`;
    } else {
      // Assistant message with optional reasoning.
      let html = '';
      if (msg.reasoning) {
        html += `<details class="reasoning"><summary>Reasoning</summary><div>${escapeHtml(msg.reasoning)}</div></details>`;
      }
      html += `<div class="msg-bubble assistant-bubble">${escapeHtml(msg.content) || '<span class="typing">▏</span>'}</div>`;
      div.innerHTML = html;
    }

    container.appendChild(div);
  }

  // Auto-scroll to bottom.
  container.scrollTop = container.scrollHeight;
}

// ---- Utility ----
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}
