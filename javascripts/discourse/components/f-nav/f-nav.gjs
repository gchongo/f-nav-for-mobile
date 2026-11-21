import Component from "@ember/component";
import { service } from "@ember/service";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import DiscourseURL from "discourse/lib/url";
import DoNotDisturb from "discourse/lib/do-not-disturb";
import EmbedMode from "discourse/lib/embed-mode";
import { getOwner } from "@ember/application";
import FNavItem from "./f-nav-item";

// Core shortens the full-page chat by --footer-nav-height under this class (its own
// PWA bar): on /chat this bar takes that place (scss/mobile/f-nav-root.scss).
const CHAT_FOOTER_CLASS = "footer-nav-visible";

// The html state classes the drawer CSS hangs off (plain class gates — no
// :has(), which has shown rendering differences on some mobile WebKits):
// f-nav-active = the bar is rendered; f-nav-drawer-open = the hamburger
// drawer is open (either panel); f-nav-switcher-top = the chat switcher is
// docked under the navbar (list views). Re-measured on every DOM mutation,
// route change and viewport resize.
const syncHtmlState = () => {
  const html = document.documentElement;
  html.classList.toggle("f-nav-active", !!document.querySelector(".f-nav"));
  html.classList.toggle(
    "f-nav-drawer-open",
    !!document.querySelector(".hamburger-panel .menu-panel.slide-in")
  );
  html.classList.toggle(
    "f-nav-switcher-top",
    !!document.querySelector(".c-navbar__title")
  );
};

// With the bar lifted above the cloak, the bar's own triggers (the ☰ tab and
// the chat-panel button) are the pointer targets when a drawer is open — and
// core's outside-click handler tears the drawer wrapper down INSTANTLY (no
// animation) during pointerdown for any outside target that is not the cloak
// itself. Block that pointerdown from leaving those triggers: their click
// handlers then decide open/close themselves and close through the cloak's
// animated dismiss path (see toggleHamburger / toggleChatPanel) — without
// this, the second tap of either trigger re-opened the drawer instead of
// closing it. The ☰ tab is matched by its data-tab-function attribute, NOT
// by its icon: sites without the JTech icon remap render core icons there,
// so an icon-based match silently never fires on them (cax.do).
document.addEventListener(
  "pointerdown",
  (e) => {
    if (!document.querySelector(".hamburger-panel .menu-panel.slide-in")) {
      return;
    }
    const hamburgerTab = e.target.closest?.(
      '.f-nav .tab[data-tab-function="hamburger"]'
    );
    if (
      hamburgerTab ||
      e.target.closest?.("#f-nav-chat-panel-trigger")
    ) {
      e.stopPropagation();
    }
  },
  true
);

// Measure the top bars' real bottom edge (site header + chat navbar, which
// stack differently per site/theme/device) into --f-nav-top. The chat
// layout's top offsets (the switcher, the composer, the chooser modal, the
// drawer cap) hang off this measured value — core's own --header-offset
// measures unreliably on iOS (dynamic viewport + safe areas can yield 0),
// which made the switcher overlap the navbar and the drawers cover the logo
// bar on phones.
const measureTopBars = () => {
  const header = document.querySelector(".d-header-wrap .d-header");
  const bottom = header ? header.getBoundingClientRect().bottom : 0;
  document.documentElement.style.setProperty(
    "--f-nav-top",
    Math.max(0, Math.round(bottom)) + "px"
  );
};
window.addEventListener("resize", measureTopBars);
window.visualViewport?.addEventListener("resize", measureTopBars);

export default class FNav extends Component {
  @service router;
  @service currentUser;
  @service site;
  @service siteSettings;
  @service topicTrackingState;
  @service sidebarState;

  tabs = settings.f_nav_tabs;

  setChatFooter = false;

  // The scroll listener that used to hide this bar (and the header) after
  // 30px of scrolling down was removed: the bar stays visible at every
  // scroll position. The matching body.f-nav-hidden CSS rules were removed
  // from scss/mobile/f-nav.scss in the same cleanup.
  @action
  teardownChatFooter() {
    if (this.setChatFooter) {
      document.documentElement.classList.remove(CHAT_FOOTER_CLASS);
    }
  }

