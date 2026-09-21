// content.js — Content script that runs inside the chat.z.ai tab.

// ---- Add a visible badge + control panel ----
(function addControlPanel() {
  // Remove existing.
  var existing = document.getElementById('lagestroemia-panel');
  if (existing) existing.remove();

  // Create the panel container.
  var panel = document.createElement('div');
  panel.id = 'lagestroemia-panel';
  panel.style.cssText = [
    'position:fixed',
    'bottom:12px',
    'right:12px',
    'z-index:9999999',
    'background:#1a1a2e',
    'color:white',
    'padding:0',
    'border-radius:12px',
    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
    'font-size:12px',
    'box-shadow:0 4px 20px rgba(0,0,0,0.5)',
    'width:340px',
    'max-height:500px',
    'overflow-y:auto',
    'user-select:none',
  ].join(';');

  // Header.
  var header = document.createElement('div');
  header.style.cssText = 'background:#7C4DFF;padding:8px 12px;border-radius:12px 12px 0 0;font-weight:600;display:flex;align-items:center;gap:8px;cursor:pointer;';
  header.innerHTML = '<span>🌺 Lagestroemia <span id="lz-version" style="font-size:10px;opacity:0.7">v0.6.2</span></span><span id="lz-status-dot" style="margin-left:auto;width:8px;height:8px;border-radius:50%;background:#e74c3c;"></span><span id="lz-close-btn" style="margin-left:8px;cursor:pointer;font-size:16px;line-height:1;">×</span>';
  panel.appendChild(header);

  // Body.
  var body = document.createElement('div');
  body.id = 'lz-panel-body';
  body.style.cssText = 'padding:12px;display:flex;flex-direction:column;gap:8px;';
  panel.appendChild(body);

  // Status line.
  var statusLine = document.createElement('div');
  statusLine.id = 'lz-status-line';
  statusLine.style.cssText = 'color:#888;font-size:11px;';
  statusLine.textContent = 'Checking...';
  body.appendChild(statusLine);

  // Divider.
  body.appendChild(makeDivider());

  // Section: Chats
  body.appendChild(makeLabel('📋 Chats'));
  var chatList = document.createElement('div');
  chatList.id = 'lz-chat-list';
  chatList.style.cssText = 'color:#aaa;font-size:11px;max-height:150px;overflow-y:auto;';
  chatList.textContent = 'Not loaded yet';
  body.appendChild(chatList);

  // Buttons row.
  var btnRow1 = document.createElement('div');
  btnRow1.style.cssText = 'display:flex;gap:6px;';
  btnRow1.appendChild(makeButton('Refresh chats', '#3498db', function() {
    log('Refresh chats clicked');
    window.lzRefreshChatList();
  }));
  btnRow1.appendChild(makeButton('Open new chat', '#27ae60', function() {
    log('Open new chat clicked');
    window.lzOpenNewChat();
  }));
  body.appendChild(btnRow1);

  body.appendChild(makeDivider());

  // Section: Current chat
  body.appendChild(makeLabel('💬 Current chat'));
  var currentChatInfo = document.createElement('div');
  currentChatInfo.id = 'lz-current-chat';
  currentChatInfo.style.cssText = 'color:#aaa;font-size:11px;';
  currentChatInfo.textContent = 'No chat selected';
  body.appendChild(currentChatInfo);

  body.appendChild(makeButton('Read current chat', '#e67e22', function() {
    log('Read current chat clicked');
    window.lzReadCurrentChat();
  }));

  body.appendChild(makeDivider());

  // Section: Model
  body.appendChild(makeLabel('🤖 Model'));
  var modelInfo = document.createElement('div');
  modelInfo.id = 'lz-model-info';
  modelInfo.style.cssText = 'color:#aaa;font-size:11px;';
  modelInfo.textContent = 'Not detected';
  body.appendChild(modelInfo);

  var modelRow = document.createElement('div');
  modelRow.style.cssText = 'display:flex;gap:6px;';
  modelRow.appendChild(makeButton('Detect model', '#3498db', function() {
    log('Detecting model...');
    var current = window.lzGetCurrentModel();
    log('Current model: ' + current);
    var info = document.getElementById('lz-model-info');
    if (info) info.textContent = 'Current: ' + current;
  }));
  modelRow.appendChild(makeButton('List models', '#27ae60', function() {
    log('Listing available models...');
    // Open the dropdown to populate the model items.
    var btn = document.querySelector('[id^="model-selector-"][id$="-button"]');
    if (btn) {
      btn.click();
      setTimeout(function() {
        var models = window.lzGetAvailableModels();
        log('Found ' + models.length + ' models:');
        for (var i = 0; i < models.length; i++) {
          log('  ' + models[i].id + ' (' + models[i].name + ')' + (models[i].selected ? ' ← selected' : ''));
        }
        // Close the dropdown.
        var modal = document.querySelector('.modal.fixed');
        if (modal) modal.click();
      }, 500);
    } else {
      log('❌ Model selector button not found');
    }
  }));
  body.appendChild(modelRow);

  // Quick model switch buttons.
  var quickModelRow = document.createElement('div');
  quickModelRow.style.cssText = 'display:flex;gap:4px;flex-wrap:wrap;';
  var quickModels = ['x-preview-l', 'glm-5.3', 'glm-5.2', 'glm-4.7'];
  for (var qm = 0; qm < quickModels.length; qm++) {
    (function(modelId) {
      var btn = document.createElement('button');
      btn.textContent = modelId;
      btn.style.cssText = 'padding:3px 6px;border:1px solid #444;border-radius:4px;background:#222;color:#ccc;font-size:10px;cursor:pointer;font-family:inherit;';
      btn.onclick = function() {
        window.lzSetModel(modelId);
      };
      quickModelRow.appendChild(btn);
    })(quickModels[qm]);
  }
  body.appendChild(quickModelRow);

  body.appendChild(makeDivider());

  // Section: Mode
  body.appendChild(makeLabel('🔧 Mode'));
  var modeRow = document.createElement('div');
  modeRow.style.cssText = 'display:flex;gap:6px;';
  modeRow.appendChild(makeButton('Chat mode', '#3498db', function() {
    log('Switching to chat mode...');
    window.lzSetMode('chat');
  }));
  modeRow.appendChild(makeButton('Agent mode', '#e74c3c', function() {
    log('Switching to agent mode...');
    window.lzSetMode('agent');
  }));
  body.appendChild(modeRow);

  body.appendChild(makeDivider());

  // Section: Test
  body.appendChild(makeLabel('🧪 Test'));
  body.appendChild(makeButton('Send test message', '#9b59b6', function() {
    log('Test send clicked');
    window.lzSendTestMessage();
  }));

  body.appendChild(makeDivider());

  // Log
  body.appendChild(makeLabel('📜 Log'));
  var logBox = document.createElement('div');
  logBox.id = 'lz-log';
  logBox.style.cssText = 'background:#0d0d1a;color:#0f0;font-family:monospace;font-size:10px;padding:6px;border-radius:4px;max-height:120px;overflow-y:auto;line-height:1.4;';
  logBox.textContent = 'Ready.';
  body.appendChild(logBox);

  // Toggle body on header click. Close button hides the entire panel.
  var expanded = true;
  var minimized = false;
  header.onclick = function(e) {
    // Don't toggle if the close button was clicked.
    if (e.target.id === 'lz-close-btn') return;
    minimized = !minimized;
    body.style.display = minimized ? 'none' : 'flex';
    panel.style.borderRadius = minimized ? '20px' : '12px';
  };

  // Close button — removes the panel entirely (reload page to bring back).
  var closeBtn = header.querySelector('#lz-close-btn');
  closeBtn.onclick = function(e) {
    e.stopPropagation();
    panel.remove();
  };

  // Wait for body.
  if (document.body) {
    document.body.appendChild(panel);
  } else {
    document.addEventListener('DOMContentLoaded', function() {
      document.body.appendChild(panel);
    });
  }

  console.log('[content] 🌺 Lagestroemia control panel added');

  // ---- Helper functions for the panel ----

  function makeDivider() {
    var d = document.createElement('hr');
    d.style.cssText = 'border:none;border-top:1px solid #333;margin:4px 0;';
    return d;
  }

  function makeLabel(text) {
    var l = document.createElement('div');
    l.style.cssText = 'font-weight:600;font-size:11px;color:#ccc;';
    l.textContent = text;
    return l;
  }

  function makeButton(text, color, onClick) {
    var b = document.createElement('button');
    b.textContent = text;
    b.style.cssText = 'flex:1;padding:6px 8px;border:none;border-radius:6px;background:' + color + ';color:white;font-size:11px;cursor:pointer;font-family:inherit;';
    b.onmouseover = function() { b.style.opacity = '0.85'; };
    b.onmouseout = function() { b.style.opacity = '1'; };
    b.onclick = onClick;
    return b;
  }

  window.lzLog = function(msg) {
    var box = document.getElementById('lz-log');
    if (!box) return;
    var time = new Date().toLocaleTimeString();
    var line = document.createElement('div');
    line.textContent = time + ' ' + msg;
    box.appendChild(line);
    box.scrollTop = box.scrollHeight;
    while (box.children.length > 50) box.removeChild(box.firstChild);
  };

  function log(msg) {
    console.log(msg);
    window.lzLog(msg.replace('[content] ', ''));
  }

  // ---- Chat list: read from chat.z.ai's API ----
  window.lzRefreshChatList = function refreshChatList() {
    log('Refreshing chat list...');
    var chatListEl = document.getElementById('lz-chat-list');
    if (chatListEl) chatListEl.innerHTML = '<div style="color:#888">Loading...</div>';

    // Use chat.z.ai's API to get the chat list (same-origin, no CORS).
    getGuestToken().then(function(token) {
      return fetch('https://chat.z.ai/api/v1/chats/', {
        headers: {
          'Authorization': 'Bearer ' + token,
          'X-FE-Version': FE_VERSION,
        },
        credentials: 'include',
      });
    }).then(function(r) { return r.json(); }).then(function(data) {
      var chats = [];
      if (Array.isArray(data)) {
        chats = data;
      } else if (data.data && Array.isArray(data.data)) {
        chats = data.data;
      }

      log('API returned ' + chats.length + ' chats');

      if (chatListEl) {
        if (chats.length === 0) {
          chatListEl.innerHTML = '<div style="color:#888">No chats found.</div>';
        } else {
          chatListEl.innerHTML = '';
          for (var i = 0; i < Math.min(chats.length, 20); i++) {
            var chat = chats[i];
            var title = chat.title || chat.name || 'Untitled';
            var model = chat.model || 'unknown';
            var chatId = chat.id || '';
            var updated = chat.updated_at ? new Date(chat.updated_at * 1000).toLocaleString() : '';

            var div = document.createElement('div');
            div.style.cssText = 'padding:4px 0;border-bottom:1px solid #222;cursor:pointer;';
            div.innerHTML = '<div style="color:#fff">' + escapeHtml(title.substring(0, 40)) + '</div>' +
                            '<div style="color:#666;font-size:10px">' + escapeHtml(model) + ' · ' + updated + '</div>';
            div.onclick = (function(id) {
              return function() {
                window.location.href = 'https://chat.z.ai/c/' + id;
              };
            })(chatId);
            chatListEl.appendChild(div);
          }
        }
      }
    }).catch(function(err) {
      log('❌ Chat list API error: ' + err.message);
      // Fallback: try DOM.
      var links = document.querySelectorAll('a[href*="/c/"]');
      log('DOM fallback: found ' + links.length + ' chat links');
      if (chatListEl) {
        if (links.length === 0) {
          chatListEl.innerHTML = '<div style="color:#888">No chats found.</div>';
        } else {
          chatListEl.innerHTML = '';
          for (var j = 0; j < links.length; j++) {
            var href = links[j].getAttribute('href') || '';
            var title = links[j].textContent.trim().substring(0, 40);
            var div = document.createElement('div');
            div.style.cssText = 'padding:4px 0;border-bottom:1px solid #222;';
            div.innerHTML = '<div style="color:#fff">' + escapeHtml(title) + '</div>';
            chatListEl.appendChild(div);
          }
        }
      }
    });
  };

  // ---- Open new chat ----
  window.lzOpenNewChat = function openNewChat() {
    log('Opening new chat...');
    // Click chat.z.ai's own "new chat" button in the sidebar.
    var btn = document.getElementById('sidebar-new-chat-button');
    if (btn) {
      log('Found sidebar-new-chat-button, clicking...');
      btn.click();
      log('Clicked new chat button');
    } else {
      // Fallback: navigate to root.
      log('sidebar-new-chat-button not found, navigating to /');
      window.location.href = 'https://chat.z.ai/';
    }
  };

  // ---- Model detection + switching ----
  // The model selector button has id "model-selector-<model>_button"
  // (e.g. model-selector-glm-5_2-button). It opens a modal dropdown
  // with buttons[aria-label="model-item"], each having data-value="<model-id>"
  // and data-selected="true" or "false".

  window.lzGetCurrentModel = function getCurrentModel() {
    // Method 1: find the model selector button by ID pattern.
    var btn = document.querySelector('[id^="model-selector-"][id$="-button"]');
    if (btn) {
      // The text content is the model display name.
      var text = btn.textContent.trim();
      // Extract just the model name (before the dropdown arrow).
      var match = text.match(/^(GLM-[\d.]+(?:v)?(?:-Flash)?(?:-Turbo)?|Z1-\w+|deep-research|zero)/i);
      if (match) return match[1];
      return text;
    }

    // Method 2: find the selected model in the dropdown.
    var selected = document.querySelector('button[aria-label="model-item"][data-selected="true"]');
    if (selected) {
      return selected.getAttribute('data-value') || 'unknown';
    }

    return 'unknown';
  };

  window.lzGetAvailableModels = function getAvailableModels() {
    var models = [];
    var items = document.querySelectorAll('button[aria-label="model-item"]');
    for (var i = 0; i < items.length; i++) {
      var value = items[i].getAttribute('data-value') || '';
      var selected = items[i].getAttribute('data-selected') === 'true';
      // Get the display name from the inner text.
      var nameEl = items[i].querySelector('.line-clamp-1 > div > div');
      var name = nameEl ? nameEl.textContent.trim() : value;
      // Get the description.
      var descEl = items[i].querySelector('.text-xs.opacity-60');
      var desc = descEl ? descEl.textContent.trim() : '';
      if (value) {
        models.push({ id: value, name: name, description: desc, selected: selected });
      }
    }
    return models;
  };

  window.lzSetModel = function setModel(modelId) {
    log('Switching model to: ' + modelId);

    // Step 1: click the model selector button to open the dropdown.
    var selectorBtn = document.querySelector('[id^="model-selector-"][id$="-button"]');
    if (!selectorBtn) {
      log('❌ Model selector button not found');
      return false;
    }
    selectorBtn.click();
    log('Opened model selector dropdown');

    // Step 2: wait for the dropdown to render, then click the target model.
    setTimeout(function() {
      var items = document.querySelectorAll('button[aria-label="model-item"]');
      log('Found ' + items.length + ' model items in dropdown');

      for (var i = 0; i < items.length; i++) {
        var value = items[i].getAttribute('data-value') || '';
        if (value === modelId) {
          items[i].click();
          log('✅ Clicked model: ' + modelId);
          return;
        }
      }
      log('❌ Model "' + modelId + '" not found in dropdown');
      log('Available: ' + Array.from(items).map(function(b) { return b.getAttribute('data-value'); }).join(', '));

      // Close the dropdown by clicking outside.
      var modal = document.querySelector('.modal.fixed');
      if (modal) {
        modal.click();
        log('Closed dropdown (model not found)');
      }
    }, 500);

    return true;
  };

  // ---- Read current chat ----
  window.lzReadCurrentChat = function readCurrentChat() {
    log('Reading current chat...');
    var infoEl = document.getElementById('lz-current-chat');
    if (infoEl) infoEl.innerHTML = '<div style="color:#888">Reading...</div>';

    var url = window.location.href;
    var chatId = '';
    var match = url.match(/\/c\/([a-f0-9-]+)/);
    if (match) chatId = match[1];

    // Read messages from the DOM using chat.z.ai's actual CSS classes.
    var messages = [];
    var msgContainers = document.querySelectorAll('.chat-user, .chat-assistant');
    log('Found ' + msgContainers.length + ' message containers');

    for (var i = 0; i < msgContainers.length; i++) {
      var el = msgContainers[i];
      var isUser = el.classList.contains('chat-user');
      var role = isUser ? 'user' : 'assistant';
      var pElements = el.querySelectorAll('p');
      var text = '';
      if (pElements.length > 0) {
        for (var p = 0; p < pElements.length; p++) {
          text += pElements[p].textContent.trim() + '\n';
        }
      } else {
        text = el.textContent.trim();
      }
      text = text.trim().substring(0, 300);
      if (text.length > 0) {
        messages.push({ role: role, text: text });
      }
    }

    // Detect current mode (chat vs agent).
    var mode = lzGetMode();

    // Get the model from the page.
    var model = 'Unknown';
    var allButtons = document.querySelectorAll('button');
    for (var b = 0; b < allButtons.length; b++) {
      var btnText = allButtons[b].textContent.trim();
      if (btnText.match(/GLM-|glm-|Z1-|deep-research|zero/i) && btnText.length < 50) {
        model = btnText;
        break;
      }
    }

    var title = document.title || 'Unknown';
    var info = 'URL: ' + url + '\n' +
               'Chat ID: ' + (chatId || 'none') + '\n' +
               'Title: ' + title + '\n' +
               'Mode: ' + mode + '\n' +
               'Model: ' + model + '\n' +
               'Messages: ' + messages.length;

    if (messages.length > 0) {
      info += '\n\n--- Messages ---';
      for (var m = 0; m < Math.min(messages.length, 10); m++) {
        info += '\n[' + messages[m].role + '] ' + messages[m].text.substring(0, 100);
      }
    }

    log('Read ' + messages.length + ' messages, mode: ' + mode + ', model: ' + model);

    if (infoEl) {
      infoEl.innerHTML = '<pre style="white-space:pre-wrap;color:#ccc;font-size:10px;">' + escapeHtml(info) + '</pre>';
    }
  };

  // ---- Mode detection: Chat vs Agent ----
  // The sidebar has a toggle with two buttons inside a container with
  // class "gap-1 p-1 mb-5". The first button is Chat mode, the second
  // is Agent mode. Each has data-active="true" or "false".
  window.lzGetMode = function getMode() {
    var container = document.querySelector('.gap-1.p-1.mb-5');
    if (!container) return 'unknown';
    var buttons = container.querySelectorAll('button[data-active]');
    if (buttons.length < 2) return 'unknown';
    if (buttons[0].getAttribute('data-active') === 'true') return 'chat';
    if (buttons[1].getAttribute('data-active') === 'true') return 'agent';
    return 'unknown';
  };

  // ---- Switch mode: Chat or Agent ----
  window.lzSetMode = function setMode(mode) {
    var container = document.querySelector('.gap-1.p-1.mb-5');
    if (!container) {
      log('❌ Mode toggle container not found');
      return false;
    }
    var buttons = container.querySelectorAll('button[data-active]');
    if (buttons.length < 2) {
      log('❌ Mode toggle buttons not found');
      return false;
    }

    var currentMode = lzGetMode();
    if (currentMode === mode) {
      log('Already in ' + mode + ' mode');
      return true;
    }

    // Click the appropriate button.
    // Button 0 = chat, Button 1 = agent.
    var targetBtn = (mode === 'chat') ? buttons[0] : buttons[1];
    targetBtn.click();
    log('Switched to ' + mode + ' mode');
    return true;
  };

  // ---- Send test message ----
  // Types into chat.z.ai's #chat-input and clicks #send-message-button.
  // The response appears in the DOM. A MutationObserver streams it back.
  window.lzSendTestMessage = function sendTestMessage() {
    var testMsg = 'Hello! This is a test from Lagestroemia.';
    window.lzSendMessage(testMsg);
  };

  // ---- Core: send a message via chat.z.ai's native UI ----
  window.lzSendMessage = function sendMessage(text, requestId) {
    requestId = requestId || ('msg-' + Date.now());
    log('Sending via native UI: "' + text.substring(0, 40) + '" (id: ' + requestId + ')');

    var textarea = document.getElementById('chat-input');
    if (!textarea) {
      log('❌ #chat-input not found');
      chrome.runtime.sendMessage({ type: 'chatError', requestId: requestId, error: '#chat-input not found' }).catch(function() {});
      return;
    }

    // Focus the textarea first.
    textarea.focus();

    // Svelte uses a custom input handler. We need to:
    // 1. Set the value using the native setter (so the DOM updates)
    // 2. Dispatch an 'input' event that Svelte's on:input handler catches
    // 3. Also try keyboard simulation as a fallback
    var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    nativeInputValueSetter.call(textarea, text);

    // Dispatch input event for Svelte.
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
    // Also try 'change' event.
    textarea.dispatchEvent(new Event('change', { bubbles: true }));

    log('Typed into #chat-input (value: "' + textarea.value.substring(0, 30) + '")');

    // Wait for Svelte to register the change, then click send.
    setTimeout(function() {
      var sendBtn = document.getElementById('send-message-button');
      if (sendBtn) {
        // Check if the button is still disabled (Svelte hasn't registered
        // the input yet). If so, try a different approach.
        if (sendBtn.disabled) {
          log('Send button is disabled — trying keyboard Enter...');
          // Simulate pressing Enter in the textarea.
          textarea.dispatchEvent(new KeyboardEvent('keydown', {
            key: 'Enter',
            code: 'Enter',
            keyCode: 13,
            which: 13,
            bubbles: true,
            cancelable: true,
          }));
          textarea.dispatchEvent(new KeyboardEvent('keypress', {
            key: 'Enter',
            code: 'Enter',
            keyCode: 13,
            which: 13,
            bubbles: true,
            cancelable: true,
          }));
          textarea.dispatchEvent(new KeyboardEvent('keyup', {
            key: 'Enter',
            code: 'Enter',
            keyCode: 13,
            which: 13,
            bubbles: true,
            cancelable: true,
          }));
          log('Sent Enter keypress to textarea');
        } else {
          // Button is enabled — click it.
          sendBtn.click();
          log('Clicked #send-message-button');
        }
      } else {
        // Try form submit.
        var form = textarea.closest('form');
        if (form) {
          form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
          log('Submitted form');
        } else {
          log('❌ No send button or form found');
          chrome.runtime.sendMessage({ type: 'chatError', requestId: requestId, error: 'No send button found' }).catch(function() {});
          return;
        }
      }

      // Start watching for the response.
      watchForResponse(requestId);
    }, 1000);
  };

  // ---- HTTP polling: poll localhost:8081 for pending requests ----
  // This bypasses native messaging stdout entirely. The HTTP server
  // (native_host.py) puts chat requests in a pending list. We poll
  // GET /_pending every 500ms. When we get a request, we process it
  // (type into chat.z.ai, watch DOM) and POST the response chunks
  // back to POST /_response.
  window.lzStartPolling = function startPolling() {
    if (window._lzPolling) return;
    window._lzPolling = true;
    log('Starting HTTP polling for pending requests...');

    setInterval(function() {
      fetch('http://127.0.0.1:8081/_pending')
        .then(function(r) { return r.json(); })
        .then(function(req) {
          if (req.type === 'none' || !req.type) return;

          log('Received pending request: ' + req.type + ' (id: ' + req.requestId + ')');

          if (req.type === 'sendChat') {
            // Extract the user message text.
            var userMessage = req.messages[req.messages.length - 1];
            var text = userMessage.content || '';
            if (typeof text !== 'string') {
              text = '';
              for (var p = 0; p < userMessage.content.length; p++) {
                if (userMessage.content[p].type === 'text') {
                  text += userMessage.content[p].text;
                }
              }
            }

            // Send the message via native UI + watch for response.
            // The watchForResponse function needs to POST chunks to
            // /_response instead of using chrome.runtime.sendMessage.
            window.lzSendMessageHTTP(text, req.requestId);
          }
        })
        .catch(function(err) {
          // Silent — server might be temporarily unavailable.
        });
    }, 500);

    log('Polling started (every 500ms)');
  };

  // ---- Send message via native UI, stream response via HTTP ----
  window.lzSendMessageHTTP = function sendMessageHTTP(text, requestId) {
    log('Sending via native UI: "' + text.substring(0, 40) + '" (id: ' + requestId + ')');

    var textarea = document.getElementById('chat-input');
    if (!textarea) {
      log('#chat-input not found');
      postResponse(requestId, 'error', { error: '#chat-input not found' });
      return;
    }

    textarea.focus();
    var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    nativeInputValueSetter.call(textarea, text);
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
    textarea.dispatchEvent(new Event('change', { bubbles: true }));
    log('Typed into #chat-input');

    setTimeout(function() {
      var sendBtn = document.getElementById('send-message-button');
      if (sendBtn) {
        if (sendBtn.disabled) {
          log('Send button disabled — trying Enter...');
          textarea.dispatchEvent(new KeyboardEvent('keydown', {
            key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
            bubbles: true, cancelable: true,
          }));
          log('Sent Enter keypress');
        } else {
          sendBtn.click();
          log('Clicked #send-message-button');
        }
      } else {
        var form = textarea.closest('form');
        if (form) {
          form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
          log('Submitted form');
        } else {
          postResponse(requestId, 'error', { error: 'No send button found' });
          return;
        }
      }

      // Watch for response and stream via HTTP.
      watchForResponseHTTP(requestId);
    }, 1000);
  };

  // ---- Post a response chunk to the HTTP server ----
  function postResponse(requestId, type, data) {
    var body = JSON.stringify(Object.assign({ requestId: requestId, type: type }, data));
    fetch('http://127.0.0.1:8081/_response', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: body,
    }).catch(function() {});
  }

  // ---- Watch for response and stream via HTTP ----
  function watchForResponseHTTP(requestId) {
    log('Watching for response (HTTP mode, id: ' + requestId + ')');

    var lastLength = 0;
    var lastContent = '';
    var stableCount = 0;
    var prevCount = document.querySelectorAll('.chat-assistant').length;
    log('Existing .chat-assistant count: ' + prevCount);

    // Wait for a NEW .chat-assistant to appear, then track its content
    // growth. We need to distinguish between:
    // - A placeholder/spinner (whitespace, no real text)
    // - The actual streaming response
    // We only start counting "stable" after we've seen real content
    // (at least 5 non-whitespace characters).

    var pollInterval = setInterval(function() {
      var allAssistant = document.querySelectorAll('.chat-assistant');
      if (allAssistant.length > prevCount) {
        var latest = allAssistant[allAssistant.length - 1];
        var currentContent = '';

        // Read ONLY the response text, excluding the "Thinking" section.
        // Structure inside .chat-assistant:
        //   .thinking-chain-container (reasoning - SKIP this)
        //   p.svelte-4sys19 (actual response text - READ this)
        var allP = latest.querySelectorAll('p');
        for (var i = 0; i < allP.length; i++) {
          var parent = allP[i].parentElement;
          var isThinking = false;
          while (parent && parent !== latest) {
            if (parent.classList && parent.classList.contains('thinking-chain-container')) {
              isThinking = true;
              break;
            }
            parent = parent.parentElement;
          }
          if (!isThinking) {
            currentContent += allP[i].textContent;
          }
        }

        // Fallback: try .markdown-prose outside thinking container.
        if (currentContent.trim().length === 0) {
          var proseElements = latest.querySelectorAll('.markdown-prose');
          for (var j = 0; j < proseElements.length; j++) {
            var p2 = proseElements[j].parentElement;
            var isThinking2 = false;
            while (p2 && p2 !== latest) {
              if (p2.classList && p2.classList.contains('thinking-chain-container')) {
                isThinking2 = true;
                break;
              }
              p2 = p2.parentElement;
            }
            if (!isThinking2) {
              currentContent += proseElements[j].textContent;
            }
          }
        }

        // Strip "Thinking..." prefix.
        currentContent = currentContent.replace(/^Thinking\.\.\.\s*/g, '');

        // Strip whitespace for comparison — chat.z.ai renders
        // loading spinners as whitespace/punctuation.
        var trimmedContent = currentContent.trim();
        var trimmedLast = lastContent.trim();

        if (trimmedContent.length > trimmedLast.length) {
          // New real text arrived — send the delta.
          var delta = currentContent.substring(lastLength);
          lastLength = currentContent.length;
          lastContent = currentContent;
          stableCount = 0;

          // Only send if the delta has non-whitespace content.
          if (delta.trim().length > 0) {
            postResponse(requestId, 'streamChunk', {
              chunk: { content: delta, reasoning: '' },
            });
            log('chunk: "' + delta.trim().substring(0, 40) + '" (total: ' + trimmedContent.length + ' chars)');
          }
        } else if (trimmedContent.length === trimmedLast.length && trimmedContent.length > 5) {
          // Content is stable AND has real text (>5 non-whitespace chars).
          // Start counting towards completion.
          stableCount++;
          if (stableCount >= 8) {
            // 8 consecutive checks (≈4s) with no change = done.
            log('Response complete: ' + trimmedContent.length + ' chars');
            postResponse(requestId, 'streamEnd', {});
            clearInterval(pollInterval);
            return;
          }
        } else if (trimmedContent.length === 0 && lastLength === 0) {
          // Still waiting for the response to start rendering.
          // Don't count this as "stable".
        }
      }
    }, 500);

    // Timeout after 120 seconds.
    setTimeout(function() {
      if (lastLength === 0) {
        log('Timeout waiting for response');
        postResponse(requestId, 'error', { error: 'Timeout waiting for response' });
      } else {
        // We got some content but the stream didn't end cleanly.
        // Send streamEnd anyway so the HTTP client gets a response.
        log('Timeout with partial response (' + lastLength + ' chars) — sending streamEnd');
        postResponse(requestId, 'streamEnd', {});
      }
      clearInterval(pollInterval);
    }, 120000);
  }
  // Watches the chat area for new .chat-assistant elements. When one
  // appears, extracts the text from <p> elements and streams chunks
  // back to the background script. When the assistant message stops
  // growing (streaming complete), sends chatComplete.
  function watchForResponse(requestId) {
    log('Watching for response (requestId: ' + requestId + ')');

    // Observe the entire body — chat.z.ai is a Svelte SPA that
    // renders messages dynamically. We can't predict the exact
    // container, so we watch everything and filter for .chat-assistant.
    var chatArea = document.body;

    var lastContent = '';
    var lastLength = 0;
    var stableCount = 0;
    var observer = null;
    var timeout = null;
    var foundResponse = false;

    // Count existing .chat-assistant elements before sending.
    var existingAssistant = document.querySelectorAll('.chat-assistant');
    var prevCount = existingAssistant.length;
    log('Existing .chat-assistant count: ' + prevCount);

    observer = new MutationObserver(function() {
      // Check if a new .chat-assistant appeared.
      var allAssistant = document.querySelectorAll('.chat-assistant');
      if (allAssistant.length > prevCount) {
        foundResponse = true;
        // New assistant message found! Get the latest one.
        var latest = allAssistant[allAssistant.length - 1];

        // Extract text from all <p> elements inside the assistant message.
        var pElements = latest.querySelectorAll('p');
        var currentContent = '';
        if (pElements.length > 0) {
          for (var i = 0; i < pElements.length; i++) {
            currentContent += pElements[i].textContent;
          }
        } else {
          // Fallback: get text content directly.
          currentContent = latest.textContent || '';
        }

        if (currentContent.length > lastLength) {
          // New text arrived — send the delta as a chunk.
          var delta = currentContent.substring(lastLength);
          lastLength = currentContent.length;
          lastContent = currentContent;
          stableCount = 0;

          // Send chunk to background (relays to native host + side panel).
          chrome.runtime.sendMessage({
            type: 'chatChunk',
            requestId: requestId,
            chunk: { content: delta, reasoning: '' },
          }).catch(function() {});

          log('chunk: "' + delta.substring(0, 40) + '" (total: ' + lastLength + ' chars)');
        } else if (currentContent.length === lastLength && lastLength > 0) {
          // Content stable — might be done streaming.
          stableCount++;
          if (stableCount >= 5) {
            // 5 consecutive checks (≈2.5s) with no change = stream complete.
            log('Response complete: ' + lastContent.length + ' chars');
            chrome.runtime.sendMessage({
              type: 'chatComplete',
              requestId: requestId,
            }).catch(function() {});
            if (observer) observer.disconnect();
            if (timeout) clearTimeout(timeout);
          }
        }
      } else if (foundResponse) {
        // Response was found before but now the count dropped back —
        // this shouldn't happen, but handle it.
      }
    });

    // Observe the entire body for changes.
    observer.observe(chatArea, {
      childList: true,
      subtree: true,
      characterData: true,
    });

    // Also poll every 500ms as a fallback (MutationObserver might miss
    // some Svelte updates).
    var pollInterval = setInterval(function() {
      var allAssistant = document.querySelectorAll('.chat-assistant');
      if (allAssistant.length > prevCount) {
        var latest = allAssistant[allAssistant.length - 1];
        var currentContent = '';

        // Read ONLY the response text, excluding the "Thinking" section.
        // Structure inside .chat-assistant:
        //   .thinking-chain-container (reasoning - SKIP this)
        //   p.svelte-4sys19 (actual response text - READ this)
        var allP = latest.querySelectorAll('p');
        for (var i = 0; i < allP.length; i++) {
          var parent = allP[i].parentElement;
          var isThinking = false;
          while (parent && parent !== latest) {
            if (parent.classList && parent.classList.contains('thinking-chain-container')) {
              isThinking = true;
              break;
            }
            parent = parent.parentElement;
          }
          if (!isThinking) {
            currentContent += allP[i].textContent;
          }
        }

        // Fallback: try .markdown-prose outside thinking container.
        if (currentContent.trim().length === 0) {
          var proseElements = latest.querySelectorAll('.markdown-prose');
          for (var j = 0; j < proseElements.length; j++) {
            var p2 = proseElements[j].parentElement;
            var isThinking2 = false;
            while (p2 && p2 !== latest) {
              if (p2.classList && p2.classList.contains('thinking-chain-container')) {
                isThinking2 = true;
                break;
              }
              p2 = p2.parentElement;
            }
            if (!isThinking2) {
              currentContent += proseElements[j].textContent;
            }
          }
        }

        // Strip "Thinking..." prefix.
        currentContent = currentContent.replace(/^Thinking\.\.\.\s*/g, '');

        if (currentContent.length > lastLength) {
          var delta = currentContent.substring(lastLength);
          lastLength = currentContent.length;
          lastContent = currentContent;
          stableCount = 0;

          chrome.runtime.sendMessage({
            type: 'chatChunk',
            requestId: requestId,
            chunk: { content: delta, reasoning: '' },
          }).catch(function() {});

          log('poll chunk: "' + delta.substring(0, 40) + '" (total: ' + lastLength + ')');
        } else if (currentContent.length === lastLength && lastLength > 0) {
          stableCount++;
          if (stableCount >= 5) {
            log('Response complete (poll): ' + lastContent.length + ' chars');
            chrome.runtime.sendMessage({
              type: 'chatComplete',
              requestId: requestId,
            }).catch(function() {});
            if (observer) observer.disconnect();
            clearInterval(pollInterval);
            if (timeout) clearTimeout(timeout);
          }
        }
      }
    }, 500);

    // Timeout after 120 seconds.
    timeout = setTimeout(function() {
      log('Timeout waiting for response');
      chrome.runtime.sendMessage({
        type: 'chatError',
        requestId: requestId,
        error: 'Timeout waiting for response',
      }).catch(function() {});
      if (observer) observer.disconnect();
      clearInterval(pollInterval);
    }, 120000);
  }

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Auto-refresh on load + start polling.
  setTimeout(function() {
    window.lzRefreshChatList();
    window.lzReadCurrentChat();
    window.lzStartPolling();
  }, 2000);
})();

