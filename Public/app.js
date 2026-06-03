import { state, hasSession, clearSession } from "./state.js";
import { api } from "./api.js";
import { renderAuth, logout, bootstrapAuthenticatedSession } from "./auth.js";
import {
    app,
    setRenderer,
    render,
    setToast,
    openModal,
    closeModal,
    setActiveModalError,
    initModalHandlers,
} from "./ui.js";
import {
    renderAppShell,
    selectTopic,
    loadTopics,
    loadTokens,
    createTopic,
    removeCurrentTopic,
    createToken,
    revokeToken,
    createWebhook,
    updateWebhook,
    deleteWebhook,
    createShare,
    updateShare,
    rotateShare,
    deleteShare,
    publishCurrentTopic,
} from "./topics.js";
import { enablePushFromAccount, unsubscribeFromTopic, watchNotificationPermission } from "./webpush.js";

async function handleModalSubmit(type, formData) {
    switch (type) {
    case "create-topic":
        return createTopic(formData);
    case "subscribe-topic": {
        const topicName = formData.get("topicName").trim();
        if (!topicName) return;
        closeModal();
        await selectTopic(topicName);
        return;
    }
    case "change-password": {
        const currentPassword = formData.get("currentPassword");
        const password = formData.get("password");
        const confirmPassword = formData.get("confirmPassword");
        if (password !== confirmPassword) {
            setActiveModalError("Passwords do not match");
            return;
        }
        try {
            await api("PATCH", `/users/${encodeURIComponent(state.user.username)}`, {
                body: { currentPassword, password },
            });
            closeModal();
            setToast("Password updated", "success");
        } catch (error) {
            setActiveModalError(error.message);
        }
        return;
    }
    case "new-token":
        return createToken(formData);
    case "new-webhook":
        return createWebhook(formData);
    case "edit-webhook":
        return updateWebhook(state.modal.webhookID, formData);
    case "new-share":
        return createShare(formData);
    case "edit-share":
        return updateShare(state.modal.shareID, formData);
    }
}

async function handleModalAction(action) {
    try {
        if (action === "confirm-delete-topic") {
            await removeCurrentTopic();
        } else if (action === "confirm-revoke-token") {
            await revokeToken(state.modal.tokenID);
        } else if (action === "confirm-delete-webhook") {
            await deleteWebhook(state.modal.webhookID);
        } else if (action === "confirm-rotate-share") {
            await rotateShare(state.modal.shareID);
        } else if (action === "confirm-delete-share") {
            await deleteShare(state.modal.shareID);
        }
    } catch (error) {
        setToast(error.message, "error");
    }
}

function findCurrentShare(shareID) {
    const topic = state.topics.find((t) => t.name === state.currentTopicName);
    if (!topic) return null;
    const share = (state.sharesByTopic[topic.name] || []).find((item) => item.id === shareID);
    if (!share) return null;
    return { topic, share };
}

