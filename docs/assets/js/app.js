"use strict";

/* =============================================================================
   app.js
   - Theme toggle (localStorage with try/catch)
   - Mobile menu (ESC / outside click close)
   - Active nav highlighting (rAF throttled)
   - Print a single section (hidden iframe; NO popup)
   - Timeline connectors (pure CSS default, JS helper optional)
============================================================================= */

const $  = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => root.querySelectorAll(sel);
const each = (iterable, fn) => Array.from(iterable || []).forEach(fn);

/* ----------------------------------
   PRINT: render ONLY a section in a hidden iframe and call print()
---------------------------------- */
const printSection = (sectionId) => {
    const node = document.getElementById(sectionId);
    if (!node) return;

    const iframe = document.createElement("iframe");
    Object.assign(iframe.style, {
        position: "fixed", right: "0", bottom: "0", width: "0", height: "0", border: "0", visibility: "hidden",
    });
    iframe.setAttribute("aria-hidden", "true");
    document.body.appendChild(iframe);

    const tailwindHref = new URL("/css/tailwind-build.css", location.origin).href;
    const customHref = new URL(
        document.querySelector('link[href$="styles.processed.css"]') ? "/css/styles.processed.css" : "/css/styles.css",
        location.origin
    ).href;

    const safeTitle = (document.title || "Print")
        .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

    const html = `<!doctype html>
<html lang="en-US">
<head>
  <meta charset="utf-8" />
  <title>Print – ${safeTitle}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <link rel="stylesheet" href="${tailwindHref}">
  <link rel="stylesheet" href="${customHref}">
  <style>
    @media print{ @page{ margin:12.7mm; } html,body{ margin:0!important; padding:0!important; } }
    .app-container{ max-width:960px; margin:0 auto; padding:0 22px; }
  </style>
</head>
<body>
  ${node.outerHTML}
</body>
</html>`;

    const doc = iframe.contentDocument || iframe.contentWindow.document;
    doc.open(); doc.write(html); doc.close();

    const onReady = () => {
        try {
            iframe.contentWindow.focus();
            iframe.contentWindow.print();
        } finally {
            setTimeout(() => iframe.remove(), 400);
        }
    };

    if (iframe.contentDocument?.readyState === "complete") {
        setTimeout(onReady, 60);
    } else {
        iframe.addEventListener("load", () => setTimeout(onReady, 60), { once: true });
    }
};

/* ----------------------------------
   THEME
---------------------------------- */
class ThemeManager {
    KEY   = "theme";
    LIGHT = "light";
    DARK  = "dark";

    els = { toggle: null, mobileToggle: null, sun: [], moon: [], labels: [] };

    init() {
        this.cache();
        this.applyInitial();
        this.bind();
    }

    cache() {
        this.els.toggle       = $("#themeToggle");
        this.els.mobileToggle = $("#mobileThemeToggle");
        this.els.sun          = $$(".sun-icon");
        this.els.moon         = $$(".moon-icon");
        this.els.labels       = $$(".theme-label");
    }

    applyInitial() {
        let pref = null;
        try {
            pref = localStorage.getItem(this.KEY);
        } catch (_) {
            // Storage might be disabled; fall through to default light mode.
        }
        // Default to light mode when no preference is stored
        const initial = pref || this.LIGHT;
        this.set(initial);
    }

    bind() {
        this.els.toggle?.addEventListener("click", () => this.toggle());
        this.els.mobileToggle?.addEventListener("click", () => this.toggle());
    }

    set(theme) {
        document.documentElement.setAttribute("data-theme", theme);
        try {
            localStorage.setItem(this.KEY, theme);
        } catch (_) {
            // ignore
        }

        const isDark = theme === this.DARK;
        // In dark mode: show sun icon + "Light" text (to switch to light)
        // In light mode: show moon icon + "Dark" text (to switch to dark)
        each(this.els.sun,  n => (n.style.display = isDark ? "block" : "none"));
        each(this.els.moon, n => (n.style.display = isDark ? "none"  : "block"));
        each(this.els.labels, n => { if (n?.tagName === "SPAN") n.textContent = isDark ? "Light" : "Dark"; });

        [this.els.toggle, this.els.mobileToggle].forEach(b => b?.setAttribute("aria-pressed", String(isDark)));
    }

    toggle() {
        const now = document.documentElement.getAttribute("data-theme");
        this.set(now === this.DARK ? this.LIGHT : this.DARK);
    }
}

/* ----------------------------------
   MOBILE MENU
---------------------------------- */
class MobileMenu {
    isOpen = false;
    hamburger = null;
    menu = null;
    links = [];
    _onKeyDown = null;
    _onDocClick = null;

    init() {
        this.cache();
        if (!this.hamburger || !this.menu) return;
        this.bind();
    }