// ---- Native messaging status tracking ----
let nativeReady = false;

function updateBadge() {
  var dot = document.getElementById('lz-status-dot');
  var line = document.getElementById('lz-status-line');
  if (dot) {
    dot.style.background = nativeReady ? '#27ae60' : '#e74c3c';
  }
  if (line) {
    line.textContent = nativeReady ? 'Server on :8081 — connected' : 'No server — native host not connected';
  }
}

// ---- Constants ----

const SECRET_KEY = 'key-@@@@)))()((9))-xxxx&&&%%%%%';
const CHAT_COMPLETIONS_URL = 'https://chat.z.ai/api/v2/chat/completions';
const MODELS_URL = 'https://chat.z.ai/api/models';
const FE_VERSION = 'prod-fe-1.1.95';

// ---- Utility: UUID v4 ----
function uuid() {
  return crypto.randomUUID();
}

// ---- Signature computation (ported from chat.z.ai's JS bundle) ----
async function computeSignature(sortedPayload, promptText, timestamp) {
  // 1. base64-encode the UTF-8 bytes of the prompt.
  const encoder = new TextEncoder();
  const promptBytes = encoder.encode(promptText);
  const p = btoa(String.fromCharCode(...promptBytes));

  // 2. canonical string: sortedPayload | base64(prompt) | timestamp
  const h = sortedPayload + '|' + p + '|' + timestamp;

  // 3. 5-minute time window index
  const m = Math.floor(Number(timestamp) / 300000);

  // 4. derived key = HMAC_SHA256(SECRET_KEY, str(m))
  const keyBytes = encoder.encode(SECRET_KEY);
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const derivedBuf = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(String(m)));
  const derivedKey = Array.from(new Uint8Array(derivedBuf))
    .map(b => b.toString(16).padStart(2, '0')).join('');

  // 5. signature = HMAC_SHA256(derivedKey, canonicalString)
  const sigKey = encoder.encode(derivedKey);
  const sigCryptoKey = await crypto.subtle.importKey(
    'raw', sigKey, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sigBuf = await crypto.subtle.sign('HMAC', sigCryptoKey, encoder.encode(h));
  return Array.from(new Uint8Array(sigBuf))
    .map(b => b.toString(16).padStart(2, '0')).join('');
}

