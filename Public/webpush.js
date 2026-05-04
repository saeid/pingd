import { state, persistWebPushDevice } from "./state.js";
import { encodePath, escapeHtml, safeJsonParse } from "./lib.js";
import { api } from "./api.js";
import { setToast, render } from "./ui.js";

export function supportsWebPush() {
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

export function showInstallHintIfNeeded() {
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

export function prefetchPushPermission() {
    if (!supportsWebPush() || !window.isSecureContext || Notification.permission !== "default") {
        return Promise.resolve(Notification.permission);
    }
    return Notification.requestPermission().catch(() => Notification.permission);
}

export async function enablePush({ requestPermission = true } = {}) {
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

export async function restorePush() {
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

export async function enablePushFromAccount() {
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

export async function subscribeToTopic(topicName, { promptPermission = true } = {}) {
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

export async function unsubscribeFromTopic(topicName) {
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

export function notificationStatus() {
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

export function renderNotificationPanel() {
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
