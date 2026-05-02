const app = document.getElementById("app");
const modalRoot = document.getElementById("modal-root");
const toastRoot = document.getElementById("toast-root");

const cachedWebPush = safeJsonParse(localStorage.getItem("pingd_webpush_device") || "");

const state = {
    token: localStorage.getItem("pingd_token"),
    guest: false,
    user: null,
    topics: [],
    currentTab: "topics",
    currentTopicName: null,
    messagesByTopic: {},
    topicStatsByTopic: {},
    topicPasswords: JSON.parse(localStorage.getItem("pingd_topic_passwords") || "{}"),
    authMode: "login",
    authError: "",
    modal: null,
    toast: null,
    toastTimer: null,
    tokens: [],
    tokensLoaded: false,
    webPushDevice: cachedWebPush?.device || null,
    webPushToken: cachedWebPush?.pushToken || null,
    webPushBusy: false,
    webhooksByTopic: {},
    webhooksLoadedByTopic: {},
    webhooksDeniedByTopic: {},
};

function escapeHtml(value) {
    return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
}

function encodePath(value) {
    return encodeURIComponent(value);
}

function hasSession() {
    return Boolean(state.token || state.guest);
}

function currentTopic() {
    return state.topics.find((topic) => topic.name === state.currentTopicName) || null;
}

function requestedTopicFromLocation() {
    const topicName = new URLSearchParams(window.location.search).get("topic");
    if (!topicName) return "";

    const normalized = topicName.trim();
    return normalized.length <= 200 ? normalized : "";
}

function clearRequestedTopicFromLocation() {
    const url = new URL(window.location.href);
    if (!url.searchParams.has("topic")) return;

    url.searchParams.delete("topic");
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
}

function saveTopicPasswords() {
    localStorage.setItem("pingd_topic_passwords", JSON.stringify(state.topicPasswords));
}

function persistWebPushDevice(device, pushToken) {
    if (!device || !pushToken) {
        localStorage.removeItem("pingd_webpush_device");
        return;
    }
    localStorage.setItem("pingd_webpush_device", JSON.stringify({ device, pushToken }));
}

function safeJsonParse(text) {
    try {
        return JSON.parse(text);
    } catch {
        return null;
    }
}

async function api(method, path, { body, topicName, headers: extraHeaders } = {}) {
    const headers = { ...(extraHeaders || {}) };
    if (body !== undefined) {
        headers["Content-Type"] = "application/json";
    }
    if (state.token) {
        headers.Authorization = `Bearer ${state.token}`;
    }
    if (topicName && state.topicPasswords[topicName]) {
        headers["X-Topic-Password"] = state.topicPasswords[topicName];
    }

    const response = await fetch(path, {
        method,
        headers,
        body: body !== undefined ? JSON.stringify(body) : undefined,
    });

    if (response.status === 204) {
        return null;
    }

    const raw = await response.text();
    const data = raw ? safeJsonParse(raw) : null;

    if (!response.ok) {
        const error = new Error(
            data?.reason ||
            data?.error ||
            raw ||
            `${response.status} ${response.statusText}`
        );
        error.status = response.status;
        error.payload = data;
        throw error;
    }

    return data;
}

function setToast(message, tone = "default") {
    state.toast = { message, tone };
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => {
        state.toast = null;
        renderToast();
    }, 2600);
    renderToast();
}

function clearSession() {
    state.token = null;
    state.user = null;
    state.guest = false;
    state.tokens = [];
    state.tokensLoaded = false;
    state.webPushDevice = null;
    state.webPushToken = null;
    state.webPushBusy = false;
    state.webhooksByTopic = {};
    state.webhooksLoadedByTopic = {};
    state.webhooksDeniedByTopic = {};
    localStorage.removeItem("pingd_token");
    localStorage.removeItem("pingd_webpush_device");
}

function persistToken(token) {
    state.token = token;
    localStorage.setItem("pingd_token", token);
}

function towerMark(size = 20) {
    const stroke = Math.max(1, size * 0.04);

    return `
        <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" fill="none" aria-hidden="true">
            <path d="M${size * 0.08} ${size * 0.48}A${size * 0.42} ${size * 0.42} 0 0 1 ${size * 0.92} ${size * 0.48}" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round" opacity="0.24"/>
            <path d="M${size * 0.2} ${size * 0.48}A${size * 0.3} ${size * 0.3} 0 0 1 ${size * 0.8} ${size * 0.48}" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round" opacity="0.58"/>
            <path d="M${size * 0.32} ${size * 0.48}A${size * 0.18} ${size * 0.18} 0 0 1 ${size * 0.68} ${size * 0.48}" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round"/>
            <line x1="${size * 0.5}" y1="${size * 0.48}" x2="${size * 0.5}" y2="${size * 0.76}" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round"/>
            <line x1="${size * 0.5}" y1="${size * 0.66}" x2="${size * 0.32}" y2="${size * 0.76}" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round"/>
            <line x1="${size * 0.5}" y1="${size * 0.66}" x2="${size * 0.68}" y2="${size * 0.76}" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round"/>
        </svg>
    `;
}

