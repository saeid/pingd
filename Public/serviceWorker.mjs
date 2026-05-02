self.addEventListener("install", (event) => {
    event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
    event.waitUntil(self.clients.claim());
});

function readPushPayload(event) {
    if (!event.data) {
        return {};
    }

    try {
        return event.data.json();
    } catch {
        try {
            return { notification: { body: event.data.text() } };
        } catch {
            return {};
        }
    }
}

self.addEventListener("push", (event) => {
    event.waitUntil((async () => {
        const data = readPushPayload(event);
        const notification = data.notification ?? {};
        const messageData = data.data ?? {};
        const title = String(notification.title || messageData.topic || "Pingd");
        const body = String(notification.body || data.body || "New message");

        await self.registration.showNotification(title, {
            body,
            tag: messageData.messageID || messageData.topic || undefined,
            data: messageData,
            renotify: false,
        });
    })());
});

self.addEventListener("notificationclick", (event) => {
    event.notification.close();
    const topic = event.notification.data?.topic;
    const targetURL = topic ? `/?topic=${encodeURIComponent(topic)}` : "/";

    event.waitUntil((async () => {
        const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
        for (const windowClient of windows) {
            if (!("focus" in windowClient)) continue;

            let targetClient = windowClient;
            if ("navigate" in windowClient) {
                try {
                    targetClient = await windowClient.navigate(targetURL) || windowClient;
                } catch {
                    targetClient = windowClient;
                }
            }
            await targetClient.focus();
            return;
        }
        if (self.clients.openWindow) {
            await self.clients.openWindow(targetURL);
        }
    })());
});
