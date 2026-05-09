import { state, saveTopicTokens } from "./state.js";
import { escapeHtml, truncateId } from "./lib.js";

export const app = document.getElementById("app");

const toastRoot = document.getElementById("toast-root");
let renderApp = null;

export function setRenderer(renderer) {
    renderApp = renderer;
}

export function render() {
    renderApp?.(app);
    renderToast();
}

export function setToast(message, tone = "default") {
    state.toast = { message, tone };
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => {
        state.toast = null;
        renderToast();
    }, 2600);
    renderToast();
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

function getDialog(type) {
    return document.getElementById(`dialog-${type}`);
}

function fillBindings(dialog, key, value) {
    const elements = dialog.querySelectorAll(`[data-bind='${key}']`);
    const text = value == null ? "" : String(value);
    elements.forEach((element) => {
        if (
            element.tagName === "INPUT" ||
            element.tagName === "TEXTAREA" ||
            element.tagName === "SELECT"
        ) {
            element.value = text;
        } else {
            element.textContent = text;
        }
    });
}

export function setActiveModalError(message) {
    const dialog = document.querySelector("dialog[open]");
    if (!dialog) return;
    const errorElement = dialog.querySelector("[data-bind='error']");
    if (!errorElement) return;
    errorElement.textContent = message || "";
    errorElement.hidden = !message;
}

function populateDialog(type, data) {
    const dialog = getDialog(type);
    if (!dialog) return null;

    const form = dialog.querySelector("form");
    if (form) form.reset();

    const errorElement = dialog.querySelector("[data-bind='error']");
    if (errorElement) {
        errorElement.textContent = "";
        errorElement.hidden = true;
    }

    switch (type) {
    case "topic-token":
        fillBindings(dialog, "topicName", data.topicName);
        if (data.errorMessage && errorElement) {
            errorElement.textContent = data.errorMessage;
            errorElement.hidden = false;
        }
        break;
    case "delete-topic":
        fillBindings(dialog, "topicName", data.topicName);
        break;
    case "revoke-token":
        fillBindings(dialog, "tokenID", truncateId(data.tokenID));
        break;
    case "delete-webhook":
        fillBindings(dialog, "webhookID", truncateId(data.webhookID));
        break;
    case "token-created":
        fillBindings(dialog, "label", data.label);
        fillBindings(dialog, "token", data.token);
        break;
    case "webhook-created":
        fillBindings(dialog, "topicName", data.topicName);
        fillBindings(dialog, "url", data.url);
        break;
    case "edit-webhook": {
        const template = data.template || {};
        form.elements.title.value = template.title || "";
        form.elements.subtitle.value = template.subtitle || "";
        form.elements.body.value = template.body || "";
        form.elements.tags.value = template.tags || "";
        form.elements.priority.value = template.priority ? String(template.priority) : "";
        form.elements.ttl.value = template.ttl ? String(template.ttl) : "";
        break;
    }
    default:
        break;
    }

    return dialog;
}

export function openModal(modal) {
    document.querySelectorAll("dialog[open]").forEach((dialog) => dialog.close());
    state.modal = modal;
    const dialog = populateDialog(modal.type, modal);
    dialog?.showModal();
}

export function closeModal() {
    document.querySelectorAll("dialog[open]").forEach((dialog) => dialog.close());
    state.modal = null;
}

export function openTopicTokenModal(topicName, onSuccess, errorMessage = "") {
    openModal({ type: "topic-token", topicName, onSuccess, errorMessage });
}

async function handleTopicTokenSubmit(formData) {
    const token = formData.get("token").trim();
    const topicName = state.modal.topicName;
    const action = state.modal.onSuccess;
    state.topicTokens[topicName] = token;
    saveTopicTokens();
    try {
        closeModal();
        await action();
    } catch (error) {
        delete state.topicTokens[topicName];
        saveTopicTokens();
        openTopicTokenModal(
            topicName,
            action,
            error.status === 403 ? "Invalid share token" : error.message
        );
    }
}

async function copyInputValue(inputID, successMessage) {
    try {
        const input = document.getElementById(inputID);
        await navigator.clipboard.writeText(input.value);
        setToast(successMessage, "success");
    } catch {
        setToast("Clipboard unavailable", "error");
    }
}

export function initModalHandlers({ onSubmit, onAction }) {
    document.querySelectorAll("dialog").forEach((dialog) => {
        dialog.addEventListener("close", () => {
            state.modal = null;
        });
    });

    document.querySelectorAll("[data-modal-form]").forEach((form) => {
        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            const type = form.dataset.modalForm;
            try {
                if (type === "topic-token") {
                    await handleTopicTokenSubmit(new FormData(form));
                } else {
                    await onSubmit(type, new FormData(form));
                }
            } catch (error) {
                setActiveModalError(error.message);
            }
        });
    });

    document.body.addEventListener("click", async (event) => {
        const actionButton = event.target.closest("[data-action]");
        if (!actionButton) return;
        const dialog = actionButton.closest("dialog");
        if (!dialog) return;

        const action = actionButton.dataset.action;
        if (action === "close-modal") {
            dialog.close();
            return;
        }
        if (action === "copy-created-token") {
            await copyInputValue("created-token-value", "Token copied");
            return;
        }
        if (action === "copy-created-webhook") {
            await copyInputValue("created-webhook-url", "Webhook URL copied");
            return;
        }

        await onAction(action, actionButton);
    });
}
