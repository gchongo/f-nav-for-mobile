import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { and } from "truth-helpers";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";
import formatAge from "discourse/helpers/format-age";
import MultiTabMessages from "../multi-tab/multi-tab-messages";
import AllUnreadNotifications from "../notifications/all-unread";
import ReviewableNotifications from "../notifications/reviewable";
import MessagesIcon from "../messages/messages-icon";
import ChatIcon from "../messages/chat-icon";

export default class FNavItem extends Component {
  get isHome() {
    return this.args.tab?.function === "home";
  }

  get isHamburger() {
    return this.args.tab?.function === "hamburger";
  }

  get isMulti() {
    return this.args.tab?.function === "multi";
  }

  get isMessage() {
    return this.args.tab?.function === "message";
  }

  get isChat() {
    return this.args.tab?.function === "chat";
  }

  get isNotification() {
    return ["notificationToRoute", "notificationMenu"].includes(this.args.tab?.function);
  }

  get isSearch() {
    return this.args.tab?.function === "search";
  }

  get isNotificationToRoute() {
    return this.args.tab?.function === "notificationToRoute";
  }

  get destination() {
    if (this.isHome) {
      return this.args.homeDestination;
    }
    if (this.isMulti || this.isMessage) {
      return this.args.messagesDestination;
    }
    if (this.isNotification) {
      return this.args.notificationsDestination;
    }
    if (this.isSearch) {
      return this.args.searchDestination;
    }

    return this.args.tab?.destination;
  }

  get clickHandler() {
    if (this.isHome) {
      return this.args.onHomeClick;
    }
    if (this.isHamburger) {
      return this.args.onHamburgerClick;
    }
    if (this.isNotification) {
      return this.isNotificationToRoute 
        ? this.args.onNotificationClick 
        : this.args.onToggleNotification;
    }
    if (this.isSearch) {
      return this.args.onSearchClick;
    }

    return () => this.args.onNavigate(this.args.tab);
  }

  get showLabels() {
    return settings.f_nav_show_labels;
  }

  <template>
    <div
      role="link"
      class="tab"
      data-destination={{this.destination}}
      {{on "click" this.clickHandler}}
    >
      {{#if this.isHome}}
        {{#if @isTopicRoute}}
          {{dIcon "angle-left"}}
        {{else}}
          {{#if @topicTrackingState.hasIncoming}}
            <a href="#" class="badge-notification has-incoming" tabindex="-1"></a>
          {{/if}}
          {{dIcon @tab.icon}}
        {{/if}}
      {{else if this.isMulti}}
        <MultiTabMessages />
      {{else if this.isMessage}}
        <MessagesIcon />
      {{else if this.isChat}}
        {{#if @canUseChat}}
          <ChatIcon />
        {{/if}}
      {{else if this.isNotification}}
        {{#if @isInDoNotDisturbBadge}}
          <div title={{i18n "notifications.paused"}}>
            {{#if @showDoNotDisturbEndDate}}
              {{formatAge @doNotDisturbDateTime}}
            {{/if}}
            {{dIcon "bell-slash"}}
          </div>
        {{else}}
          {{#if @currentUser.unseen_reviewable_count}}
            <ReviewableNotifications />
          {{else}}
            <AllUnreadNotifications />
          {{/if}}
          {{dIcon @tab.icon}}
        {{/if}}
      {{else}}
        {{dIcon @tab.icon}}
      {{/if}}
      {{#if this.showLabels}}
        <div class="tab-label">
          {{#if (and this.isHome @isTopicRoute)}}
            {{i18n "js.back_button"}}
          {{else}}
            {{@tab.name}}
          {{/if}}
        </div>
      {{/if}}
    </div>
  </template>
}