function icon(name) {
    const icons = {
        topics: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>`,
        account: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`,
        refresh: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.5 9a9 9 0 0 1 14.12-3.36L23 10M1 14l5.38 4.36A9 9 0 0 0 20.5 15"/></svg>`,
        unsubscribe: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>`,
        trash: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4h6v2"/></svg>`,
        globe: `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`,
        protected: `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2.8 19 5.9v5.2c0 4.4-2.9 8.4-7 10.1-4.1-1.7-7-5.7-7-10.1V5.9L12 2.8Z"/><path d="M12 6.4v11.8"/></svg>`,
        private: `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`,
        logout: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>`,
    };

    return icons[name] || "";
}

function visibilityBadge(visibility) {
    const value = visibility || "unknown";
    const className = {
        open: "badge-open",
        protected: "badge-protected",
        private: "badge-private",
    }[value] || "badge-off";

    return `<span class="badge ${className}">${escapeHtml(value)}</span>`;
}

function visibilityIcon(visibility) {
    switch (visibility) {
    case "open":
        return icon("globe");
    case "protected":
        return icon("protected");
    case "private":
        return icon("private");
    default:
        return "";
    }
}

function priorityClass(priority) {
    const p = Number(priority);
    if (p >= 3) return "priority-urgent";
    if (p <= 1) return "priority-low";
    return "priority-default";
}

function formatDate(value) {
    if (!value) return "—";
    return new Date(value).toLocaleDateString(undefined, {
        year: "numeric",
        month: "short",
        day: "numeric",
    });
}

function formatDateTime(value) {
    if (!value) return "—";
    return new Date(value).toLocaleString(undefined, {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
    });
}

function truncateId(value) {
    if (!value) return "—";
    return value.length > 12 ? `${value.slice(0, 12)}…` : value;
}

function maskToken(value) {
    if (!value) return "—";
    return value.length > 16 ? `${value.slice(0, 10)}••••••${value.slice(-6)}` : value;
}

function isCurrentSessionToken(tokenValue) {
    if (!state.token || !tokenValue) return false;
    if (tokenValue === state.token) return true;
    return state.token.endsWith(tokenValue.slice(-4)) && tokenValue.startsWith("pgd_****");
}

function upsertTopic(topic) {
    const existing = state.topics.findIndex((item) => item.name === topic.name);
    if (existing >= 0) {
        state.topics[existing] = topic;
    } else {
        state.topics.push(topic);
        state.topics.sort((left, right) => left.name.localeCompare(right.name));
    }
}

async function loadMe() {
    state.user = await api("GET", "/me");
}

async function loadTopics() {
    state.topics = (await api("GET", "/topics")) || [];
    if (
        state.currentTopicName &&
        !state.topics.some((topic) => topic.name === state.currentTopicName)
    ) {
        state.currentTopicName = null;
    }
}

async function loadTokens() {
    if (!state.user?.username) {
        state.tokens = [];
        state.tokensLoaded = false;
        return;
    }

    state.tokens = await api("GET", `/users/${encodePath(state.user.username)}/tokens`);
    state.tokensLoaded = true;
}

function topicFromSubscription(subscription) {
    const topic = subscription.topic || {};
    return {
        id: topic.id,
        name: topic.name,
        visibility: topic.visibility,
        hasPassword: !!topic.hasPassword,
        ownerUserID: topic.ownerUserID,
    };
}

async function loadSubscribedTopics() {
    if (!state.user?.username || state.user.role !== "user") {
        return;
    }

    const subscriptions = await api("GET", `/users/${encodePath(state.user.username)}/subscriptions`);
    const topicsByName = new Map();
    for (const subscription of subscriptions || []) {
        const topic = topicFromSubscription(subscription);
        if (topic.name) {
            topicsByName.set(topic.name, topic);
        }
    }

    state.topics = [...topicsByName.values()]
        .sort((left, right) => left.name.localeCompare(right.name));
    if (
        state.currentTopicName &&
        !state.topics.some((topic) => topic.name === state.currentTopicName)
    ) {
        state.currentTopicName = null;
    }
}

function supportsWebPush() {
    return "serviceWorker" in navigator &&
        "PushManager" in window &&
        "Notification" in window;
}

function deviceInfo() {
    const data = navigator.userAgentData;
    const ua = navigator.userAgent;

    let browser, osLabel, platform;

    if (data?.brands?.length) {
        browser = data.brands.find((b) => !/Not.?A.?Brand/i.test(b.brand))?.brand || "Browser";
        osLabel = data.platform || "Device";
        platform = osLabel === "iOS" ? "ios" : osLabel === "Android" ? "android" : "web";
    } else {
        browser = /Edg\//.test(ua) ? "Edge"
            : /Firefox\/|FxiOS\//.test(ua) ? "Firefox"
            : /Chrome\/|CriOS\//.test(ua) ? "Chrome"
            : /Safari\//.test(ua) ? "Safari"
            : "Browser";
        const isIPad = /iPad/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
        [osLabel, platform] = /iPhone/.test(ua) ? ["iPhone", "ios"]
            : isIPad ? ["iPad", "ios"]
            : /Android/.test(ua) ? ["Android", "android"]
            : /Mac OS X/.test(ua) ? ["macOS", "web"]
            : /Windows/.test(ua) ? ["Windows", "web"]
            : /Linux/.test(ua) ? ["Linux", "web"]
            : ["Device", "web"];
    }

    return { name: `${browser} on ${osLabel}`, platform };
}

function showInstallHintIfNeeded() {
    const isAppleMobile = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    const isStandalone = window.matchMedia("(display-mode: standalone)").matches ||
        window.navigator.standalone === true;
    if (isAppleMobile && !isStandalone) {
        setToast("Safari push works after adding Pingd to Home Screen and opening it there.", "default");
        return true;
    }
    return false;
}

function urlBase64ToUint8Array(value) {
    const padding = "=".repeat((4 - value.length % 4) % 4);
    const base64 = (value + padding).replaceAll("-", "+").replaceAll("_", "/");
    const rawData = atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let index = 0; index < rawData.length; index += 1) {
        outputArray[index] = rawData.charCodeAt(index);
    }
    return outputArray;
}

function uint8ArrayToUrlBase64(value) {
    if (!value) return "";

    const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
    let binary = "";
    for (const byte of bytes) {
        binary += String.fromCharCode(byte);
    }

    return btoa(binary)
        .replaceAll("+", "-")
        .replaceAll("/", "_")
        .replaceAll("=", "");
}

function subscriptionVAPIDKey(subscription) {
    return uint8ArrayToUrlBase64(subscription?.options?.applicationServerKey);
}

function serializeSubscription(subscription, fallbackVapidKey) {
    return JSON.stringify({
        ...subscription.toJSON(),
        applicationServerKey: subscriptionVAPIDKey(subscription) || fallbackVapidKey,
    });
}

async function registerOrUpdatePushDevice(pushToken) {
    const { name, platform } = deviceInfo();
    const existing = state.webPushDevice;
    const canPatch = existing?.id && existing.userID === state.user?.id;

    if (canPatch) {
        try {
            return await api("PATCH", `/devices/${encodePath(existing.id)}`, {
                body: { name, pushToken, isActive: true, deliveryEnabled: true },
            });
        } catch (error) {
            if (![403, 404, 409].includes(error.status)) {
                throw error;
            }
        }
    }

    return await api("POST", "/devices", {
        body: { name, platform, pushType: "webpush", pushToken, deliveryEnabled: true },
    });
}

async function apiSubscribe(device, topicName) {
    if (!device?.id || !topicName) return;

    try {
        await api("POST", `/devices/${encodePath(device.id)}/subscriptions`, {
            topicName,
            body: { topicName },
        });
    } catch (error) {
        if (error.status === 404) {
            state.webPushDevice = null;
            state.webPushToken = null;
            persistWebPushDevice(null);
            return;
        }
        if (error.status !== 409) {
            throw error;
        }
    }
}

function prefetchPushPermission() {
    if (!supportsWebPush() || !window.isSecureContext || Notification.permission !== "default") {
        return Promise.resolve(Notification.permission);
    }
    return Notification.requestPermission().catch(() => Notification.permission);
}

async function enablePush({ requestPermission = true } = {}) {
    if (!state.token || !state.user || state.user.role === "guest") {
        return;
    }

    if (!supportsWebPush()) {
        throw new Error("Web Push is not supported by this browser");
    }

    if (!window.isSecureContext) {
        throw new Error("HTTPS required (or localhost)");
    }

    let permission = Notification.permission;
    if (permission === "default" && requestPermission) {
        permission = await Notification.requestPermission();
    }

    if (permission !== "granted") {
        throw new Error("Notification permission was not granted");
    }

    const options = await api("GET", "/webpush/vapid-key");
    const vapidKey = options?.vapid;

    if (!vapidKey) {
        throw new Error("Web Push is not configured");
    }

    const registration = await navigator.serviceWorker.register("/serviceWorker.mjs");
    await registration.update();

    let subscription = await registration.pushManager.getSubscription();
    if (subscription && subscriptionVAPIDKey(subscription) !== vapidKey) {
        await subscription.unsubscribe();
        subscription = null;
    }

    if (!subscription) {
        subscription = await registration.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(vapidKey),
        });
    }

    const pushToken = serializeSubscription(subscription, vapidKey);
    state.webPushToken = pushToken;

    state.webPushDevice = await registerOrUpdatePushDevice(pushToken);
    persistWebPushDevice(state.webPushDevice, pushToken);

    await Promise.allSettled(
        state.topics.map((topic) => apiSubscribe(state.webPushDevice, topic.name))
    );
}

async function restorePush() {
    if (!state.token || !state.user || state.user.role === "guest" || !supportsWebPush()) {
        state.webPushDevice = null;
        state.webPushToken = null;
        persistWebPushDevice(null);
        return;
    }
    if (!window.isSecureContext || Notification.permission !== "granted") {
        return;
    }

    const cached = safeJsonParse(localStorage.getItem("pingd_webpush_device") || "");
    const cachedToken = safeJsonParse(cached?.pushToken || "");
    if (cached?.device && cached.device.userID === state.user.id && cachedToken?.endpoint) {
        try {
            const registration = await navigator.serviceWorker.register("/serviceWorker.mjs");
            const subscription = await registration.pushManager.getSubscription();
            if (subscription?.endpoint === cachedToken.endpoint) {
                state.webPushDevice = cached.device;
                state.webPushToken = cached.pushToken;
                return;
            }
        } catch (error) {
            console.warn("Push hydration failed", error);
        }
    }

    try {
        await enablePush({ requestPermission: false });
    } catch (error) {
        console.warn("Push restore failed", error);
    }
}

async function enablePushFromAccount() {
    if (state.webPushBusy) return;

    state.webPushBusy = true;
    render();
    try {
        await enablePush();
        setToast("Notifications enabled", "success");
    } catch (error) {
        setToast(error.message, "error");
    } finally {
        state.webPushBusy = false;
        render();
    }
}

async function subscribeToTopic(topicName, { promptPermission = true } = {}) {
    if (!state.token || !state.user || state.user.role === "guest" || !topicName) {
        return;
    }

    if (!promptPermission && !state.webPushDevice?.id) {
        return;
    }

    if (!state.webPushDevice?.id) {
        await enablePush();
    }
    await apiSubscribe(state.webPushDevice, topicName);
}

async function unsubscribeFromTopic(topicName) {
    if (!state.token || !state.user || state.user.role !== "user" || !topicName) {
        return;
    }
    const topic = state.topics.find((item) => item.name === topicName);
    if (topic?.ownerUserID === state.user.id) {
        throw new Error("Owners cannot unsubscribe from their own topic");
    }

    if (state.webPushDevice?.id) {
        try {
            await api("DELETE", `/devices/${encodePath(state.webPushDevice.id)}/subscriptions/${encodePath(topicName)}`);
        } catch (error) {
            if (error.status !== 404) throw error;
        }
    }

    state.topics = state.topics.filter((topic) => topic.name !== topicName);
    delete state.messagesByTopic[topicName];
    delete state.topicStatsByTopic[topicName];
    delete state.webhooksByTopic[topicName];
    delete state.webhooksLoadedByTopic[topicName];
    delete state.webhooksDeniedByTopic[topicName];
    if (state.currentTopicName === topicName) {
        state.currentTopicName = null;
    }
    render();
    setToast(`Unsubscribed from ${topicName}`, "success");
}

async function loadWebhooks(topicName) {
    if (!state.token || !topicName) {
        delete state.webhooksByTopic[topicName];
        delete state.webhooksLoadedByTopic[topicName];
        delete state.webhooksDeniedByTopic[topicName];
        return;
    }

    try {
        state.webhooksByTopic[topicName] = await api(
            "GET",
            `/topics/${encodePath(topicName)}/webhooks`,
            { topicName }
        );
        state.webhooksDeniedByTopic[topicName] = false;
        state.webhooksLoadedByTopic[topicName] = true;
    } catch (error) {
        if (error.status !== 403) {
            setToast(error.message, "error");
        }
        state.webhooksByTopic[topicName] = [];
        state.webhooksDeniedByTopic[topicName] = error.status === 403;
        state.webhooksLoadedByTopic[topicName] = true;
    }
}

async function loadTopicStats(topicName) {
    if (state.user?.role !== "admin") {
        delete state.topicStatsByTopic[topicName];
        return;
    }

    try {
        state.topicStatsByTopic[topicName] = await api(
            "GET",
            `/topics/${encodePath(topicName)}/stats`
        );
    } catch (error) {
        if (error.status !== 403) {
            setToast(error.message, "error");
        }
        delete state.topicStatsByTopic[topicName];
    }
}

async function loadMessages(topicName) {
    state.messagesByTopic[topicName] = await api(
        "GET",
        `/topics/${encodePath(topicName)}/messages`,
        { topicName }
    );
}

async function bootstrapAuthenticatedSession({ syncWebPush = true } = {}) {
    await loadMe();
    if (state.user?.role === "admin") {
        await loadTopics();
    } else {
        await loadSubscribedTopics();
    }
    if (state.currentTab === "account") {
        await loadTokens();
    }
    render();
    await selectRequestedTopicFromLocation();
    if (syncWebPush) {
        void restorePush();
    }
}

async function bootstrapGuestSession() {
    render();
    await selectRequestedTopicFromLocation();
}

function openModal(modal) {
    state.modal = modal;
    renderModal();
}

function closeModal() {
    state.modal = null;
    renderModal();
}

function openPasswordModal(topicName, onSuccess, errorMessage = "") {
    openModal({
        type: "password",
        topicName,
        onSuccess,
        errorMessage,
    });
}

async function handleProtectedAction(topicName, action) {
    try {
        await action();
    } catch (error) {
        if (error.status === 403) {
            const hadPassword = !!state.topicPasswords[topicName];
            if (hadPassword) {
                delete state.topicPasswords[topicName];
                saveTopicPasswords();
            }
            openPasswordModal(topicName, action, hadPassword ? "Wrong password" : "");
            return;
        }
        setToast(error.message, "error");
    }
}

async function lookupTopicByName(topicName, { subscribe = true, promptPermission = true } = {}) {
    const name = topicName.trim();
    if (!name) return;

    try {
        const topic = await api("GET", `/topics/${encodePath(name)}`, { topicName: name });
        upsertTopic(topic);
        if (subscribe) {
            await subscribeToTopic(topic.name, { promptPermission });
        }
        state.currentTab = "topics";
        state.currentTopicName = topic.name;
        const loads = [loadMessages(topic.name), loadTopicStats(topic.name)];
        if (canManageWebhooks(topic)) {
            loads.push(loadWebhooks(topic.name));
        }
        await Promise.all(loads);
        render();
    } catch (error) {
        if (error.status === 403 && state.topicPasswords[name]) {
            delete state.topicPasswords[name];
            saveTopicPasswords();
            openPasswordModal(name, () => lookupTopicByName(name, { subscribe, promptPermission }), "Wrong password");
            return;
        }
        if (error.status === 403 && state.guest) {
            openPasswordModal(name, () => lookupTopicByName(name, { subscribe, promptPermission }));
            return;
        }
        setToast(error.status === 403 ? "Permission denied" : error.message, "error");
    }
}

async function selectTopic(topicName) {
    await lookupTopicByName(topicName);
}

async function selectRequestedTopicFromLocation() {
    const topicName = requestedTopicFromLocation();
    if (!topicName || !hasSession()) return;

    clearRequestedTopicFromLocation();
    await lookupTopicByName(topicName, { promptPermission: false });
}

async function createTopic(form) {
    const name = form.get("name").trim();
    const visibility = form.get("visibility");
    const password = form.get("password").trim();

    if (!name) {
        throw new Error("Topic name is required");
    }
    const body = {
        name,
        visibility,
        password: password || null,
    };

    const topic = await api("POST", "/topics", { body });
    upsertTopic(topic);
    if (password) {
        state.topicPasswords[name] = password;
        saveTopicPasswords();
    }
    await subscribeToTopic(topic.name);
    closeModal();
    setToast(`Created topic ${name}`, "success");
    await lookupTopicByName(name, { subscribe: false });
    if (state.user?.role === "admin") {
        await loadTopics();
    } else if (state.token) {
        await loadSubscribedTopics();
    }
    render();
}

async function publishCurrentTopic(form) {
    const topic = currentTopic();
    if (!topic) return;

    const title = form.get("title").trim();
    const body = form.get("body").trim();
    const tags = form.get("tags")
        .split(",")
        .map((tag) => tag.trim())
        .filter(Boolean);
    const priority = Number(form.get("priority") || 3);
    const ttlRaw = form.get("ttl");
    const ttl = ttlRaw ? Number(ttlRaw) : null;

    if (!body) {
        throw new Error("Message body is required");
    }

    await handleProtectedAction(topic.name, async () => {
        const message = await api(
            "POST",
            `/topics/${encodePath(topic.name)}/messages`,
            {
                topicName: topic.name,
                body: {
                    priority,
                    tags: tags.length ? tags : null,
                    payload: {
                        title: title || null,
                        subtitle: null,
                        body,
                    },
                    ttl,
                },
            }
        );

        const existing = state.messagesByTopic[topic.name] || [];
        state.messagesByTopic[topic.name] = [...existing, message];
        await loadTopicStats(topic.name);
        render();

        setToast(`Published to ${topic.name}`, "success");
    });
}

async function removeCurrentTopic() {
    const topic = currentTopic();
    if (!topic) return;

    await api("DELETE", `/topics/${encodePath(topic.name)}`);
    delete state.messagesByTopic[topic.name];
    delete state.topicStatsByTopic[topic.name];
    delete state.webhooksByTopic[topic.name];
    delete state.webhooksLoadedByTopic[topic.name];
    delete state.webhooksDeniedByTopic[topic.name];
    delete state.topicPasswords[topic.name];
    saveTopicPasswords();
    if (state.currentTopicName === topic.name) {
        state.currentTopicName = null;
    }
    if (state.user?.role === "admin") {
        await loadTopics();
    } else {
        state.topics = state.topics.filter((item) => item.name !== topic.name);
    }
    closeModal();
    render();
    setToast(`Deleted topic ${topic.name}`);
}

async function createToken(form) {
    const label = form.get("label").trim();
    if (!label) {
        throw new Error("Token label is required");
    }

    const created = await api("POST", `/users/${encodePath(state.user.username)}/tokens`, {
        body: {
            label,
            expiresAt: null,
        },
    });

    await loadTokens();
    state.modal = { type: "token-created", token: created.token, label: created.label };
    render();
    renderModal();
}

async function revokeToken(tokenID) {
    await api("DELETE", `/tokens/${encodePath(tokenID)}`);
    await loadTokens();
    closeModal();
    render();
    setToast("Token revoked");
}

function webhookURL(token) {
    return `${window.location.origin}/hooks/${token}`;
}

function webhookTitle(webhook) {
    const template = webhook.template || {};
    return template.title || template.body || "Untitled webhook";
}

function webhookTemplateFromForm(form) {
    const priorityRaw = form.get("priority");
    const ttlRaw = form.get("ttl");
    const field = (name) => (form.get(name) ?? "").trim();
    const template = {
        title: field("title") || null,
        subtitle: field("subtitle") || null,
        body: field("body") || null,
        tags: field("tags") || null,
        priority: priorityRaw ? Number(priorityRaw) : null,
        ttl: ttlRaw ? Number(ttlRaw) : null,
    };

    if (template.priority && (template.priority < 1 || template.priority > 3)) {
        throw new Error("Priority must be between 1 and 3");
    }
    if (template.ttl && template.ttl < 1) {
        throw new Error("TTL must be positive");
    }
    return template;
}

async function createWebhook(form) {
    const topic = currentTopic();
    if (!topic) return;
    if (!canManageWebhooks(topic)) {
        throw new Error("Only admins and topic owners can manage webhooks");
    }

    const template = webhookTemplateFromForm(form);
    const created = await api("POST", `/topics/${encodePath(topic.name)}/webhooks`, {
        topicName: topic.name,
        body: { template },
    });

    await loadWebhooks(topic.name);
    state.modal = {
        type: "webhook-created",
        token: created.token,
        url: webhookURL(created.token),
        topicName: topic.name,
    };
    render();
    renderModal();
}

async function updateWebhook(webhookID, form) {
    const topic = currentTopic();
    if (!topic) return;
    if (!canManageWebhooks(topic)) {
        throw new Error("Only admins and topic owners can manage webhooks");
    }

    const template = webhookTemplateFromForm(form);
    await api("PATCH", `/webhooks/${encodePath(webhookID)}`, {
        body: { template },
    });
    await loadWebhooks(topic.name);
    closeModal();
    render();
    setToast("Webhook updated", "success");
}

async function deleteWebhook(webhookID) {
    const topic = currentTopic();
    if (!topic) return;
    if (!canManageWebhooks(topic)) {
        throw new Error("Only admins and topic owners can manage webhooks");
    }

    await api("DELETE", `/webhooks/${encodePath(webhookID)}`);
    await loadWebhooks(topic.name);
    closeModal();
    render();
    setToast("Webhook deleted");
}

async function handleLogin(form) {
    const username = form.get("username").trim();
    const password = form.get("password");
    const notificationPermission = prefetchPushPermission();

    try {
        const data = await api("POST", "/auth/login", {
            body: {
                username,
                password,
                label: "dashboard",
            },
        });
        persistToken(data.token);
        state.guest = false;
        state.authError = "";
        await bootstrapAuthenticatedSession({ syncWebPush: false });
        void notificationPermission.then(restorePush);
        if (!showInstallHintIfNeeded()) {
            setToast(`Welcome back ${data.username}`, "success");
        }
    } catch (error) {
        state.authError = error.message;
        render();
    }
}

async function handleRegister(form) {
    const username = form.get("username").trim();
    const password = form.get("password");
    const confirmPassword = form.get("confirmPassword");

    if (password !== confirmPassword) {
        state.authError = "Passwords do not match";
        render();
        return;
    }

    const notificationPermission = prefetchPushPermission();

    try {
        const data = await api("POST", "/auth/register", {
            body: {
                username,
                password,
                label: "dashboard",
            },
        });
        persistToken(data.token);
        state.guest = false;
        state.authError = "";
        await bootstrapAuthenticatedSession({ syncWebPush: false });
        void notificationPermission.then(restorePush);
        if (!showInstallHintIfNeeded()) {
            setToast(`Account created for ${data.username}`, "success");
        }
    } catch (error) {
        state.authError = error.message;
        render();
    }
}

async function logout() {
    if (state.token) {
        try {
            await api("DELETE", "/auth/logout", {
                headers: state.webPushToken ? { "X-Push-Token": state.webPushToken } : undefined,
            });
        } catch {}
    }
    clearSession();
    state.currentTab = "topics";
    state.currentTopicName = null;
    render();
}

async function continueAsGuest() {
    clearSession();
    state.guest = true;
    state.authError = "";
    await bootstrapGuestSession();
}

function renderAuth() {
    const isLogin = state.authMode === "login";

    app.innerHTML = `
        <div class="auth-shell">
            <section class="auth-card">
                <div class="brand-lockup">
                    <div class="brand-mark">${towerMark(26)}</div>
                    <div class="brand-title">pingd</div>
                    <div class="brand-subtitle">Control topics, publish messages, inspect delivery.</div>
                </div>

                <div class="auth-tabs">
                    <button type="button" class="auth-tab ${isLogin ? "active" : ""}" data-auth-mode="login">Sign in</button>
                    <button type="button" class="auth-tab ${!isLogin ? "active" : ""}" data-auth-mode="register">Register</button>
                </div>

                <form id="auth-form" class="auth-form">
                    <div class="field">
                        <label for="auth-username">Username</label>
                        <input class="input" id="auth-username" name="username" autocomplete="username" placeholder="your username" required>
                    </div>

                    <div class="field">
                        <label for="auth-password">Password</label>
                        <input class="input" id="auth-password" name="password" type="password" autocomplete="current-password" placeholder="your password" required>
                    </div>

                    ${!isLogin ? `
                        <div class="field">
                            <label for="auth-password-confirm">Confirm password</label>
                            <input class="input" id="auth-password-confirm" name="confirmPassword" type="password" autocomplete="new-password" placeholder="repeat password" required>
                        </div>
                    ` : ""}

                    ${state.authError ? `<div class="error-text">${escapeHtml(state.authError)}</div>` : ""}

                    <div class="auth-actions">
                        <button class="btn btn-primary" type="submit">${isLogin ? "Sign in" : "Create account"}</button>
                        <button class="btn btn-outline" id="guest-button" type="button">Continue without login</button>
                    </div>
                </form>

                <p class="auth-note" style="margin-top: 16px;">
                    Registration depends on server configuration. If it is disabled, the dashboard will show the API error directly.
                </p>
            </section>
        </div>
    `;

    app.querySelectorAll("[data-auth-mode]").forEach((button) => {
        button.addEventListener("click", () => {
            state.authMode = button.dataset.authMode;
            state.authError = "";
            render();
        });
    });

    app.querySelector("#auth-form").addEventListener("submit", async (event) => {
        event.preventDefault();
        const form = new FormData(event.currentTarget);
        if (state.authMode === "login") {
            await handleLogin(form);
        } else {
            await handleRegister(form);
        }
    });

    app.querySelector("#guest-button").addEventListener("click", continueAsGuest);
}

function renderTopicItems() {
    if (!state.topics.length) {
        const message = state.user?.role === "admin"
            ? "No topics visible yet."
            : "Subscribe to a topic by name to view it.";
        return `<div class="empty-panel" style="height:auto;padding:18px;"><p>${message}</p></div>`;
    }

    return state.topics.map((topic) => `
        <div class="topic-row ${state.currentTopicName === topic.name ? "active" : ""}">
            <button class="topic-item" data-topic="${escapeHtml(topic.name)}" type="button">
                ${visibilityIcon(topic.visibility)}
                <span class="topic-name">${escapeHtml(topic.name)}</span>
            </button>
            ${state.user?.role === "user" && topic.ownerUserID !== state.user.id ? `
                <button class="topic-unsubscribe" type="button" data-action="unsubscribe-topic" data-topic-name="${escapeHtml(topic.name)}" title="Unsubscribe from ${escapeHtml(topic.name)}" aria-label="Unsubscribe from ${escapeHtml(topic.name)}">
                    ${icon("unsubscribe")}
                </button>
            ` : ""}
        </div>
    `).join("");
}

function renderMessagesPanel() {
    const topic = currentTopic();
    if (!topic) {
        const message = state.user?.role === "admin"
            ? "Select a topic from the left rail or subscribe to one by name to inspect messages and publish new messages."
            : "Subscribe to a topic by name to inspect messages and publish new messages.";
        return `
            <section class="panel message-layout">
                <div class="empty-panel">
                    <p>${message}</p>
                </div>
            </section>
        `;
    }

    const messages = state.messagesByTopic[topic.name] || [];

    return `
        <section class="panel message-layout">
            <header class="panel-header">
                <div class="panel-title">
                    <h2 class="mono">/${escapeHtml(topic.name)}</h2>
                </div>
                <div class="topbar-actions">
                    ${topic.hasPassword ? '<span class="badge badge-muted" title="Password protected">' + icon("protected") + '</span>' : ""}
                    ${visibilityBadge(topic.visibility)}
                    ${state.user?.role === "user" && topic.ownerUserID !== state.user.id ? `
                        <button class="btn btn-outline btn-small" data-action="unsubscribe-topic" data-topic-name="${escapeHtml(topic.name)}" type="button">
                            ${icon("unsubscribe")}
                            Unsubscribe
                        </button>
                    ` : ""}
                    ${state.user?.role === "admin" || state.user?.id === topic.ownerUserID ? `
                        <button class="btn btn-danger btn-small" data-action="delete-topic" type="button">
                            ${icon("trash")}
                        </button>
                    ` : ""}
                </div>
            </header>

            <form id="publish-form" class="composer">
                <input class="input composer-title-input" name="title" placeholder="Title (optional)">
                <textarea class="textarea composer-body-input" name="body" placeholder="Message body…" required></textarea>
                <div class="composer-row">
                    <input class="input" name="tags" placeholder="tags">
                    <select class="select" name="priority">
                        <option value="1">Low</option>
                        <option value="2" selected>Default</option>
                        <option value="3">Urgent</option>
                    </select>
                    <select class="select" name="ttl">
                        <option value="" selected>No expiry</option>
                        <option value="3600">Expires in 1h</option>
                        <option value="21600">Expires in 6h</option>
                        <option value="86400">Expires in 24h</option>
                        <option value="604800">Expires in 7d</option>
                        <option value="2592000">Expires in 30d</option>
                    </select>
                    <button class="btn btn-primary" type="submit">Publish</button>
                </div>
            </form>

            <div class="message-list">
                ${messages.length ? messages.map((message) => `
                    <article class="message-item">
                        <div class="message-priority ${priorityClass(message.priority)}"></div>
                        <div class="message-copy">
                            ${message.payload?.title ? `<div class="message-title">${escapeHtml(message.payload.title)}</div>` : ""}
                            <div class="message-body">${escapeHtml(message.payload?.body || "")}</div>
                            <div class="message-meta">
                                <span class="mono">${formatDateTime(message.time)}</span>
                                ${message.expiresAt ? `<span class="mono" title="Expires ${escapeHtml(new Date(message.expiresAt).toISOString())}">expires ${formatDateTime(message.expiresAt)}</span>` : ""}
                            </div>
                            ${message.tags?.length ? `
                                <div class="message-tags" style="margin-top: 10px;">
                                    ${message.tags.map((tag) => `<span class="tag mono">${escapeHtml(tag)}</span>`).join("")}
                                </div>
                            ` : ""}
                        </div>
                    </article>
                `).join("") : `
                    <div class="empty-panel">
                        <p>No messages yet. Publish the first message to see it here.</p>
                    </div>
                `}
            </div>
        </section>
    `;
}

function renderWebhookTemplateMeta(template = {}) {
    const parts = [];
    if (template.priority) parts.push(`priority ${template.priority}`);
    if (template.ttl) parts.push(`ttl ${template.ttl}s`);
    if (template.tags) parts.push(`tags ${template.tags}`);
    return parts.length ? parts.join(" · ") : "default priority";
}

function canManageWebhooks(topic) {
    if (!state.token || !state.user || !topic) return false;
    return state.user.role === "admin" || state.user.id === topic.ownerUserID;
}

function renderWebhooksPanel(topic) {
    if (!state.token) {
        return "";
    }

    if (!topic) {
        return "";
    }

    if (!canManageWebhooks(topic)) {
        return "";
    }

    const webhooks = state.webhooksByTopic[topic.name] || [];
    const loaded = !!state.webhooksLoadedByTopic[topic.name];
    const denied = !!state.webhooksDeniedByTopic[topic.name];

    return `
        <section class="panel panel-scroll">
            <header class="panel-header">
                <div class="panel-title">
                    <h3>Webhooks</h3>
                    <p>Receive JSON and publish it into this topic.</p>
                </div>
                ${denied ? "" : `<button class="btn btn-primary btn-small" type="button" data-action="new-webhook">New webhook</button>`}
            </header>

            <div class="token-list">
                ${denied ? `
                    <div class="empty-panel">
                        <p>You need publish access to manage webhooks for this topic.</p>
                    </div>
                ` : loaded && webhooks.length ? webhooks.map((webhook) => `
                    <article class="token-row webhook-row">
                        <div>
                            <div class="token-title">${escapeHtml(webhookTitle(webhook))}</div>
                            <div class="token-copy mono">${escapeHtml(truncateId(webhook.id))}</div>
                            <div class="token-meta mono">
                                <span>${escapeHtml(renderWebhookTemplateMeta(webhook.template))}</span>
                                <span>created ${formatDateTime(webhook.createdAt)}</span>
                            </div>
                        </div>
                        <div class="row-actions">
                            <button class="btn btn-outline btn-small" type="button" data-action="edit-webhook" data-webhook-id="${escapeHtml(webhook.id)}">Edit</button>
                            <button class="btn btn-danger btn-small" type="button" data-action="delete-webhook" data-webhook-id="${escapeHtml(webhook.id)}">Delete</button>
                        </div>
                    </article>
                `).join("") : `
                    <div class="empty-panel">
                        <p>${loaded ? "No webhooks created yet." : "Webhook records will load when you open this topic."}</p>
                    </div>
                `}
            </div>
        </section>
    `;
}

function renderTopicRail() {
    const topic = currentTopic();
    const stats = topic ? state.topicStatsByTopic[topic.name] : null;

    if (!topic || (state.user?.role !== "admin" && !canManageWebhooks(topic))) {
        return "";
    }

    return `
        <div class="stack">
            ${state.user?.role === "admin" ? `<section class="panel">
                <header class="panel-header">
                    <div class="panel-title">
                        <h3>Delivery Stats</h3>
                    </div>
                </header>
                <div class="panel-body">
                    ${stats ? `
                        <div class="stat-grid">
                            <div class="stat-card"><strong>${stats.subscriberCount}</strong><span>Subscribers</span></div>
                            <div class="stat-card"><strong>${stats.messageCount}</strong><span>Messages</span></div>
                            <div class="stat-card"><strong>${stats.deliveryStats.delivered}</strong><span>Delivered</span></div>
                            <div class="stat-card"><strong>${stats.deliveryStats.failed}</strong><span>Failed</span></div>
                        </div>
                        <dl class="detail-list" style="margin-top: 14px;">
                            <div class="detail-row"><dt>Pending</dt><dd>${stats.deliveryStats.pending}</dd></div>
                            <div class="detail-row"><dt>Ongoing</dt><dd>${stats.deliveryStats.ongoing}</dd></div>
                            <div class="detail-row"><dt>Last message</dt><dd>${formatDateTime(stats.lastMessageAt)}</dd></div>
                        </dl>
                    ` : `
                        <div class="empty-panel" style="height:auto;padding:0;">
                            <p>Select a topic and stats will load here.</p>
                        </div>
                    `}
                </div>
            </section>` : ""}
            ${renderWebhooksPanel(topic)}
        </div>
    `;
}

function renderTopicsWorkspace() {
    const rail = renderTopicRail();
    return `
        <div class="topics-layout ${rail ? "" : "topics-layout-single"}">
            ${renderMessagesPanel()}
            ${rail}
        </div>
    `;
}

function notificationStatus() {
    if (!supportsWebPush()) {
        return {
            label: "Unsupported",
            className: "badge-off",
            detail: "This browser cannot receive Web Push.",
            canEnable: false,
        };
    }

    if (!window.isSecureContext) {
        return {
            label: "HTTPS required",
            className: "badge-off",
            detail: "Requires HTTPS or localhost.",
            canEnable: false,
        };
    }

    if (Notification.permission === "denied") {
        return {
            label: "Permission denied",
            className: "badge-private",
            detail: "Blocked in browser settings.",
            canEnable: false,
        };
    }

    if (state.webPushDevice?.deliveryEnabled === true) {
        return {
            label: "Enabled",
            className: "badge-open",
            detail: state.webPushDevice.name || "This browser is registered.",
            canEnable: false,
        };
    }

    if (Notification.permission === "granted") {
        return {
            label: "Disabled",
            className: "badge-protected",
            detail: "Permission granted, device not registered.",
            canEnable: true,
        };
    }

    return {
        label: "Disabled",
        className: "badge-muted",
        detail: "Permission has not been requested.",
        canEnable: true,
    };
}

function renderNotificationPanel() {
    const status = notificationStatus();
    const actionDisabled = state.webPushBusy || !status.canEnable;

    return `
        <section class="panel">
            <header class="panel-header">
                <div class="panel-title">
                    <h3>Notifications</h3>
                </div>
                ${status.canEnable ? `
                    <button class="btn btn-outline btn-small" type="button" data-action="enable-notifications" ${actionDisabled ? "disabled" : ""}>
                        ${state.webPushBusy ? "Enabling..." : "Enable"}
                    </button>
                ` : ""}
            </header>
            <div class="panel-body">
                <dl class="detail-list">
                    <div class="detail-row"><dt>Device</dt><dd>${escapeHtml(status.detail)}</dd></div>
                </dl>
            </div>
        </section>
    `;
}

function renderAccountWorkspace() {
    return `
        <div class="account-stack">
            <section class="panel">
                <header class="panel-header">
                    <div class="panel-title">
                        <h2>Account</h2>
                    </div>
                </header>
                <div class="panel-body">
                    <dl class="detail-list">
                        <div class="detail-row"><dt>Username</dt><dd class="mono">${escapeHtml(state.user?.username || "—")}</dd></div>
                        <div class="detail-row">
                            <dt>Password</dt>
                            <dd>
                                <span class="mono">*****</span>
                                <button class="btn btn-outline btn-small" type="button" data-action="change-password" style="margin-left:8px;">Change</button>
                            </dd>
                        </div>
                    </dl>
                </div>
            </section>

            ${renderNotificationPanel()}

            <section class="panel panel-scroll">
                <header class="panel-header">
                    <div class="panel-title">
                        <h3>Access Tokens</h3>
                    </div>
                    <button class="btn btn-primary btn-small" type="button" data-action="new-token">New token</button>
                </header>

                <div class="token-list">
                    ${state.tokensLoaded && state.tokens.length ? state.tokens.map((token) => `
                        <article class="token-row">
                            <div>
                                <div class="token-title-row">
                                    <div class="token-title">${escapeHtml(token.label || "Untitled token")}</div>
                                    ${isCurrentSessionToken(token.token)
                                        ? '<span class="token-session-label mono">current session</span>'
                                        : ""}
                                </div>
                                <div class="token-copy mono">${escapeHtml(maskToken(token.token))}</div>
                                <div class="token-meta mono">
                                    <span>last used ${formatDateTime(token.lastUsedAt)}</span>
                                    <span>expires ${formatDateTime(token.expiresAt)}</span>
                                </div>
                            </div>
                            <div style="display:flex;gap:8px;">
                                ${isCurrentSessionToken(token.token)
                                    ? ''
                                    : `<button class="btn btn-danger btn-small" type="button" data-action="revoke-token" data-token-id="${escapeHtml(token.id)}">Revoke</button>`}
                            </div>
                        </article>
                    `).join("") : `
                        <div class="empty-panel">
                            <p>${state.tokensLoaded ? "No tokens created yet." : "Token records will load when you open this tab."}</p>
                        </div>
                    `}
                </div>
            </section>
        </div>
    `;
}

function renderTopbar() {
    const topic = currentTopic();
    const subtitle = state.currentTab === "account"
        ? "Manage your authenticated session"
        : topic
            ? `/${topic.name}`
            : "Select a topic";
    const mobileTopics = state.topics.length
        ? state.topics.map((item) => `
            <button class="mobile-topic-pill ${state.currentTopicName === item.name ? "active" : ""}" type="button" data-topic="${escapeHtml(item.name)}">
                ${visibilityIcon(item.visibility)}
                <span>${escapeHtml(item.name)}</span>
            </button>
        `).join("")
        : `<span class="mobile-empty-text">${state.user?.role === "admin" ? "No topics visible yet." : "No subscribed topics yet."}</span>`;

    return `
        <header class="topbar">
            <div class="topbar-title">
                <strong>${state.currentTab === "account" ? "Account" : "Topics"}</strong>
                <span class="mono">${escapeHtml(subtitle)}</span>
            </div>
            <div class="topbar-actions">
                <button class="btn btn-outline btn-small" type="button" data-action="refresh">${icon("refresh")}Refresh</button>
            </div>
            <div class="mobile-topbar-controls">
                <div class="mobile-nav-row">
                    <button class="btn btn-outline btn-small ${state.currentTab === "topics" ? "active" : ""}" type="button" data-tab="topics">${icon("topics")}Topics</button>
                    ${state.token ? `<button class="btn btn-outline btn-small ${state.currentTab === "account" ? "active" : ""}" type="button" data-tab="account">${icon("account")}Account</button>` : ""}
                    <button class="btn btn-outline btn-small" type="button" data-action="subscribe-topic">Subscribe</button>
                    ${state.token ? `<button class="btn btn-outline btn-small" type="button" data-action="create-topic">Create</button>` : ""}
                    <button type="button" class="btn btn-ghost btn-small" data-action="logout">${icon("logout")}</button>
                </div>
                ${state.currentTab === "topics" ? `<div class="mobile-topic-strip">${mobileTopics}</div>` : ""}
            </div>
        </header>
    `;
}

function renderAppShell() {
    const topic = currentTopic();
    const displayUser = state.guest ? "guest" : (state.user?.username || "user");
    const userInitial = displayUser[0]?.toLowerCase() || "?";

    app.innerHTML = `
        <div class="app-shell">
            <aside class="sidebar">
                <div class="sidebar-top">
                    <div class="brand-mark">${towerMark(18)}</div>
                    <div class="brand-title">pingd</div>
                </div>

                <div class="sidebar-nav">
                    <button class="nav-item ${state.currentTab === "topics" ? "active" : ""}" type="button" data-tab="topics">
                        ${icon("topics")}
                        <span>Topics</span>
                    </button>
                    ${state.token ? `
                        <button class="nav-item ${state.currentTab === "account" ? "active" : ""}" type="button" data-tab="account">
                            ${icon("account")}
                            <span>Account</span>
                        </button>
                    ` : ""}
                </div>

                <div class="sidebar-section-title">${state.user?.role === "admin" ? "Topics" : "Subscribed topics"}</div>
                <div class="topic-list">${renderTopicItems()}</div>

                <div class="topic-quick-actions">
                    <button class="btn btn-outline" type="button" data-action="subscribe-topic">Subscribe to topic</button>
                    ${state.token ? `<button class="btn btn-outline" type="button" data-action="create-topic">Create topic</button>` : ""}
                </div>

                <div class="sidebar-footer">
                    <div class="sidebar-user">
                        <div class="user-badge mono">${escapeHtml(userInitial)}</div>
                        <div>
                            <div style="font-size: 12px; color: var(--text-muted);">${escapeHtml(displayUser)}</div>
                        </div>
                    </div>
                    <button type="button" class="btn btn-ghost btn-small" data-action="logout">${icon("logout")}</button>
                </div>
            </aside>

            <main class="main-shell">
                ${renderTopbar()}
                <section class="content-shell">
                    ${state.currentTab === "account" && state.token ? renderAccountWorkspace() : renderTopicsWorkspace(topic)}
                </section>
            </main>
        </div>
    `;

    bindAppEvents();
}

function renderWebhookFormFields(template = {}) {
    return `
        <div class="field">
            <label for="webhook-title-input">Title template</label>
            <input class="input" id="webhook-title-input" name="title" placeholder="{{alert.title}}" value="${escapeHtml(template.title || "")}">
        </div>
        <div class="field">
            <label for="webhook-subtitle-input">Subtitle template</label>
            <input class="input" id="webhook-subtitle-input" name="subtitle" placeholder="{{source}}" value="${escapeHtml(template.subtitle || "")}">
        </div>
        <div class="field">
            <label for="webhook-body-input">Body template</label>
            <textarea class="textarea" id="webhook-body-input" name="body" placeholder="{{message}}">${escapeHtml(template.body || "")}</textarea>
        </div>
        <div class="field">
            <label for="webhook-tags-input">Tags template</label>
            <input class="input" id="webhook-tags-input" name="tags" placeholder="deploy, {{service}}" value="${escapeHtml(template.tags || "")}">
        </div>
        <div class="webhook-form-grid">
            <div class="field">
                <label for="webhook-priority-input">Priority</label>
                <select class="select" id="webhook-priority-input" name="priority">
                    <option value="" ${template.priority ? "" : "selected"}>Default</option>
                    <option value="1" ${Number(template.priority) === 1 ? "selected" : ""}>Low</option>
                    <option value="2" ${Number(template.priority) === 2 ? "selected" : ""}>Normal</option>
                    <option value="3" ${Number(template.priority) === 3 ? "selected" : ""}>Urgent</option>
                </select>
            </div>
            <div class="field">
                <label for="webhook-ttl-input">TTL</label>
                <select class="select" id="webhook-ttl-input" name="ttl">
                    <option value="" ${template.ttl ? "" : "selected"}>No expiry</option>
                    <option value="3600" ${Number(template.ttl) === 3600 ? "selected" : ""}>1h</option>
                    <option value="21600" ${Number(template.ttl) === 21600 ? "selected" : ""}>6h</option>
                    <option value="86400" ${Number(template.ttl) === 86400 ? "selected" : ""}>24h</option>
                    <option value="604800" ${Number(template.ttl) === 604800 ? "selected" : ""}>7d</option>
                    <option value="2592000" ${Number(template.ttl) === 2592000 ? "selected" : ""}>30d</option>
                </select>
            </div>
        </div>
    `;
}

function renderToast() {
    if (!state.toast) {
        toastRoot.innerHTML = "";
        return;
    }

    toastRoot.innerHTML = `
        <div class="toast toast-${state.toast.tone}">
            ${escapeHtml(state.toast.message)}
        </div>
    `;
}

function renderModal() {
    if (!state.modal) {
        modalRoot.innerHTML = "";
        return;
    }

    if (state.modal.type === "create-topic") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Create topic</h3>
                        <p>Set the topic name, visibility, and optional password.</p>
                    </header>
                    <form id="create-topic-modal-form">
                        <div class="modal-body">
                            ${state.modal.error ? `<div class="error-text">${escapeHtml(state.modal.error)}</div>` : ""}
                            <div class="field">
                                <label for="modal-topic-name">Topic name</label>
                                <input class="input mono" id="modal-topic-name" name="name" placeholder="alerts.critical" required>
                            </div>
                            <div class="field">
                                <label for="modal-topic-visibility">Visibility</label>
                                <select class="select" id="modal-topic-visibility" name="visibility">
                                    <option value="open">Open</option>
                                    <option value="protected" selected>Protected</option>
                                    <option value="private">Private</option>
                                </select>
                            </div>
                            <div class="field">
                                <label for="modal-topic-password">Password</label>
                                <input class="input" id="modal-topic-password" name="password" type="password" placeholder="optional password">
                            </div>
                        </div>
                        <footer class="modal-footer">
                            <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                            <button class="btn btn-primary" type="submit">Create</button>
                        </footer>
                    </form>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "password") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Topic password</h3>
                        <p>Access to <span class="mono">/${escapeHtml(state.modal.topicName)}</span> requires a topic password.</p>
                    </header>
                    <form id="topic-password-form">
                        <div class="modal-body">
                            ${state.modal.errorMessage ? `<div class="error-text">${escapeHtml(state.modal.errorMessage)}</div>` : ""}
                            <div class="field">
                                <label for="topic-password-input">Password</label>
                                <input class="input" id="topic-password-input" name="password" type="password" placeholder="topic password" required>
                            </div>
                        </div>
                        <footer class="modal-footer">
                            <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                            <button class="btn btn-primary" type="submit">Unlock</button>
                        </footer>
                    </form>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "delete-topic") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Delete topic</h3>
                        <p>This permanently removes <span class="mono">/${escapeHtml(state.modal.topicName)}</span> and its stored messages.</p>
                    </header>
                    <footer class="modal-footer">
                        <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                        <button class="btn btn-danger" type="button" data-action="confirm-delete-topic">Delete</button>
                    </footer>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "subscribe-topic") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Subscribe to topic</h3>
                        <p>Enter the name of a topic to subscribe.</p>
                    </header>
                    <form id="subscribe-topic-form">
                        <div class="modal-body">
                            <div class="field">
                                <label for="subscribe-topic-input">Topic name</label>
                                <input class="input mono" id="subscribe-topic-input" name="topicName" placeholder="my-topic" autocomplete="off" required>
                            </div>
                        </div>
                        <footer class="modal-footer">
                            <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                            <button class="btn btn-primary" type="submit">Subscribe</button>
                        </footer>
                    </form>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "change-password") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Change password</h3>
                    </header>
                    <form id="change-password-form">
                        <div class="modal-body">
                            ${state.modal.error ? `<div class="error-text">${escapeHtml(state.modal.error)}</div>` : ""}
                            <div class="field">
                                <label for="current-password">Current password</label>
                                <input class="input" id="current-password" name="currentPassword" type="password" placeholder="Current password" required minlength="6">
                            </div>
                            <div class="field">
                                <label for="new-password">New password</label>
                                <input class="input" id="new-password" name="password" type="password" placeholder="New password" required minlength="8">
                            </div>
                            <div class="field">
                                <label for="confirm-password">Confirm password</label>
                                <input class="input" id="confirm-password" name="confirmPassword" type="password" placeholder="Confirm new password" required minlength="8">
                            </div>
                        </div>
                        <footer class="modal-footer">
                            <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                            <button class="btn btn-primary" type="submit">Update</button>
                        </footer>
                    </form>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "new-token") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Create token</h3>
                        <p>Creates a new token for your account.</p>
                    </header>
                    <form id="create-token-form">
                        <div class="modal-body">
                            ${state.modal.error ? `<div class="error-text">${escapeHtml(state.modal.error)}</div>` : ""}
                            <div class="field">
                                <label for="token-label-input">Label</label>
                                <input class="input" id="token-label-input" name="label" placeholder="dashboard automation" required>
                            </div>
                        </div>
                        <footer class="modal-footer">
                            <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                            <button class="btn btn-primary" type="submit">Create</button>
                        </footer>
                    </form>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "token-created") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Token created</h3>
                        <p>Copy your token now. It won't be shown again.</p>
                    </header>
                    <div class="modal-body">
                        <div class="field">
                            <label>Token for "${escapeHtml(state.modal.label)}"</label>
                            <div class="token-created-value">
                                <input class="input mono" id="created-token-value" value="${escapeHtml(state.modal.token)}" readonly>
                                <button class="btn btn-primary btn-small" type="button" data-action="copy-created-token">Copy</button>
                            </div>
                        </div>
                    </div>
                    <footer class="modal-footer">
                        <button class="btn btn-outline" type="button" data-action="close-modal">Done</button>
                    </footer>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "revoke-token") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Revoke token</h3>
                        <p>Revoke token <span class="mono">${escapeHtml(truncateId(state.modal.tokenID))}</span>? This cannot be undone.</p>
                    </header>
                    <footer class="modal-footer">
                        <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                        <button class="btn btn-danger" type="button" data-action="confirm-revoke-token">Revoke</button>
                    </footer>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "new-webhook") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Create webhook</h3>
                        <p>Template fields can read JSON paths with {{field.name}} placeholders.</p>
                    </header>
                    <form id="create-webhook-form">
                        <div class="modal-body">
                            ${state.modal.error ? `<div class="error-text">${escapeHtml(state.modal.error)}</div>` : ""}
                            ${renderWebhookFormFields()}
                        </div>
                        <footer class="modal-footer">
                            <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                            <button class="btn btn-primary" type="submit">Create</button>
                        </footer>
                    </form>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "edit-webhook") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Edit webhook</h3>
                        <p>Updates the template used for future webhook deliveries.</p>
                    </header>
                    <form id="edit-webhook-form">
                        <div class="modal-body">
                            ${state.modal.error ? `<div class="error-text">${escapeHtml(state.modal.error)}</div>` : ""}
                            ${renderWebhookFormFields(state.modal.template)}
                        </div>
                        <footer class="modal-footer">
                            <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                            <button class="btn btn-primary" type="submit">Update</button>
                        </footer>
                    </form>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "webhook-created") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Webhook created</h3>
                        <p>Copy your webhook URL now. The token won't be shown again.</p>
                    </header>
                    <div class="modal-body">
                        <div class="field">
                            <label>Webhook URL for /${escapeHtml(state.modal.topicName)}</label>
                            <div class="token-created-value">
                                <input class="input mono" id="created-webhook-url" value="${escapeHtml(state.modal.url)}" readonly>
                                <button class="btn btn-primary btn-small" type="button" data-action="copy-created-webhook">Copy</button>
                            </div>
                        </div>
                    </div>
                    <footer class="modal-footer">
                        <button class="btn btn-outline" type="button" data-action="close-modal">Done</button>
                    </footer>
                </section>
            </div>
        `;
    }

    if (state.modal.type === "delete-webhook") {
        modalRoot.innerHTML = `
            <div class="modal-overlay">
                <section class="modal">
                    <header class="modal-header">
                        <h3>Delete webhook</h3>
                        <p>Delete webhook <span class="mono">${escapeHtml(truncateId(state.modal.webhookID))}</span>? Existing webhook URLs for it will stop working.</p>
                    </header>
                    <footer class="modal-footer">
                        <button class="btn btn-outline" type="button" data-action="close-modal">Cancel</button>
                        <button class="btn btn-danger" type="button" data-action="confirm-delete-webhook">Delete</button>
                    </footer>
                </section>
            </div>
        `;
    }

    bindModalEvents();
}