// ---- Build request metadata (sortedPayload + URL params) ----
function buildRequestMeta(userId, token) {
  const timestamp = String(Date.now());
  const requestId = uuid();
  const o = { timestamp, requestId, user_id: userId || '' };

  // sortedPayload: entries sorted by key, joined by ","
  const sortedPayload = Object.entries(o)
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([k, v]) => `${k},${v}`)
    .join(',');

  // URL params (browser fingerprint — values can be faked)
  const params = new URLSearchParams({
    ...o,
    version: '0.0.1',
    platform: 'web',
    token: token || '',
    user_agent: navigator.userAgent,
    language: navigator.language || 'en-US',
    languages: (navigator.languages || ['en-US']).join(','),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
    cookie_enabled: String(navigator.cookieEnabled),
    screen_width: String(screen.width),
    screen_height: String(screen.height),
    screen_resolution: `${screen.width}x${screen.height}`,
    viewport_height: String(window.innerHeight),
    viewport_width: String(window.innerWidth),
    viewport_size: `${window.innerWidth}x${window.innerHeight}`,
    color_depth: String(screen.colorDepth),
    pixel_ratio: String(window.devicePixelRatio),
    current_url: window.location.href,
    pathname: window.location.pathname,
    search: window.location.search,
    hash: window.location.hash,
    host: window.location.host,
    hostname: window.location.hostname,
    protocol: window.location.protocol,
    referrer: document.referrer,
    title: document.title,
    timezone_offset: String(new Date().getTimezoneOffset()),
    local_time: new Date().toISOString(),
    utc_time: new Date().toUTCString(),
    is_mobile: 'false',
    is_touch: String('ontouchstart' in window),
    max_touch_points: String(navigator.maxTouchPoints || 0),
    browser_name: 'Chrome',
    os_name: 'Unknown',
  });

  return { timestamp, requestId, sortedPayload, params };
}

