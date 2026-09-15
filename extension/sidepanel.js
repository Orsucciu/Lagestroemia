// sidepanel.js — The chat UI + live debug console for the extension.

const $ = (sel) => document.querySelector(sel);

// ---- State ----
let currentChat = [];
let currentModel = 'glm-4.7';
let availableModels = [];

// ---- Debug log ----
function debugLog(msg) {
    const el = $('#debug-log');
    if (!el) return;
    const time = new Date().toLocaleTimeString();
    const line = document.createElement('div');
    line.className = 'debug-line';
    line.innerHTML = `<span class="debug-time">${time}</span> ${escapeHtml(msg)}`;
    el.appendChild(line);
    el.scrollTop = el.scrollHeight;
    while (el.children.length > 100) el.removeChild(el.firstChild);
}

// ---- Init ----
document.addEventListener('DOMContentLoaded', async () => {
    debugLog('Side panel opened');

    const saved = await chrome.storage.local.get(['lagestroemia_model']);
    if (saved.lagestroemia_model) currentModel = saved.lagestroemia_model;

    await loadModels();

    $('#send-btn').addEventListener('click', sendMessage);
    $('#msg-input').addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage(); }
    });
    $('#model-select').addEventListener('change', (e) => {
        currentModel = e.target.value;
        chrome.storage.local.set({ lagestroemia_model: currentModel });
        debugLog(`Model: ${currentModel}`);
    });
    $('#clear-btn').addEventListener('click', () => { currentChat = []; renderChat(); debugLog('Chat cleared'); });
    $('#debug-toggle').addEventListener('click', () => {
        const p = $('#debug-panel');
        p.style.display = p.style.display === 'none' ? 'flex' : 'none';
    });

    // Check native host status.
    try {
        const health = await fetch('http://127.0.0.1:8081/health').then(r => r.json());
        debugLog(`Server: ok=${health.ok}, connected=${health.extension_connected}`);
        if (health.extension_connected) {
            $('#status-dot').className = 'status-dot connected';
            $('#status-text').textContent = 'Server on :8081';
        } else {
            $('#status-dot').className = 'status-dot disconnected';
            $('#status-text').textContent = 'No server';
        }
    } catch {
        debugLog('Server not reachable');
        $('#status-dot').className = 'status-dot disconnected';
        $('#status-text').textContent = 'No server';
    }

    // Listen for ALL messages (for debugging + UI updates).
    chrome.runtime.onMessage.addListener((message, sender) => {
        const msgType = message.type || 'unknown';
        const from = sender.tab ? `tab:${sender.tab.id}` : 'bg';

        if (msgType === 'chatChunk') {
            const c = message.chunk?.content || '';
            const r = message.chunk?.reasoning || '';
            if (c) debugLog(`← chunk "${c.substring(0, 40)}"`);
            if (r) debugLog(`← reasoning "${r.substring(0, 40)}"`);
            onChunk(message.chunk);
        } else if (msgType === 'chatStatus') {
            debugLog(`status: ${message.status}`);
        } else if (msgType === 'chatComplete') {
            debugLog('✅ Stream complete');
        } else if (msgType === 'chatError') {
            debugLog(`❌ Error: ${message.error}`);
        } else if (msgType === 'nativeStatus') {
            debugLog(`native: ${message.connected ? 'CONNECTED' : 'DISCONNECTED'}`);
            $('#status-dot').className = message.connected ? 'status-dot connected' : 'status-dot disconnected';
            $('#status-text').textContent = message.connected ? 'Server on :8081' : 'No server';
        } else {
            debugLog(`msg: ${msgType} ← ${from}`);
        }
    });

    debugLog('Ready. Type a message and press Enter.');
});

// ---- Load models ----
async function loadModels() {
    try {
        const resp = await chrome.runtime.sendMessage({ type: 'getModels' });
        if (resp.ok) availableModels = resp.models;
    } catch (e) { debugLog(`loadModels error: ${e.message}`); }

    const select = $('#model-select');
    select.innerHTML = '';
    const fallback = [
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
        : fallback;
    for (const m of models) {
        const opt = document.createElement('option');
        opt.value = m.id; opt.textContent = m.name;
        if (m.id === currentModel) opt.selected = true;
        select.appendChild(opt);
    }
}

// ---- Send message ----
async function sendMessage() {
    const input = $('#msg-input');
    const text = input.value.trim();
    if (!text) return;

    currentChat.push({ role: 'user', content: text });
    renderChat();
    input.value = '';

    const assistantMsg = { role: 'assistant', content: '', reasoning: '' };
    currentChat.push(assistantMsg);
    renderChat();

    const messages = currentChat.filter(m => m.content).map(m => ({ role: m.role, content: m.content }));

    debugLog(`→ sendChat: model=${currentModel}, msg="${text.substring(0, 40)}"`);
    $('#send-btn').disabled = true;

    try {
        const resp = await chrome.runtime.sendMessage({ type: 'sendChat', messages, model: currentModel, options: {} });
        if (!resp.ok) {
            assistantMsg.content = `Error: ${resp.error}`;
            renderChat();
            debugLog(`❌ ${resp.error}`);
        }
    } catch (e) {
        assistantMsg.content = `Error: ${e.message}`;
        renderChat();
        debugLog(`❌ ${e.message}`);
    } finally {
        $('#send-btn').disabled = false;
    }
}

// ---- Streaming chunk handler ----
function onChunk(chunk) {
    if (currentChat.length > 0 && currentChat[currentChat.length - 1].role === 'assistant') {
        const msg = currentChat[currentChat.length - 1];
        if (chunk.content) msg.content += chunk.content;
        if (chunk.reasoning) msg.reasoning += chunk.reasoning;
        renderChat();
    }
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
            let html = '';
            if (msg.reasoning) {
                html += `<details class="reasoning"><summary>Reasoning</summary><div>${escapeHtml(msg.reasoning)}</div></details>`;
            }
            html += `<div class="msg-bubble assistant-bubble">${escapeHtml(msg.content) || '<span class="typing">▏</span>'}</div>`;
            div.innerHTML = html;
        }
        container.appendChild(div);
    }
    container.scrollTop = container.scrollHeight;
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