  get isInChat() {
    const route = this.router.currentRouteName || "";
    return route === "chat" || route.startsWith("chat.");
  }

  // Only ever removes the class it added, so core's PWA bar keeps its own.
  @action
  syncChatFooter() {
    measureTopBars();
    syncHtmlState();
    const classes = document.documentElement.classList;
    if (this.isInChat) {
      if (!classes.contains(CHAT_FOOTER_CLASS)) {
        this.setChatFooter = true;
        classes.add(CHAT_FOOTER_CLASS);
      }
    } else if (this.setChatFooter) {
      this.setChatFooter = false;
      classes.remove(CHAT_FOOTER_CLASS);
    }
  }

  // Computed properties for visibility and states
  get shouldShowNav() {
    return (
      this.currentUser &&
      this.site.mobileView &&
      !EmbedMode.enabled &&
      this.tabs.length
    );
  }

  get canUseChat() {
    return this.currentUser?.has_chat_enabled && this.siteSettings?.chat_enabled;
  }

  get isTopicRoute() {
    return this.router.currentRouteName.startsWith("topic.");
  }

  // DoNotDisturb related computeds
  get isInDoNotDisturbBadge() {
    return this.currentUser.isInDoNotDisturb();
  }

  get doNotDisturbDateTime() {
    const date = this.#getDoNotDisturbDate();
    return date?.getTime();
  }

  get showDoNotDisturbEndDate() {
    return !DoNotDisturb.isEternal(this.currentUser.get("do_not_disturb_until"));
  }

  // Destination computeds
  get homeDestination() {
    return "/";
  }

  get messagesDestination() {
    return `/u/${this.currentUser.username_lower}/messages`;
  }

  get searchDestination() {
    return "/search";
  }

  get notificationsDestination() {
    if (this.currentUser.unseen_reviewable_count) {
      return "/review";
    }
    const base = `/u/${this.currentUser.username_lower}/notifications`;
    return this.currentUser.all_unread_notifications_count 
      ? `${base}?filter=unread` 
      : base;
  }

  get aiBotDestination() {
    return "/discourse-ai/ai-bot/conversations";
  }

  // Private methods
  #getDoNotDisturbDate() {
    const until = this.currentUser.get("do_not_disturb_until");
    if (!until) {
      return null;
    }
    