// ---- Extract the guest token ----
// Tries cookie first, falls back to fetching from the API.
let cachedToken = null;
let cachedTokenTime = 0;

async function getGuestToken() {
  // Check cache (valid for 30 minutes).
  if (cachedToken && (Date.now() - cachedTokenTime) < 30 * 60 * 1000) {
    return cachedToken;
  }

  // Try cookie first (fastest).
  try {
    const match = document.cookie.match(/(?:^|;\s*)token=([^;]+)/);
    if (match && match[1]) {
      cachedToken = match[1];
      cachedTokenTime = Date.now();
      console.log('[content] Got token from cookie');
      return cachedToken;
    }
  } catch (e) {
    console.log('[content] Cookie access failed:', e);
  }

  // Fallback: fetch from the API (same-origin, no CORS issues).
  console.log('[content] No cookie token, fetching from API...');
  const resp = await fetch('https://chat.z.ai/api/v1/auths/', {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'X-FE-Version': FE_VERSION,
    },
    credentials: 'include',
  });
  if (!resp.ok) {
    throw new Error(`Guest token fetch failed: HTTP ${resp.status}`);
  }
  const data = await resp.json();
  if (!data.token) {
    throw new Error('No token in API response');
  }
  cachedToken = data.token;
  cachedTokenTime = Date.now();
  console.log('[content] Got token from API');
  return cachedToken;
}

