import { safeJsonParse } from "./lib.js";

const cachedWebPush = safeJsonParse(localStorage.getItem("pingd_webpush_device") || "");

export const state = {
    token: localStorage.getItem("pingd_token"),
    guest: false,
    user: null,
    topics: [],
    currentTab: "topics",
    currentTopicName: null,
    messagesByTopic: {},
    topicStatsByTopic: {},
    topicTokens: JSON.parse(localStorage.getItem("pingd_topic_tokens") || "{}"),
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

export function hasSession() {
    return Boolean(state.token || state.guest);
}

export function currentTopic() {
    return state.topics.find((topic) => topic.name === state.currentTopicName) || null;
}

export function requestedTopicFromLocation() {
    const topicName = new URLSearchParams(window.location.search).get("topic");
    if (!topicName) return "";

    const normalized = topicName.trim();
    return normalized.length <= 200 ? normalized : "";
}

export function clearRequestedTopicFromLocation() {
    const url = new URL(window.location.href);
    if (!url.searchParams.has("topic")) return;

    url.searchParams.delete("topic");
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
}

export function saveTopicTokens() {
    localStorage.setItem("pingd_topic_tokens", JSON.stringify(state.topicTokens));
}

export function persistWebPushDevice(device, pushToken) {
    if (!device || !pushToken) {
        localStorage.removeItem("pingd_webpush_device");
        return;
    }
    localStorage.setItem("pingd_webpush_device", JSON.stringify({ device, pushToken }));
}

export function persistToken(token) {
    state.token = token;
    localStorage.setItem("pingd_token", token);
}

export function clearSession() {
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

export function upsertTopic(topic) {
    const existing = state.topics.findIndex((item) => item.name === topic.name);
    if (existing >= 0) {
        state.topics[existing] = topic;
    } else {
        state.topics.push(topic);
        state.topics.sort((left, right) => left.name.localeCompare(right.name));
    }
}
