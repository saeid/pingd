const state = {
    token: localStorage.getItem('pingd_token'),
    username: localStorage.getItem('pingd_username'),
    currentTopic: null,
    topicPasswords: {},
    subscribedTopics: JSON.parse(localStorage.getItem('pingd_subscribed') || '[]'),
    topicData: {},
    sseAbort: null,
    liveTopics: {},
    pendingTopic: null,
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
async function api(method, path, body, topicName) {
    const headers = {};
    if (body) headers['Content-Type'] = 'application/json';
    if (state.token) headers['Authorization'] = `Bearer ${state.token}`;
    if (topicName && state.topicPasswords[topicName]) {
        headers['X-Topic-Password'] = state.topicPasswords[topicName];
    }

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
    loadSubscribedTopics();
}

// Subscribed topics
function saveSubscribedTopics() {
    localStorage.setItem('pingd_subscribed', JSON.stringify(state.subscribedTopics));
}

function subscribeTopic(name, topic) {
    if (!state.subscribedTopics.includes(name)) {
        state.subscribedTopics.push(name);
        saveSubscribedTopics();
    }
    if (topic) state.topicData[name] = topic;
    renderSubscribedTopics();
}

function unsubscribeTopic(name) {
    state.subscribedTopics = state.subscribedTopics.filter(n => n !== name);
    saveSubscribedTopics();
    delete state.topicData[name];
    delete state.topicPasswords[name];
    delete state.liveTopics[name];
    if (state.currentTopic === name) {
        state.currentTopic = null;
        disconnectSSE();
        emptyState.classList.remove('hidden');
        messagesView.classList.add('hidden');
    }
    renderSubscribedTopics();
}

async function loadSubscribedTopics() {
    for (const name of state.subscribedTopics) {
        try {
            const topic = await api('GET', `/topics/${name}`, null, name);
            state.topicData[name] = topic;
        } catch {
            state.topicData[name] = { name, visibility: 'unknown', hasPassword: false };
        }
    }
    renderSubscribedTopics();
}

function renderSubscribedTopics() {
    topicList.innerHTML = '';
    state.subscribedTopics.forEach(name => {
        const topic = state.topicData[name] || { name, visibility: 'unknown', hasPassword: false };
        const el = document.createElement('div');
        el.className = 'topic-item' + (state.currentTopic === name ? ' active' : '');

        const nameEl = document.createElement('span');
        nameEl.className = 'topic-name';
        nameEl.textContent = name;
        el.appendChild(nameEl);

        if (topic.hasPassword) {
            const lockEl = document.createElement('span');
            lockEl.className = 'topic-lock';
            lockEl.textContent = '\u{1F512}';
            el.appendChild(lockEl);
        }

        if (state.liveTopics[name]) {
            const liveEl = document.createElement('span');
            liveEl.className = 'badge badge-live';
            liveEl.textContent = 'live';
            el.appendChild(liveEl);
        }

        const badgeEl = document.createElement('span');
        badgeEl.className = `badge badge-${topic.visibility}`;
        badgeEl.textContent = topic.visibility;
        el.appendChild(badgeEl);

        el.addEventListener('click', () => selectTopic(topic));
        topicList.appendChild(el);
    });
}

// Join topic by name
const joinTopicForm = document.getElementById('join-topic-form');
joinTopicForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = document.getElementById('join-topic-name').value.trim();
    if (!name) return;

    try {
        const topic = await api('GET', `/topics/${name}`, null, name);
        document.getElementById('join-topic-name').value = '';
        subscribeTopic(name, topic);
        selectTopic(topic);
    } catch (err) {
        if (err.message.startsWith('403')) {
            showPasswordModal(name);
        } else {
            alert(err.message);
        }
    }
});

// Password modal
const passwordModal = document.getElementById('password-modal');
const passwordForm = document.getElementById('password-form');
const passwordError = document.getElementById('password-error');
const passwordCancel = document.getElementById('password-cancel');

function showPasswordModal(topicName) {
    state.pendingTopic = topicName;
    passwordError.classList.add('hidden');
    document.getElementById('topic-password-input').value = '';
    passwordModal.classList.remove('hidden');
    document.getElementById('topic-password-input').focus();
}

