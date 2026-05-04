export function escapeHtml(value) {
    return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
}

export function encodePath(value) {
    return encodeURIComponent(value);
}

export function safeJsonParse(text) {
    try {
        return JSON.parse(text);
    } catch {
        return null;
    }
}

export function towerMark(size = 20) {
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

export function icon(name) {
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

export function visibilityBadge(visibility) {
    const value = visibility || "unknown";
    const className = {
        open: "badge-open",
        protected: "badge-protected",
        private: "badge-private",
    }[value] || "badge-off";

    return `<span class="badge ${className}">${escapeHtml(value)}</span>`;
}

export function visibilityIcon(visibility) {
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

export function priorityClass(priority) {
    const p = Number(priority);
    if (p >= 3) return "priority-urgent";
    if (p <= 1) return "priority-low";
    return "priority-default";
}

export function formatDate(value) {
    if (!value) return "—";
    return new Date(value).toLocaleDateString(undefined, {
        year: "numeric",
        month: "short",
        day: "numeric",
    });
}

export function formatDateTime(value) {
    if (!value) return "—";
    return new Date(value).toLocaleString(undefined, {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
    });
}

export function truncateId(value) {
    if (!value) return "—";
    return value.length > 12 ? `${value.slice(0, 12)}…` : value;
}

export function maskToken(value) {
    if (!value) return "—";
    return value.length > 16 ? `${value.slice(0, 10)}••••••${value.slice(-6)}` : value;
}