function render() {
    if (!hasSession()) {
        renderAuth();
    } else {
        renderAppShell();
    }
    renderModal();
    renderToast();
}

function bindAppEvents() {
    app.querySelectorAll("[data-tab]").forEach((button) => {
        button.addEventListener("click", async () => {
            const nextTab = button.dataset.tab;
            state.currentTab = nextTab;
            if (nextTab === "account" && state.token && !state.tokensLoaded) {
                await loadTokens();
            }
            render();
        });
    });

    app.querySelectorAll("[data-topic]").forEach((button) => {
        button.addEventListener("click", async () => {
            await selectTopic(button.dataset.topic);
        });
    });

    app.querySelectorAll("[data-action='logout']").forEach((button) => {
        button.addEventListener("click", logout);
    });

    app.querySelectorAll("[data-action='refresh']").forEach((button) => {
        button.addEventListener("click", async () => {
            if (state.user?.role === "admin") {
                await loadTopics();
            }
            if (state.currentTopicName) {
                await selectTopic(state.currentTopicName);
            } else {
                render();
            }
            setToast("Dashboard refreshed", "success");
        });
    });

    app.querySelectorAll("[data-action='subscribe-topic']").forEach((button) => {
        button.addEventListener("click", () => {
            openModal({ type: "subscribe-topic" });
        });
    });

    app.querySelectorAll("[data-action='create-topic']").forEach((button) => {
        button.addEventListener("click", () => {
            openModal({ type: "create-topic", error: "" });
        });
    });

    app.querySelectorAll("[data-action='delete-topic']").forEach((button) => {
        button.addEventListener("click", () => {
            const topic = currentTopic();
            if (!topic) return;
            openModal({ type: "delete-topic", topicName: topic.name });
        });
    });

    app.querySelectorAll("[data-action='unsubscribe-topic']").forEach((button) => {
        button.addEventListener("click", async () => {
            const topicName = button.dataset.topicName || state.currentTopicName;
            if (!topicName) return;
            button.disabled = true;
            try {
                await unsubscribeFromTopic(topicName);
            } catch (error) {
                setToast(error.message, "error");
                render();
            }
        });
    });

    app.querySelectorAll("[data-action='change-password']").forEach((button) => {
        button.addEventListener("click", () => {
            openModal({ type: "change-password", error: "" });
        });
    });

    app.querySelectorAll("[data-action='enable-notifications']").forEach((button) => {
        button.addEventListener("click", enablePushFromAccount);
    });

    app.querySelectorAll("[data-action='new-token']").forEach((button) => {
        button.addEventListener("click", () => {
            openModal({ type: "new-token", error: "" });
        });
    });

    app.querySelectorAll("[data-action='revoke-token']").forEach((button) => {
        button.addEventListener("click", () => {
            openModal({ type: "revoke-token", tokenID: button.dataset.tokenId });
        });
    });

    app.querySelectorAll("[data-action='new-webhook']").forEach((button) => {
        button.addEventListener("click", () => {
            openModal({ type: "new-webhook", error: "" });
        });
    });

    app.querySelectorAll("[data-action='edit-webhook']").forEach((button) => {
        button.addEventListener("click", () => {
            const topic = currentTopic();
            const webhook = (state.webhooksByTopic[topic?.name] || [])
                .find((item) => item.id === button.dataset.webhookId);
            if (!webhook) return;
            openModal({
                type: "edit-webhook",
                webhookID: webhook.id,
                template: webhook.template || {},
                error: "",
            });
        });
    });

    app.querySelectorAll("[data-action='delete-webhook']").forEach((button) => {
        button.addEventListener("click", () => {
            openModal({ type: "delete-webhook", webhookID: button.dataset.webhookId });
        });
    });

    const publishForm = app.querySelector("#publish-form");
    if (publishForm) {
        publishForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const formElement = event.currentTarget;
            try {
                await publishCurrentTopic(new FormData(formElement));
                formElement.reset();
            } catch (error) {
                setToast(error.message, "error");
            }
        });
    }

}

