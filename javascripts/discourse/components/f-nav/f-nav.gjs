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

const SCROLL_MAX = 30;
const HIDDEN_F_NAV_CLASS = "f-nav-hidden";
const MODAL_OPEN_CLASS = "modal-open";
const SCROLL_LOCK_CLASS = "scroll-lock";
// Core shortens the full-page chat by --footer-nav-height under this class (its own
// PWA bar): on /chat this bar takes that place (scss/mobile/f-nav-root.scss).
const CHAT_FOOTER_CLASS = "footer-nav-visible";

// With the bar lifted above the cloak, the ☰ tab is the pointer target when
// the drawer is open — and core's outside-click handler tears the drawer
// wrapper down INSTANTLY (no animation) for any outside target that is not
// the cloak itself. Block that pointerdown from leaving the bar: the tab's
// click handler then closes through the cloak's animated dismiss path
// instead (see toggleHamburger), and the double-fire (instant close + our
// toggle re-opening it) is gone.
document.addEventListener(
  "pointerdown",
  (e) => {
    if (!document.querySelector(".hamburger-panel .menu-panel.slide-in")) {
      return;
    }
    const tab = e.target.closest?.(".f-nav .tab");
    if (tab && tab.querySelector('use[href="#jt-menu"]')) {
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

  // Scroll handling
  lastScrollTop = 0;
  scrollTimeout = null;
  setChatFooter = false;

  @action
  scrollListener(event) {
    if (
      document.documentElement.classList.contains(MODAL_OPEN_CLASS) ||
      document.documentElement.classList.contains(SCROLL_LOCK_CLASS)
    ) {
      return;
    }

    if (this.scrollTimeout) {
      return;
    }

    this.scrollTimeout = requestAnimationFrame(() => {
      const currentScroll = window.scrollY;
      const shouldHide = this.lastScrollTop < currentScroll && currentScroll > SCROLL_MAX;

      document.body.classList.toggle(HIDDEN_F_NAV_CLASS, shouldHide);
      this.lastScrollTop = currentScroll;
      this.scrollTimeout = null;
    });
  }

  // The scroll listener that hid this bar (and the header) after 30px of
  // scrolling down is intentionally NOT registered: the bar must stay visible
  // at every scroll position, not just at the top of the page. The listener
  // code below is kept for reference / upstream merges, it just never runs.
  @action
  setupScrollListener() {}

  @action
  removeScrollListener() {
    document.removeEventListener("scroll", this.scrollListener);
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
    // Chat pages must show the CHAT panel in the drawer (Search chat /
    // channels / DMs), like core's own hamburger does there — core's
    // route-based panel switch does not fire for this programmatic open,
    // so pick the panel explicitly. Forum pages get the main panel back.
    this.sidebarState?.setPanel?.(this.isInChat ? "chat" : "main");
    this.#handleElementClick("toggle-hamburger-menu");
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
        {{didInsert this.setupScrollListener}}
        {{didInsert this.syncChatFooter}}
        {{didUpdate this.syncChatFooter this.isInChat}}
        {{willDestroy this.removeScrollListener}}
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