passwordCancel.addEventListener('click', () => {
    passwordModal.classList.add('hidden');
    state.pendingTopic = null;
});

passwordForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const password = document.getElementById('topic-password-input').value;
    const topicName = state.pendingTopic;
    if (!topicName) return;

    state.topicPasswords[topicName] = password;

    try {
        const topic = await api('GET', `/topics/${topicName}`, null, topicName);
        passwordModal.classList.add('hidden');
        state.pendingTopic = null;
        document.getElementById('join-topic-name').value = '';
        subscribeTopic(topicName, topic);
        selectTopic(topic);
    } catch (err) {
        delete state.topicPasswords[topicName];
        if (err.message.startsWith('403')) {
            passwordError.textContent = 'Wrong password';
            passwordError.classList.remove('hidden');
        } else {
            passwordError.textContent = err.message;
            passwordError.classList.remove('hidden');
        }
    }
});

createTopicForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = document.getElementById('topic-name').value;
    const visibility = document.getElementById('topic-visibility').value;

    try {
        const topic = await api('POST', '/topics', { name, visibility });
        document.getElementById('topic-name').value = '';
        subscribeTopic(name, topic);
        selectTopic(topic);
    } catch (err) {
        alert(err.message);
    }
});

deleteTopicBtn.addEventListener('click', async () => {
    if (!state.currentTopic) return;
    if (!confirm(`Delete topic "${state.currentTopic}"?`)) return;

    try {
        await api('DELETE', `/topics/${state.currentTopic}`);
        unsubscribeTopic(state.currentTopic);
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

    // Update live toggle to reflect this topic's state
    const isLive = !!state.liveTopics[topic.name];
    sseToggle.classList.toggle('active', isLive);

    renderSubscribedTopics();
    await loadMessages();
    if (isLive) connectSSE();
}

async function loadMessages() {
    try {
        const messages = await api('GET', `/topics/${state.currentTopic}/messages`, null, state.currentTopic);
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
        }, state.currentTopic);
        document.getElementById('msg-title').value = '';
        document.getElementById('msg-body').value = '';
        if (!state.liveTopics[state.currentTopic]) await loadMessages();
    } catch (err) {
        alert(err.message);
    }
});

// SSE via fetch (supports auth headers) — per topic
sseToggle.addEventListener('click', () => {
    if (!state.currentTopic) return;
    const topic = state.currentTopic;
    if (state.liveTopics[topic]) {
        disconnectSSE();
        delete state.liveTopics[topic];
        sseToggle.classList.remove('active');
    } else {
        state.liveTopics[topic] = true;
        sseToggle.classList.add('active');
        connectSSE();
    }
    renderSubscribedTopics();
});

async function connectSSE() {
    disconnectSSE();
    if (!state.currentTopic) return;

    const topic = state.currentTopic;
    const abort = new AbortController();
    state.sseAbort = abort;

    const headers = {};
    if (state.token) headers['Authorization'] = `Bearer ${state.token}`;
    if (state.topicPasswords[topic]) {
        headers['X-Topic-Password'] = state.topicPasswords[topic];
    }

    try {
        const res = await fetch(`/topics/${topic}/stream`, {
            headers,
            signal: abort.signal,
        });

        if (!res.ok) {
            delete state.liveTopics[topic];
            sseToggle.classList.remove('active');
            renderSubscribedTopics();
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
                    const msg = JSON.parse(line.slice(6));
                    if (state.currentTopic === topic) {
                        appendMessage(msg, true);
                    }

                    if (notificationSound) {
                        notificationSound.currentTime = 0;
                        notificationSound.play().catch(() => {});
                    }

                    if (Notification.permission === 'granted') {
                        new Notification(msg.payload?.title || topic, {
                            body: msg.payload?.body,
                        });
                    }
                } catch {}
            }
        }
    } catch (err) {
        if (err.name !== 'AbortError') {
            delete state.liveTopics[topic];
            sseToggle.classList.remove('active');
            renderSubscribedTopics();
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