    const date = new Date(until);
    return date < new Date() ? null : date;
  }

  #handleElementClick(elementId) {
    const element = document.getElementById(elementId);
    element?.click();
  }

  // Navigation actions
  @action
  homeTabRouteSwitcher() {
    this.isTopicRoute ? window.history.back() : DiscourseURL.routeTo("/");
  }

  @action
  toggleHamburger() {
    if (document.querySelector(".hamburger-panel .menu-panel.slide-in")) {
      // Closing (the drawer is still open because the pointerdown blocker
      // below kept core's instant teardown from running on this tap). Core
      // only ANIMATES the dismiss when the closing pointer event lands on
      // the cloak itself — replay the pointer sequence there so the second
      // tap closes with the same slide-down animation as the open.
      const cloak = document.querySelector(".header-cloak");
      if (cloak) {
        const opts = {
          bubbles: true,
          cancelable: true,
          composed: true,
          pointerId: 1,
          pointerType: "touch",
          isPrimary: true,
        };
        cloak.dispatchEvent(new PointerEvent("pointerdown", opts));
        cloak.dispatchEvent(new PointerEvent("pointerup", opts));
        cloak.dispatchEvent(new MouseEvent("click", opts));
        syncHtmlState();
        return;
      }
    }
    // Opening: the site hamburger always shows the main (forum) panel — the
    // chat panel drawer has its own trigger on chat pages (toggleChatPanel).
    this.sidebarState?.setPanel?.("main");
    this.#handleElementClick("toggle-hamburger-menu");
    syncHtmlState();
  }

  // The chat-pages drawer trigger: a dedicated button in the chat switcher
  // (nav.c-footer, before the Starred tab) that opens the chat panel drawer
  // (Search chat / Starred channels / Channels / DMs / Live rooms) — kept
  // separate from the site hamburger, which always shows the forum panel.
  @action
  toggleChatPanel() {
    if (document.querySelector(".hamburger-panel .menu-panel.slide-in")) {
      // Closing. Core only ANIMATES the dismiss when the closing pointer
      // event lands on the cloak itself — any other outside target gets an
      // instant teardown. Replay the pointer sequence on the cloak so the
      // second tap closes with the same slide-down animation as the open.
      const cloak = document.querySelector(".header-cloak");
      if (cloak) {
        const opts = {
          bubbles: true,
          cancelable: true,
          composed: true,
          pointerId: 1,
          pointerType: "touch",
          isPrimary: true,
        };
        cloak.dispatchEvent(new PointerEvent("pointerdown", opts));
        cloak.dispatchEvent(new PointerEvent("pointerup", opts));
        cloak.dispatchEvent(new MouseEvent("click", opts));
        syncHtmlState();
        return;
      }
    }
    // Opening: the chat panel, separated (its sections only), with every
    // section expanded — the sidebar sections remember collapsed state per
    // device, and a collapsed section renders no rows.
    this.sidebarState?.setSeparatedMode?.();
    this.sidebarState._requestedPanelKey = "chat";
    for (const id of ["chat-starred-channels", "chat-channels", "chat-dms"]) {
      try {
        if (this.sidebarState.isSectionCollapsed?.(id)) {
          this.sidebarState.expandSection?.(id);
        }
      } catch (e) {
        // section ids can vary between core versions
      }
    }
    this.#handleElementClick("toggle-hamburger-menu");
    // Sections can still render collapsed for ids the state layer doesn't
    // track (Live rooms = live-rooms-chat) — expand them from the DOM once
    // the drawer rendered.
    const expandStillCollapsed = () => {
      document
        .querySelectorAll(
          ".hamburger-panel .sidebar-section-wrapper:not(.sidebar-section--expanded) .sidebar-section-header"
        )
        .forEach((h) => h.click());
    };
    setTimeout(expandStillCollapsed, 400);
    setTimeout(expandStillCollapsed, 900);
    syncHtmlState();
  }

  // Chat navbar: the back-to-forum link renders the system logo image (the
  // same logo core's own header logo uses), with the light/dark asset
  // swapped per the interface color mode: light mode shows the light logo,
  // dark mode shows the dark logo. Re-synced by the observer flow on every
  // palette switch.
  @action
  setupChatNavbarLogo() {
    if (!this.isInChat) return;
    const link = document.querySelector(".back-to-forum");
    if (!link || link.dataset.fnavLogo) return;
    let logo = null,
      logoDark = null;
    try {
      const pre = document.getElementById("data-preloaded");
      const data = JSON.parse(pre.textContent);
      let ss = data.siteSettings;
      if (typeof ss === "string") {
        ss = JSON.parse(ss);
      }
      logo = ss?.logo || ss?.site_logo_url || null;
      logoDark = ss?.logo_dark || ss?.site_logo_dark_url || logo || null;
    } catch (e) {
      // no preloaded data — leave the link as core rendered it
    }
    if (!logo) return;
    link.dataset.fnavLogo = "true";
    link.classList.add("f-nav-chat-logo");
    const darkMode = !!this.#interfaceColor()?.colorModeIsDark;
    link.innerHTML = `<img class="logo-mobile" src="${
      darkMode && logoDark ? logoDark : logo
    }" alt="">`;
  }

  // Keeps the chat navbar logo's asset in step with the color mode: the
  // palette switch doesn't reload the page, so the observer flow re-runs
  // this and swaps the light/dark asset per the current mode.
  @action
  syncChatNavbarLogoMode() {
    const img = document.querySelector('.back-to-forum .logo-mobile');
    if (!img) return;
    let logo = null,
      logoDark = null;
    try {
      const pre = document.getElementById("data-preloaded");
      const data = JSON.parse(pre.textContent);
      let ss = data.siteSettings;
      if (typeof ss === "string") {
        ss = JSON.parse(ss);
      }
      logo = ss?.logo || ss?.site_logo_url || null;
      logoDark = ss?.logo_dark || ss?.site_logo_dark_url || logo || null;
    } catch (e) {
      return;
    }
    const darkMode = !!this.#interfaceColor()?.colorModeIsDark;
    img.src = darkMode && logoDark ? logoDark : logo || img.src;
  }

  #interfaceColor() {
    try {
      return getOwner(this).lookup("service:interface-color") ?? null;
    } catch (e) {
      return null;
    }
  }

  @action
  ensureChatPanelTrigger() {
    measureTopBars();
    syncHtmlState();
    this.setupChatNavbarLogo();
    this.syncChatNavbarLogoMode();
    if (!this.isInChat) {
      document.getElementById("f-nav-chat-panel-trigger")?.remove();
      return;
    }
    // Keep the trigger's active state in sync: blue while the chat panel
    // drawer is the open one (core's own tabs turn --active the same way),
    // gray when it's closed or the site hamburger took over. The observer
    // re-runs this on every drawer mount/unmount, so outside-click closes
    // stay in sync too.
    let btn = document.getElementById("f-nav-chat-panel-trigger");
    if (btn) {
      const chatDrawerOpen =
        !!document.querySelector(".hamburger-panel .menu-panel.slide-in") &&
        this.sidebarState?._requestedPanelKey === "chat";
      btn.classList.toggle("--active", chatDrawerOpen);
      return;
    }
    const footer = document.querySelector("nav.c-footer");
    if (!footer) {
      return;
    }
    btn = document.createElement("button");
    btn.id = "f-nav-chat-panel-trigger";
    btn.type = "button";
    btn.className = "btn btn-icon-text btn-transparent c-footer__item";
    btn.setAttribute("aria-label", "Chat sections");
    btn.title = "Chat sections";
    btn.innerHTML =
      '<svg class="fa d-icon d-icon-layer-group svg-icon fa-width-auto svg-string" width="1em" height="1em" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><use href="#layer-group"></use></svg><span class="d-button-label">Menu</span>';
    btn.addEventListener("click", this.toggleChatPanel);
    footer.prepend(btn);
  }

  @action
  setupChatPanelTrigger() {
    this._footerObserver = new MutationObserver(() => {
      this.ensureChatPanelTrigger();
    });
    this._footerObserver.observe(document.body, {
      childList: true,
      subtree: true,
    });
    this.ensureChatPanelTrigger();
  }

  @action
  teardownChatPanelTrigger() {
    this._footerObserver?.disconnect();
    document.getElementById("f-nav-chat-panel-trigger")?.remove();
  }

  @action
  toggleNotification() {
    this.#handleElementClick("toggle-current-user");
  }

  @action
  navigateNotifications() {
    DiscourseURL.routeTo(this.notificationsDestination);
  }

  @action
  toggleSearchMenu() {
    this.#handleElementClick("search-button");
  }

  @action
  navigate(tab) {
    DiscourseURL.routeTo(tab.destination);
  }

  <template>
    {{#if this.shouldShowNav}}
      <div
        class="f-nav"
        {{didInsert this.syncChatFooter}}
        {{didInsert this.setupChatPanelTrigger}}
        {{didUpdate this.syncChatFooter this.isInChat}}
        {{willDestroy this.teardownChatFooter}}
        {{willDestroy this.teardownChatPanelTrigger}}
      >
        {{#each this.tabs as |tab|}}
          <FNavItem
            @tab={{tab}}
            @isTopicRoute={{this.isTopicRoute}}
            @canUseChat={{this.canUseChat}}
            @isInDoNotDisturbBadge={{this.isInDoNotDisturbBadge}}
            @showDoNotDisturbEndDate={{this.showDoNotDisturbEndDate}}
            @doNotDisturbDateTime={{this.doNotDisturbDateTime}}
            @currentUser={{this.currentUser}}
            @topicTrackingState={{this.topicTrackingState}}
            @homeDestination={{this.homeDestination}}
            @messagesDestination={{this.messagesDestination}}
            @searchDestination={{this.searchDestination}}
            @notificationsDestination={{this.notificationsDestination}}
            @aiBotDestination={{this.aiBotDestination}}
            @onHomeClick={{this.homeTabRouteSwitcher}}
            @onHamburgerClick={{this.toggleHamburger}}
            @onNotificationClick={{this.navigateNotifications}}
            @onToggleNotification={{this.toggleNotification}}
            @onSearchClick={{this.toggleSearchMenu}}
            @onNavigate={{this.navigate}}
          />
        {{/each}}
      </div>
    {{/if}}
  </template>
}
