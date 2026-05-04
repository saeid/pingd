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
    publishCurrentTopic,
} from "./topics.js";
import { enablePushFromAccount, unsubscribeFromTopic } from "./webpush.js";

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
        }
    } catch (error) {
        setToast(error.message, "error");
    }
}

const appActions = {
    "logout": () => logout(),
    "subscribe-topic": () => openModal({ type: "subscribe-topic" }),
    "create-topic": () => openModal({ type: "create-topic" }),
    "change-password": () => openModal({ type: "change-password" }),
    "new-token": () => openModal({ type: "new-token" }),
    "new-webhook": () => openModal({ type: "new-webhook" }),
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
};

function initAppEvents() {
    app.addEventListener("click", async (event) => {
        const tabButton = event.target.closest("[data-tab]");
        if (tabButton && app.contains(tabButton)) {
            const nextTab = tabButton.dataset.tab;
            if (nextTab === state.currentTab) return;
            state.currentTab = nextTab;
            if (nextTab === "account" && state.token && !state.tokensLoaded) {
                await loadTokens();
            }
            render();
            return;
        }

        const topicButton = event.target.closest("[data-topic]");
        if (topicButton && app.contains(topicButton)) {
            if (topicButton.dataset.topic === state.currentTopicName) return;
            await selectTopic(topicButton.dataset.topic);
            return;
        }

        const actionButton = event.target.closest("[data-action]");
        if (actionButton && app.contains(actionButton)) {
            const handler = appActions[actionButton.dataset.action];
            if (handler) await handler(actionButton);
        }
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
