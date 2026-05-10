(function () {
    const here = location.pathname.split("/").pop() || "index.html";
    document.querySelectorAll(".sidebar a").forEach((link) => {
        const target = link.getAttribute("href");
        if (target === here || (here === "" && target === "index.html")) {
            link.classList.add("active");
        }
    });

    document.querySelectorAll("pre").forEach((pre) => {
        if (pre.querySelector(".copy-btn")) return;
        const btn = document.createElement("button");
        btn.className = "copy-btn";
        btn.type = "button";
        btn.textContent = "copy";
        btn.addEventListener("click", () => {
            const code = pre.querySelector("code")?.innerText ?? pre.innerText;
            navigator.clipboard.writeText(code).then(() => {
                btn.textContent = "copied";
                btn.classList.add("copied");
                setTimeout(() => {
                    btn.textContent = "copy";
                    btn.classList.remove("copied");
                }, 1400);
            });
        });
        pre.appendChild(btn);
    });

    document.querySelectorAll(".tabs").forEach((root) => {
        const panels = Array.from(root.querySelectorAll(":scope > .tab-panel"));
        if (panels.length === 0) return;
        const bar = document.createElement("div");
        bar.className = "tab-bar";
        panels.forEach((panel, idx) => {
            const label = panel.dataset.label || `Tab ${idx + 1}`;
            const btn = document.createElement("button");
            btn.type = "button";
            btn.className = "tab-btn";
            btn.textContent = label;
            btn.addEventListener("click", () => {
                root.querySelectorAll(".tab-btn").forEach((b) => b.classList.remove("active"));
                panels.forEach((p) => p.classList.remove("active"));
                btn.classList.add("active");
                panel.classList.add("active");
            });
            bar.appendChild(btn);
            if (idx === 0) {
                btn.classList.add("active");
                panel.classList.add("active");
            }
        });
        root.insertBefore(bar, panels[0]);
    });

    const toggle = document.querySelector(".menu-toggle");
    const sidebar = document.querySelector(".sidebar");
    let scrim = null;
    if (toggle && sidebar) {
        const close = () => {
            sidebar.classList.remove("open");
            if (scrim) { scrim.remove(); scrim = null; }
        };
        toggle.addEventListener("click", () => {
            const isOpen = sidebar.classList.toggle("open");
            if (isOpen) {
                scrim = document.createElement("div");
                scrim.className = "scrim";
                scrim.addEventListener("click", close);
                document.body.appendChild(scrim);
            } else if (scrim) {
                scrim.remove();
                scrim = null;
            }
        });
        sidebar.querySelectorAll("a").forEach((a) => a.addEventListener("click", close));
    }
})();