function bindModalEvents() {
    modalRoot.querySelectorAll("[data-action='close-modal']").forEach((button) => {
        button.addEventListener("click", closeModal);
    });

    const createTopicForm = modalRoot.querySelector("#create-topic-modal-form");
    if (createTopicForm) {
        createTopicForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const formElement = event.currentTarget;
            try {
                await createTopic(new FormData(formElement));
            } catch (error) {
                state.modal.error = error.message;
                renderModal();
            }
        });
    }

    const changePasswordForm = modalRoot.querySelector("#change-password-form");
    if (changePasswordForm) {
        changePasswordForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            const currentPassword = form.get("currentPassword");
            const password = form.get("password");
            const confirmPassword = form.get("confirmPassword");
            if (password !== confirmPassword) {
                state.modal.error = "Passwords do not match";
                renderModal();
                return;
            }
            try {
                await api("PATCH", `/users/${encodeURIComponent(state.user.username)}`, {
                    body: {
                        currentPassword,
                        password,
                    },
                });
                closeModal();
                setToast("Password updated", "success");
            } catch (error) {
                state.modal.error = error.message;
                renderModal();
            }
        });
    }

    const subscribeTopicForm = modalRoot.querySelector("#subscribe-topic-form");
    if (subscribeTopicForm) {
        subscribeTopicForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const topicName = new FormData(event.currentTarget).get("topicName").trim();
            if (!topicName) return;
            closeModal();
            await selectTopic(topicName);
        });
    }

    const passwordForm = modalRoot.querySelector("#topic-password-form");
    if (passwordForm) {
        passwordForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const formElement = event.currentTarget;
            const password = new FormData(formElement).get("password");
            const topicName = state.modal.topicName;
            const action = state.modal.onSuccess;
            state.topicPasswords[topicName] = password;
            saveTopicPasswords();

            try {
                closeModal();
                await action();
            } catch (error) {
                delete state.topicPasswords[topicName];
                saveTopicPasswords();
                openPasswordModal(topicName, action, error.status === 403 ? "Wrong password" : error.message);
            }
        });
    }

    const deleteTopicButton = modalRoot.querySelector("[data-action='confirm-delete-topic']");
    if (deleteTopicButton) {
        deleteTopicButton.addEventListener("click", async () => {
            try {
                await removeCurrentTopic();
            } catch (error) {
                setToast(error.message, "error");
            }
        });
    }

    const createTokenForm = modalRoot.querySelector("#create-token-form");
    if (createTokenForm) {
        createTokenForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const formElement = event.currentTarget;
            try {
                await createToken(new FormData(formElement));
            } catch (error) {
                state.modal.error = error.message;
                renderModal();
            }
        });
    }

    const revokeTokenButton = modalRoot.querySelector("[data-action='confirm-revoke-token']");
    if (revokeTokenButton) {
        revokeTokenButton.addEventListener("click", async () => {
            try {
                await revokeToken(state.modal.tokenID);
            } catch (error) {
                setToast(error.message, "error");
            }
        });
    }

    const copyCreatedToken = modalRoot.querySelector("[data-action='copy-created-token']");
    if (copyCreatedToken) {
        copyCreatedToken.addEventListener("click", async () => {
            try {
                const input = document.getElementById("created-token-value");
                await navigator.clipboard.writeText(input.value);
                setToast("Token copied", "success");
            } catch {
                setToast("Clipboard unavailable", "error");
            }
        });
    }

    const createWebhookForm = modalRoot.querySelector("#create-webhook-form");
    if (createWebhookForm) {
        createWebhookForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const formElement = event.currentTarget;
            try {
                await createWebhook(new FormData(formElement));
            } catch (error) {
                state.modal.error = error.message;
                renderModal();
            }
        });
    }

    const editWebhookForm = modalRoot.querySelector("#edit-webhook-form");
    if (editWebhookForm) {
        editWebhookForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const formElement = event.currentTarget;
            try {
                await updateWebhook(state.modal.webhookID, new FormData(formElement));
            } catch (error) {
                state.modal.error = error.message;
                renderModal();
            }
        });
    }

    const deleteWebhookButton = modalRoot.querySelector("[data-action='confirm-delete-webhook']");
    if (deleteWebhookButton) {
        deleteWebhookButton.addEventListener("click", async () => {
            try {
                await deleteWebhook(state.modal.webhookID);
            } catch (error) {
                setToast(error.message, "error");
            }
        });
    }

    const copyCreatedWebhook = modalRoot.querySelector("[data-action='copy-created-webhook']");
    if (copyCreatedWebhook) {
        copyCreatedWebhook.addEventListener("click", async () => {
            try {
                const input = document.getElementById("created-webhook-url");
                await navigator.clipboard.writeText(input.value);
                setToast("Webhook URL copied", "success");
            } catch {
                setToast("Clipboard unavailable", "error");
            }
        });
    }
}

async function initialize() {
    try {
        if (state.token) {
            await bootstrapAuthenticatedSession();
        } else {
            render();
        }
    } catch (error) {
        clearSession();
        render();
        setToast(`Session expired: ${error.message}`, "error");
    }
}

initialize();