// ---- Extract user ID from JWT ----
function getUserIdFromToken(token) {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.id || '';
  } catch {
    return '';
  }
}

// ---- Send a chat completion request (with auto-retry) ----
async function sendChatCompletion(messages, model, options = {}) {
  const token = await getGuestToken();
  if (!token) {
    throw new Error('Could not get guest token. Make sure you are signed in on chat.z.ai.');
  }
  const userId = getUserIdFromToken(token);
  const promptText = extractPromptText(messages);

  // Build request metadata + signature.
  const meta = buildRequestMeta(userId, token);
  const signature = await computeSignature(meta.sortedPayload, promptText, meta.timestamp);
  meta.params.set('signature_timestamp', meta.timestamp);

  // Build the request body (matching chat.z.ai's format).
  const body = {
    stream: true,
    model: model || 'glm-4.7',
    messages: messages,
    signature_prompt: promptText,
    params: {},
    extra: {},
    features: {
      image_generation: false,
      web_search: false,
      auto_web_search: false,
      preview_mode: true,
      flags: [],
      vlm_tools_enable: false,
      vlm_web_search_enable: false,
      vlm_website_mode: false,
      enable_thinking: options.thinking || false,
      reasoning_effort: options.thinking ? 'max' : 'low',
    },
    variables: {
      '{{USER_NAME}}': 'Guest',
      '{{USER_LOCATION}}': 'Unknown',
      '{{CURRENT_DATETIME}}': new Date().toISOString().substring(0, 19).replace('T', ' '),
      '{{CURRENT_DATE}}': new Date().toISOString().substring(0, 10),
      '{{CURRENT_TIME}}': new Date().toISOString().substring(11, 19),
      '{{CURRENT_WEEKDAY}}:': ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][new Date().getDay()],
      '{{CURRENT_TIMEZONE}}': Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
      '{{USER_LANGUAGE}}': navigator.language || 'en-US',
    },
    chat_id: options.chatId || uuid(),
    id: uuid(),
    current_user_message_id: uuid(),
    current_user_message_parent_id: null,
    background_tasks: { title_generation: true, tags_generation: true },
  };

  // If we have a captcha param, include it.
  if (options.captchaVerifyParam) {
    body.captcha_verify_param = options.captchaVerifyParam;
  }

  const url = `${CHAT_COMPLETIONS_URL}?${meta.params.toString()}`;
  console.log('[content] Sending chat request to', url);

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'X-FE-Version': FE_VERSION,
      'X-Signature': signature,
      'X-Region': 'overseas',
    },
    body: JSON.stringify(body),
    credentials: 'include',
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`HTTP ${resp.status}: ${text}`);
  }

  return resp;
}

