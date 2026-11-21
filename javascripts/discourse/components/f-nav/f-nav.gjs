import Component from "@ember/component";
import { service } from "@ember/service";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import DiscourseURL from "discourse/lib/url";
import DoNotDisturb from "discourse/lib/do-not-disturb";
import EmbedMode from "discourse/lib/embed-mode";
import FNavItem from "./f-nav-item";

// Core shortens the full-page chat by --footer-nav-height under this class (its own
// PWA bar): on /chat this bar takes that place (scss/mobile/f-nav-root.scss).
const CHAT_FOOTER_CLASS = "footer-nav-visible";

// With the bar lifted above the cloak, the bar's own triggers (the ☰ tab and
// the chat-panel button) are the pointer targets when a drawer is open — and
// core's outside-click handler tears the drawer wrapper down INSTANTLY (no
// animation) during pointerdown for any outside target that is not the cloak
// itself. Block that pointerdown from leaving those triggers: their click
// handlers then decide open/close themselves and close through the cloak's
// animated dismiss path (see toggleHamburger / toggleChatPanel) — without
// this, the second tap of either trigger re-opened the drawer instead of
// closing it.
document.addEventListener(
  "pointerdown",
  (e) => {
    if (!document.querySelector(".hamburger-panel .menu-panel.slide-in")) {
      return;
    }
    const hamburgerTab = e.target.closest?.(".f-nav .tab");
    if (
      (hamburgerTab && hamburgerTab.querySelector('use[href="#jt-menu"]')) ||
      e.target.closest?.("#f-nav-chat-panel-trigger")
    ) {
      e.stopPropagation();
    }
  },
  true
);

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
        return;
      }
    }
    // Opening: the site hamburger always shows the main (forum) panel — the
    // chat panel drawer has its own trigger on chat pages (toggleChatPanel).
    this.sidebarState?.setPanel?.("main");
    this.#handleElementClick("toggle-hamburger-menu");
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
  }

  @action
  ensureChatPanelTrigger() {
    if (!this.isInChat) {
      document.getElementById("f-nav-chat-panel-trigger")?.remove();
      return;
    }
    const footer = document.querySelector("nav.c-footer");
    if (!footer || document.getElementById("f-nav-chat-panel-trigger")) {
      return;
    }
    const btn = document.createElement("button");
    btn.id = "f-nav-chat-panel-trigger";
    btn.type = "button";
    btn.className = "btn btn-icon-text btn-transparent c-footer__item";
    btn.setAttribute("aria-label", "Chat sections");
    btn.title = "Chat sections";
    btn.innerHTML =
      '<svg class="fa d-icon d-icon-bars svg-icon fa-width-auto svg-string" width="1em" height="1em" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><use href="#jt-menu"></use></svg><span class="d-button-label">Menu</span>';
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
