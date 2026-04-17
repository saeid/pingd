const state = {
    token: localStorage.getItem('pingd_token'),
    username: localStorage.getItem('pingd_username'),
    currentTopic: null,
    sseAbort: null,
    liveEnabled: false,
};

// Elements
const loginView = document.getElementById('login-view');
const mainView = document.getElementById('main-view');
const loginForm = document.getElementById('login-form');
const loginError = document.getElementById('login-error');
const currentUser = document.getElementById('current-user');
const logoutBtn = document.getElementById('logout-btn');
const topicList = document.getElementById('topic-list');
const createTopicForm = document.getElementById('create-topic-form');
const emptyState = document.getElementById('empty-state');
const messagesView = document.getElementById('messages-view');
const messagesTopicName = document.getElementById('messages-topic-name');
const messagesVisibility = document.getElementById('messages-visibility');
const publishForm = document.getElementById('publish-form');
const messageList = document.getElementById('message-list');
const sseToggle = document.getElementById('sse-toggle');
const deleteTopicBtn = document.getElementById('delete-topic-btn');
const notificationSound = document.getElementById('notification-sound');

// API
async function api(method, path, body) {
    const headers = {};
    if (body) headers['Content-Type'] = 'application/json';
    if (state.token) headers['Authorization'] = `Bearer ${state.token}`;

    const opts = { method, headers };
    if (body) opts.body = JSON.stringify(body);

    const res = await fetch(path, opts);
    if (res.status === 204) return null;
    if (!res.ok) {
        const text = await res.text();
        throw new Error(`${res.status}: ${text}`);
    }
    return res.json();
}

// Auth
loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = document.getElementById('login-username').value;
    const password = document.getElementById('login-password').value;
    loginError.classList.add('hidden');

    try {
        const data = await api('POST', '/auth/login', { username, password });
        state.token = data.token;
        state.username = data.username;
        localStorage.setItem('pingd_token', data.token);
        localStorage.setItem('pingd_username', data.username);
        document.getElementById('login-username').value = '';
        document.getElementById('login-password').value = '';
        showDashboard();
    } catch {
        loginError.textContent = 'Invalid credentials';
        loginError.classList.remove('hidden');
    }
});

document.getElementById('skip-login').addEventListener('click', () => {
    showDashboard();
});

logoutBtn.addEventListener('click', async () => {
    if (state.token) {
        try { await api('DELETE', '/auth/logout'); } catch {}
    }
    state.token = null;
    state.username = null;
    localStorage.removeItem('pingd_token');
    localStorage.removeItem('pingd_username');
    disconnectSSE();
    showLogin();
});

function showLogin() {
    loginView.classList.remove('hidden');
    mainView.classList.add('hidden');
}

function showDashboard() {
    loginView.classList.add('hidden');
    mainView.classList.remove('hidden');
    currentUser.textContent = state.username || 'anonymous';
    logoutBtn.textContent = state.token ? 'sign out' : 'back';
    loadTopics();
}

// Topics
async function loadTopics() {
    try {
        const topics = await api('GET', '/topics');
        renderTopics(topics);
    } catch (err) {
        if (err.message.startsWith('401')) {
            showLogin();
        }
    }
}

function renderTopics(topics) {
    topicList.innerHTML = '';
    topics.forEach(topic => {
        const el = document.createElement('div');
        el.className = 'topic-item' + (state.currentTopic === topic.name ? ' active' : '');

        const nameEl = document.createElement('span');
        nameEl.className = 'topic-name';
        nameEl.textContent = topic.name;
        el.appendChild(nameEl);

        const badgeEl = document.createElement('span');
        badgeEl.className = `badge badge-${topic.visibility}`;
        badgeEl.textContent = topic.visibility;
        el.appendChild(badgeEl);

        el.addEventListener('click', () => selectTopic(topic));
        topicList.appendChild(el);
    });
}

createTopicForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = document.getElementById('topic-name').value;
    const visibility = document.getElementById('topic-visibility').value;

    try {
        await api('POST', '/topics', { name, visibility });
        document.getElementById('topic-name').value = '';
        loadTopics();
    } catch (err) {
        alert(err.message);
    }
});

deleteTopicBtn.addEventListener('click', async () => {
    if (!state.currentTopic) return;
    if (!confirm(`Delete topic "${state.currentTopic}"?`)) return;

    try {
        await api('DELETE', `/topics/${state.currentTopic}`);
        state.currentTopic = null;
        emptyState.classList.remove('hidden');
        messagesView.classList.add('hidden');
        disconnectSSE();
        loadTopics();
    } catch (err) {
        alert(err.message);
    }
});