// ---- Extract prompt text from messages ----
function extractPromptText(messages) {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'user') {
      const c = messages[i].content;
      if (typeof c === 'string') return c;
      if (Array.isArray(c)) {
        for (const part of c) {
          if (part.type === 'text') return part.text || '';
        }
      }
      return '';
    }
  }
  return '';
}

// ---- Parse SSE stream ----
async function* parseSSE(resp) {
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    // Split on double newlines (SSE event boundaries).
    while (true) {
      const idx = buffer.indexOf('\n\n');
      if (idx === -1) break;
      const event = buffer.substring(0, idx);
      buffer = buffer.substring(idx + 2);

      // Parse data: lines.
      const dataLines = [];
      for (const line of event.split('\n')) {
        if (line.startsWith('data:')) {
          dataLines.push(line.substring(5).trim());
        }
      }
      if (dataLines.length === 0) continue;
      const data = dataLines.join('\n');
      if (data === '[DONE]') return;
      yield JSON.parse(data);
    }
  }
}

// ---- Solve captcha using chat.z.ai's own SDK ----
async function solveCaptcha() {
  return new Promise((resolve, reject) => {
    // chat.z.ai loads the Aliyun captcha SDK lazily. We must NOT load
    // it ourselves — chat.z.ai's CSP blocks scripts from alicdn.com
    // when injected by an extension. Instead, we wait for chat.z.ai's
    // own copy to be available.
    //
    // The SDK is loaded when the user interacts with chat.z.ai (types
    // a message, clicks send). We try to trigger it by clicking the
    // input, then poll for window.initAliyunCaptcha.
    console.log('[content] solveCaptcha() called — looking for initAliyunCaptcha...');

    var attempts = 0;
    var maxAttempts = 120; // 120 * 500ms = 60s timeout

    function checkForCaptcha() {
      attempts++;
      console.log('[content] Checking for initAliyunCaptcha (attempt ' + attempts + ')...');

      if (window.initAliyunCaptcha) {
        console.log('[content] ✅ initAliyunCaptcha found!');
        doInitCaptcha(resolve, reject);
        return;
      }

      if (attempts < maxAttempts) {
        // Try to trigger chat.z.ai to load the SDK by interacting
        // with the page. chat.z.ai loads the SDK on first chat send
        // attempt.
        if (attempts === 1) {
          console.log('[content] Trying to trigger SDK load by clicking input...');
          // Click the textarea/input.
          var inputs = document.querySelectorAll('textarea, [contenteditable="true"]');
          for (var i = 0; i < inputs.length; i++) {
            inputs[i].click();
            inputs[i].focus();
          }
          // Also try clicking any "send" button.
          var sendBtns = document.querySelectorAll('button[type="submit"], button[class*="send"]');
          for (var s = 0; s < sendBtns.length; s++) {
            // Don't actually click send — just focus it.
            sendBtns[s].focus();
          }
        }

        // Every 10 attempts, try clicking the input again.
        if (attempts % 10 === 0) {
          console.log('[content] Still waiting for SDK... try clicking input again.');
          var inputs2 = document.querySelectorAll('textarea, [contenteditable="true"]');
          if (inputs2.length > 0) {
            inputs2[0].click();
          }
        }

        setTimeout(checkForCaptcha, 500);
      } else {
        reject(new Error('Captcha SDK not available after 60s. Please type a message in chat.z.ai first to trigger the SDK load, then retry.'));
      }
    }

    checkForCaptcha();
  });
}

