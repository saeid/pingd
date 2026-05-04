import {
    state,
    currentTopic,
    upsertTopic,
    requestedTopicFromLocation,
    clearRequestedTopicFromLocation,
    saveTopicPasswords,
} from "./state.js";
import {
    escapeHtml,
    encodePath,
    towerMark,
    icon,
    visibilityBadge,
    visibilityIcon,
    priorityClass,
    formatDateTime,
    truncateId,
    maskToken,
} from "./lib.js";
import { api } from "./api.js";
import { subscribeToTopic, renderNotificationPanel } from "./webpush.js";
import {
    setToast,
    render,
    openModal,
    closeModal,
    openPasswordModal,
} from "./ui.js";

function isCurrentSessionToken(tokenValue) {
    if (!state.token || !tokenValue) return false;
    if (tokenValue === state.token) return true;
    return state.token.endsWith(tokenValue.slice(-4)) && tokenValue.startsWith("pgd_****");
}

export async function loadMe() {
    state.user = await api("GET", "/me");
}

export async function loadTopics() {
    state.topics = (await api("GET", "/topics")) || [];
    if (
        state.currentTopicName &&
        !state.topics.some((topic) => topic.name === state.currentTopicName)
    ) {
        state.currentTopicName = null;
    }
}

export async function loadTokens() {
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

export async function loadSubscribedTopics() {
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

export async function loadWebhooks(topicName) {
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

export async function loadTopicStats(topicName) {
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

export async function loadMessages(topicName) {
    state.messagesByTopic[topicName] = await api(
        "GET",
        `/topics/${encodePath(topicName)}/messages`,
        { topicName }
    );
}

export async function handleProtectedAction(topicName, action) {
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

export async function lookupTopicByName(topicName, { subscribe = true, promptPermission = true } = {}) {
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

export async function selectTopic(topicName) {
    await lookupTopicByName(topicName);
}

export async function selectRequestedTopicFromLocation() {
    const topicName = requestedTopicFromLocation();
    if (!topicName || !hasSessionFromState()) return;

    clearRequestedTopicFromLocation();
    await lookupTopicByName(topicName, { promptPermission: false });
}

function hasSessionFromState() {
    return Boolean(state.token || state.guest);
}

export async function createTopic(form) {
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

export async function publishCurrentTopic(form) {
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

export async function removeCurrentTopic() {
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

export async function createToken(form) {
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
    render();
    openModal({ type: "token-created", token: created.token, label: created.label });
}

export async function revokeToken(tokenID) {
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

export async function createWebhook(form) {
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
    render();
    openModal({
        type: "webhook-created",
        token: created.token,
        url: webhookURL(created.token),
        topicName: topic.name,
    });
}

export async function updateWebhook(webhookID, form) {
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

export async function deleteWebhook(webhookID) {
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

export function canManageWebhooks(topic) {
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

export function renderAppShell(app, bindAppEvents) {
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
