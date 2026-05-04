import { state, persistToken, clearSession, hasSession } from "./state.js";
import { escapeHtml, towerMark } from "./lib.js";
import { api } from "./api.js";
import { setToast, render } from "./ui.js";
import {
    prefetchPushPermission,
    restorePush,
    showInstallHintIfNeeded,
} from "./webpush.js";
import { loadMe, loadTopics, loadSubscribedTopics, loadTokens, selectRequestedTopicFromLocation } from "./topics.js";

export async function bootstrapAuthenticatedSession({ syncWebPush = true } = {}) {
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

export async function bootstrapGuestSession() {
    render();
    await selectRequestedTopicFromLocation();
}

export async function handleLogin(form) {
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

export async function handleRegister(form) {
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

export async function logout() {
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

export async function continueAsGuest() {
    clearSession();
    state.guest = true;
    state.authError = "";
    await bootstrapGuestSession();
}

export function renderAuth(app) {
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