function doInitCaptcha(resolve, reject) {
  if (!window.initAliyunCaptcha) {
    reject(new Error('initAliyunCaptcha not found'));
    return;
  }

  // Create a container for the captcha.
  let container = document.getElementById('lz-captcha-overlay');
  if (!container) {
    container = document.createElement('div');
    container.id = 'lz-captcha-overlay';
    container.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:999999;display:flex;align-items:center;justify-content:center;';
    const inner = document.createElement('div');
    inner.style.cssText = 'background:white;padding:24px;border-radius:12px;max-width:400px;';
    const title = document.createElement('div');
    title.textContent = 'Solve the captcha to continue';
    title.style.cssText = 'font-size:16px;font-weight:600;margin-bottom:16px;color:#333;';
    inner.appendChild(title);
    const captchaEl = document.createElement('div');
    captchaEl.id = 'lz-captcha-element';
    captchaEl.style.cssText = 'min-height:200px;';
    inner.appendChild(captchaEl);
    const btn = document.createElement('button');
    btn.id = 'lz-captcha-button';
    btn.style.cssText = 'position:absolute;left:-9999px;';
    inner.appendChild(btn);
    container.appendChild(inner);
    document.body.appendChild(container);
  }

  window.initAliyunCaptcha({
    SceneId: 'didk33e0',
    mode: 'embed',
    element: '#lz-captcha-element',
    button: '#lz-captcha-button',
    prefix: 'no8xfe',
    region: 'sgp',
    language: 'en',
    timeout: 60000,
    delayBeforeSuccess: false,
    success: function(v) {
      const param = (typeof v === 'string') ? v : JSON.stringify(v);
      // Remove the overlay.
      const overlay = document.getElementById('lz-captcha-overlay');
      if (overlay) overlay.remove();
      resolve(param || '');
    },
    fail: function(e) {
      const overlay = document.getElementById('lz-captcha-overlay');
      if (overlay) overlay.remove();
      reject(new Error(String(e || 'captcha fail')));
    },
    onError: function(e) {
      const overlay = document.getElementById('lz-captcha-overlay');
      if (overlay) overlay.remove();
      reject(new Error(String(e || 'captcha error')));
    }
  });
}

