import { state } from "./state.js";
import { safeJsonParse } from "./lib.js";

export async function api(method, path, { body, topicName, headers: extraHeaders } = {}) {
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