const appActions = {
    "logout": () => logout(),
    "subscribe-topic": () => openModal({ type: "subscribe-topic" }),
    "create-topic": () => openModal({ type: "create-topic" }),
    "change-password": () => openModal({ type: "change-password" }),
    "new-token": () => openModal({ type: "new-token" }),
    "new-webhook": () => openModal({ type: "new-webhook" }),
    "new-share": () => {
        const topic = state.topics.find((t) => t.name === state.currentTopicName);
        if (!topic) return;
        openModal({ type: "new-share", topicName: topic.name });
    },
    "edit-share": (button) => {
        const found = findCurrentShare(button.dataset.shareId);
        if (!found) return;
        openModal({
            type: "edit-share",
            shareID: found.share.id,
            topicName: found.topic.name,
            share: found.share,
        });
    },
    "rotate-share": (button) => {
        const found = findCurrentShare(button.dataset.shareId);
        if (!found) return;
        openModal({
            type: "rotate-share",
            shareID: found.share.id,
            shareLabel: found.share.label || "(no label)",
        });
    },
    "delete-share": (button) => {
        const found = findCurrentShare(button.dataset.shareId);
        if (!found) return;
        openModal({
            type: "delete-share",
            shareID: found.share.id,
            shareLabel: found.share.label || "(no label)",
        });
    },
    "enable-notifications": () => enablePushFromAccount(),
    "refresh": async () => {
        if (state.user?.role === "admin") {
            await loadTopics();
        }
        if (state.currentTopicName) {
            await selectTopic(state.currentTopicName);
        } else {
            render();
        }
        setToast("Dashboard refreshed", "success");
    },
    "delete-topic": () => {
        const topic = state.topics.find((t) => t.name === state.currentTopicName);
        if (!topic) return;
        openModal({ type: "delete-topic", topicName: topic.name });
    },
    "unsubscribe-topic": async (button) => {
        const topicName = button.dataset.topicName || state.currentTopicName;
        if (!topicName) return;
        button.disabled = true;
        try {
            await unsubscribeFromTopic(topicName);
        } catch (error) {
            setToast(error.message, "error");
            render();
        }
    },
    "revoke-token": (button) => {
        openModal({ type: "revoke-token", tokenID: button.dataset.tokenId });
    },
    "edit-webhook": (button) => {
        const topic = state.topics.find((t) => t.name === state.currentTopicName);
        const webhook = (state.webhooksByTopic[topic?.name] || [])
            .find((item) => item.id === button.dataset.webhookId);
        if (!webhook) return;
        openModal({
            type: "edit-webhook",
            webhookID: webhook.id,
            template: webhook.template || {},
        });
    },
    "delete-webhook": (button) => {
        openModal({ type: "delete-webhook", webhookID: button.dataset.webhookId });
    },
    "toggle-nav": () => {
        state.navOpen = !state.navOpen;
        render();
    },
};

function initAppEvents() {
    app.addEventListener("click", async (event) => {
        const navRowClick = event.target.closest(".mobile-nav-row");
        const navWillClose = !!(navRowClick && app.contains(navRowClick) && state.navOpen);
        if (navWillClose) state.navOpen = false;
        const renderClosedNav = () => {
            if (navWillClose) render();
        };

        const mobileViewButton = event.target.closest("button[data-mobile-view]");
        if (mobileViewButton && app.contains(mobileViewButton)) {
            const nextView = mobileViewButton.dataset.mobileView;
            if (nextView === state.mobileView) {
                renderClosedNav();
                return;
            }
            state.mobileView = nextView;
            render();
            return;
        }

        const railTabButton = event.target.closest("[data-rail-tab]");
        if (railTabButton && app.contains(railTabButton)) {
            const nextRail = railTabButton.dataset.railTab;
            if (nextRail === state.railTab) {
                renderClosedNav();
                return;
            }
            state.railTab = nextRail;
            render();
            return;
        }

        const tabButton = event.target.closest("[data-tab]");
        if (tabButton && app.contains(tabButton)) {
            const nextTab = tabButton.dataset.tab;
            if (nextTab === state.currentTab) {
                renderClosedNav();
                return;
            }
            state.currentTab = nextTab;
            if (nextTab === "account" && state.token && !state.tokensLoaded) {
                await loadTokens();
            }
            render();
            return;
        }

        const topicButton = event.target.closest("[data-topic]");
        if (topicButton && app.contains(topicButton)) {
            if (topicButton.dataset.topic === state.currentTopicName) {
                renderClosedNav();
                return;
            }
            await selectTopic(topicButton.dataset.topic);
            return;
        }

        const actionButton = event.target.closest("[data-action]");
        if (actionButton && app.contains(actionButton)) {
            const handler = appActions[actionButton.dataset.action];
            if (handler) {
                await handler(actionButton);
                return;
            }
        }

        renderClosedNav();
    });

    app.addEventListener("submit", async (event) => {
        const form = event.target.closest("#publish-form");
        if (!form) return;
        event.preventDefault();
        try {
            await publishCurrentTopic(new FormData(form));
            form.reset();
        } catch (error) {
            setToast(error.message, "error");
        }
    });
}

async function initialize() {
    setRenderer((root) => {
        if (!hasSession()) {
            renderAuth(root);
        } else {
            renderAppShell(root, () => {});
        }
    });
    initModalHandlers({
        onSubmit: handleModalSubmit,
        onAction: handleModalAction,
    });
    initAppEvents();
    watchNotificationPermission();
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