// ---- Auto-retry wrapper ----
const MAX_RETRIES = 5;
const RETRYABLE_ERRORS = ['server overload', 'rate limit', 'network', '502', '503', '504'];

async function sendChatWithRetry(messages, model, options, onChunk, onStatus) {
  let captchaParam = options.captchaVerifyParam || null;
  let lastError = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      if (onStatus) onStatus(attempt === 0 ? 'Sending…' : `Retry ${attempt}/${MAX_RETRIES}…`);

      const opts = { ...options };
      if (captchaParam) {
        opts.captchaVerifyParam = captchaParam;
      }

      const resp = await sendChatCompletion(messages, model, opts);

      // Check for inline SSE error.
      let streamError = null;
      let captchaRequired = false;

      for await (const chunk of parseSSE(resp)) {
        // Unwrap chat.z.ai's envelope. Error events have a different
        // structure: {data: {data: {done:true, error:{}}}} (no type field).
        // Content events have: {type:"chat:completion", data:{data:{choices:[]}}}
        let payload = chunk;
        if (chunk.type === 'chat:completion' && chunk.data) {
          if (chunk.data.data) {
            payload = chunk.data.data;
          } else {
            payload = chunk.data;
          }
        } else if (chunk.data && chunk.data.data) {
          // Error event: {data: {data: {done:true, error:{}}}}
          payload = chunk.data.data;
        }

        // Check for error FIRST (before extracting content).
        if (payload.error) {
          const err = payload.error;
          const errorCode = err.error_code || err.code;
          if (errorCode === 'FRONTEND_CAPTCHA_REQUIRED') {
            captchaRequired = true;
            streamError = new Error('Captcha required');
            break;
          }
          streamError = new Error(err.detail || err.message || 'Unknown error');
          break;
        }

        // Skip done-only events (no choices, no error).
        if (payload.done && !payload.choices) continue;

        // Extract content delta.
        if (payload.choices && payload.choices.length > 0) {
          const delta = payload.choices[0].delta;
          if (delta) {
            if (onChunk) onChunk({
              content: delta.content || '',
              reasoning: delta.reasoning_content || '',
            });
          }
        }
      }

      if (captchaRequired) {
        if (onStatus) onStatus('Captcha required — solving…');
        captchaParam = await solveCaptcha();
        if (onStatus) onStatus('Captcha solved — retrying…');
        continue; // retry with the captcha param
      }

      if (streamError) {
        // Check if retryable.
        const msg = streamError.message.toLowerCase();
        const isRetryable = RETRYABLE_ERRORS.some(e => msg.includes(e));
        if (isRetryable && attempt < MAX_RETRIES) {
          const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s, 8s, 16s
          if (onStatus) onStatus(`Server error — retrying in ${delay/1000}s…`);
          await new Promise(r => setTimeout(r, delay));
          continue;
        }
        throw streamError;
      }

      // Success!
      if (onStatus) onStatus('Done');
      return { ok: true };

    } catch (err) {
      lastError = err;
      const msg = err.message.toLowerCase();
      const isRetryable = RETRYABLE_ERRORS.some(e => msg.includes(e)) ||
                         msg.includes('fetch') || msg.includes('network');
      if (isRetryable && attempt < MAX_RETRIES) {
        const delay = Math.pow(2, attempt) * 1000;
        if (onStatus) onStatus(`Error — retrying in ${delay/1000}s…`);
        await new Promise(r => setTimeout(r, delay));
        continue;
      }
      throw err;
    }
  }

  throw lastError || new Error('Max retries exceeded');
}

// ---- Message handler ----
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[content] Message:', message.type);

  // Handle native host status updates.
  if (message.type === 'nativeStatus') {
    nativeReady = message.connected;
    console.log('[content] Native host:', message.connected ? 'CONNECTED' : 'DISCONNECTED');
    updateBadge();
    return false;
  }

  if (message.type === 'sendChat') {
    // Flash the badge to show we received the message.
    var badge = document.getElementById('lz-status-dot');
    if (badge) badge.style.background = '#e74c3c';
    console.log('[content] sendChat received! requestId:', message.requestId, 'model:', message.model);

    // Extract the user message text.
    var userMessage = message.messages[message.messages.length - 1];
    var text = userMessage.content || '';
    if (typeof text !== 'string') {
      text = '';
      for (var p = 0; p < userMessage.content.length; p++) {
        if (userMessage.content[p].type === 'text') {
          text += userMessage.content[p].text;
        }
      }
    }

    // Don't try to switch models — just use whatever is currently
    // selected on chat.z.ai. Guest users can't switch models anyway.
    // If a model is requested, log it but don't attempt to change it.
    if (message.model) {
      console.log('[content] Requested model:', message.model, '(using whatever is selected on the page)');
    }

    // Send the message via the native UI.
    window.lzSendMessage(text, message.requestId);

    sendResponse({ ok: true });
    return true;
  }

  if (message.type === 'solveCaptcha') {
    solveCaptcha()
      .then((param) => sendResponse({ ok: true, captchaVerifyParam: param }))
      .catch((err) => sendResponse({ ok: false, error: err.message }));
    return true;
  }

  if (message.type === 'getModels') {
    // Read models from chat.z.ai's DOM by opening the model selector
    // dropdown, reading the items, then closing it.
    console.log('[content] getModels — reading from DOM...');

    var selectorBtn = document.querySelector('[id^="model-selector-"][id$="-button"]');
    if (!selectorBtn) {
      console.log('[content] Model selector button not found');
      sendResponse({ ok: true, models: [] });
      return true;
    }

    // Click to open the dropdown.
    selectorBtn.click();

    setTimeout(function() {
      var items = document.querySelectorAll('button[aria-label="model-item"]');
      var models = [];
      for (var i = 0; i < items.length; i++) {
        var value = items[i].getAttribute('data-value') || '';
        if (value) models.push(value);
      }
      console.log('[content] Found ' + models.length + ' models in DOM: ' + models.join(', '));

      // Close the dropdown.
      var modal = document.querySelector('.modal.fixed');
      if (modal) modal.click();

      sendResponse({ ok: true, models: models });
    }, 500);
    return true;
  }
});