// Messages
async function selectTopic(topic) {
    state.currentTopic = topic.name;
    emptyState.classList.add('hidden');
    messagesView.classList.remove('hidden');
    messagesTopicName.textContent = topic.name;
    messagesVisibility.textContent = topic.visibility;
    messagesVisibility.className = `badge badge-${topic.visibility}`;

    document.querySelectorAll('.topic-item').forEach(el => {
        const name = el.querySelector('.topic-name').textContent;
        el.classList.toggle('active', name === topic.name);
    });

    await loadMessages();
    if (state.liveEnabled) connectSSE();
}

async function loadMessages() {
    try {
        const messages = await api('GET', `/topics/${state.currentTopic}/messages`);
        renderMessages(messages);
    } catch (err) {
        messageList.innerHTML = `<div class="empty-state"><p>${err.message}</p></div>`;
    }
}

function renderMessages(messages) {
    messageList.innerHTML = '';
    if (messages.length === 0) {
        messageList.innerHTML = '<div class="empty-state"><p>No messages yet</p></div>';
        return;
    }
    messages.forEach(msg => appendMessage(msg, false));
}

function appendMessage(msg, isNew) {
    // remove "no messages" placeholder
    const placeholder = messageList.querySelector('.empty-state');
    if (placeholder) placeholder.remove();

    const el = document.createElement('div');
    el.className = 'message-item' + (isNew ? ' new' : '');

    const payload = msg.payload || msg;
    const time = msg.time ? new Date(msg.time).toLocaleTimeString() : new Date().toLocaleTimeString();

    if (payload.title) {
        const titleEl = document.createElement('div');
        titleEl.className = 'message-title';
        titleEl.textContent = payload.title;
        el.appendChild(titleEl);
    }

    const bodyEl = document.createElement('div');
    bodyEl.className = 'message-body';
    bodyEl.textContent = payload.body || '';
    el.appendChild(bodyEl);

    if (msg.tags?.length) {
        const tagsEl = document.createElement('div');
        tagsEl.className = 'message-tags';
        msg.tags.forEach(t => {
            const tag = document.createElement('span');
            tag.className = 'message-tag';
            tag.textContent = t;
            tagsEl.appendChild(tag);
        });
        el.appendChild(tagsEl);
    }

    const metaEl = document.createElement('div');
    metaEl.className = 'message-meta';
    metaEl.textContent = time;
    el.appendChild(metaEl);

    if (isNew) {
        messageList.prepend(el);
    } else {
        messageList.appendChild(el);
    }
}

publishForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const title = document.getElementById('msg-title').value || null;
    const body = document.getElementById('msg-body').value;

    try {
        await api('POST', `/topics/${state.currentTopic}/messages`, {
            priority: 3,
            payload: { title, subtitle: null, body }
        });
        document.getElementById('msg-title').value = '';
        document.getElementById('msg-body').value = '';
        if (!state.liveEnabled) await loadMessages();
    } catch (err) {
        alert(err.message);
    }
});

// SSE via fetch (supports auth headers)
sseToggle.addEventListener('click', () => {
    state.liveEnabled = !state.liveEnabled;
    sseToggle.classList.toggle('active', state.liveEnabled);
    if (state.liveEnabled && state.currentTopic) {
        connectSSE();
    } else {
        disconnectSSE();
    }
});

async function connectSSE() {
    disconnectSSE();
    if (!state.currentTopic) return;

    const abort = new AbortController();
    state.sseAbort = abort;

    const headers = {};
    if (state.token) headers['Authorization'] = `Bearer ${state.token}`;

    try {
        const res = await fetch(`/topics/${state.currentTopic}/stream`, {
            headers,
            signal: abort.signal,
        });

        if (!res.ok) {
            state.liveEnabled = false;
            sseToggle.classList.remove('active');
            return;
        }

        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const chunks = buffer.split('\n\n');
            buffer = chunks.pop();

            for (const chunk of chunks) {
                const line = chunk.trim();
                if (!line.startsWith('data: ')) continue;
                try {
                    const payload = JSON.parse(line.slice(6));
                    appendMessage({ payload, time: new Date().toISOString() }, true);

                    if (notificationSound) {
                        notificationSound.currentTime = 0;
                        notificationSound.play().catch(() => {});
                    }

                    if (Notification.permission === 'granted') {
                        new Notification(payload.title || state.currentTopic, {
                            body: payload.body,
                        });
                    }
                } catch {}
            }
        }
    } catch (err) {
        if (err.name !== 'AbortError') {
            state.liveEnabled = false;
            sseToggle.classList.remove('active');
        }
    }
}

function disconnectSSE() {
    if (state.sseAbort) {
        state.sseAbort.abort();
        state.sseAbort = null;
    }
}

// Request notification permission
if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
}

// Init
if (state.token) {
    showDashboard();
} else {
    showLogin();
}