    cache() {
        this.hamburger = $("#hamburger");
        this.menu      = $("#mobileMenu");
        this.links     = this.menu ? $$(".mobile-menu-link", this.menu) : [];
    }

    bind() {
        this.hamburger.addEventListener("click", (e) => {
            e.preventDefault(); e.stopPropagation(); this.toggle();
        });

        this.menu.addEventListener("click", (e) => {
            const link = e.target.closest(".mobile-menu-link");
            if (!link) return;
            e.preventDefault();
            const id = link.getAttribute("href");
            this.close();
            setTimeout(() => this.scrollTo(id), 200);
        });

        this._onKeyDown = (e) => { if (e.key === "Escape" && this.isOpen) this.close(); };
        this._onDocClick = (e) => {
            if (!this.isOpen) return;
            const t = e.target;
            if (!this.hamburger.contains(t) && !this.menu.contains(t)) this.close();
        };

        document.addEventListener("keydown", this._onKeyDown, { passive: true });
        document.addEventListener("click", this._onDocClick, { passive: true });
        window.addEventListener("beforeunload", () => this.destroy());
    }

    destroy() {
        document.removeEventListener("keydown", this._onKeyDown);
        document.removeEventListener("click", this._onDocClick);
    }

    toggle(){ this.isOpen ? this.close() : this.open(); }

    open(){
        this.isOpen = true;
        this.hamburger.classList.add("active");
        this.menu.classList.add("active");
        this.hamburger.setAttribute("aria-expanded", "true");
        this.menu.setAttribute("aria-hidden", "false");
        document.body.style.overflow = "hidden";
    }

    close(){
        this.isOpen = false;
        this.hamburger.classList.remove("active");
        this.menu.classList.remove("active");
        this.hamburger.setAttribute("aria-expanded", "false");
        this.menu.setAttribute("aria-hidden", "true");
        document.body.style.overflow = "";
    }

    scrollTo(id){
        const target = id && document.querySelector(id);
        if (!target) return;
        const navH = $(".nav-header")?.offsetHeight ?? 0;
        window.scrollTo({ top: target.offsetTop - navH, behavior: "smooth" });
    }

    updateActiveLink(activeId){
        each(this.links, (a) => {
            const active = !!activeId && a.getAttribute("href") === `#${activeId}`;
            a.classList.toggle("active", active);
            a.setAttribute("aria-current", active ? "true" : "false");
        });
    }
}

/* ----------------------------------
   NAV / ACTIVE LINKS (rAF throttled)
---------------------------------- */
class Navigation {
    header = null;
    links = [];
    sections = [];
    mobileMenu = new MobileMenu();

    init() {
        this.cache();
        if (!this.header) return;
        this.mobileMenu.init();
        this.bind();
        this.onScroll(); // initial state
    }

    cache() {
        this.header   = $(".nav-header");
        this.links    = $$(".nav-link");
        this.sections = $$("section[id]");
    }

    bind() {
        $(".nav-links")?.addEventListener("click", (e) => {
            const link = e.target.closest(".nav-link");
            if (!link) return;
            e.preventDefault();
            this.scrollTo(link.getAttribute("href"));
        });

        let rafId = null;
        const onScroll = () => {
            if (rafId) return;
            rafId = requestAnimationFrame(() => { this.onScroll(); rafId = null; });
        };
        window.addEventListener("scroll", onScroll, { passive: true });
        window.addEventListener("beforeunload", () => window.removeEventListener("scroll", onScroll));

        // Print delegation
        document.addEventListener("click", (e) => {
            const btn = e.target.closest("[data-print-section]");
            if (!btn) return;
            e.preventDefault();
            printSection(btn.getAttribute("data-print-section"));
        });
    }

    scrollTo(id) {
        if (!id) return;
        const target = document.querySelector(id);
        if (!target) return;
        const navH = this.header?.offsetHeight ?? 0;
        window.scrollTo({ top: target.offsetTop - navH, behavior: "smooth" });
    }

    onScroll() {
        this.header?.classList.toggle("scrolled", window.scrollY > 100);
        this.updateActive();
    }

    updateActive() {
        const y = window.scrollY + 120;
        let current = null;
        each(this.sections, (sec) => {
            const top = sec.offsetTop, h = sec.offsetHeight;
            if (y >= top && y < top + h) current = sec.id;
        });

        each(this.links, (a) => {
            const active = !!current && a.getAttribute("href") === `#${current}`;
            a.classList.toggle("active", active);
            a.setAttribute("aria-current", active ? "true" : "false");
        });

        this.mobileMenu.updateActiveLink(current);
    }
}

/* ----------------------------------
   Boot
---------------------------------- */
document.addEventListener("DOMContentLoaded", () => {
    try {
        new ThemeManager().init();
        new Navigation().init();
    } catch (err) {
        console.error("Initialization error:", err);
    }
});