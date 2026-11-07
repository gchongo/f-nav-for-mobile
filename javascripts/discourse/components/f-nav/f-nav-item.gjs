import Component from "@glimmer/component";
import { getOwner } from "@ember/application";
import { service } from "@ember/service";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { and } from "truth-helpers";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";
import formatAge from "discourse/helpers/format-age";
import DiscourseURL from "discourse/lib/url";
import MultiTabMessages from "../multi-tab/multi-tab-messages";
import AllUnreadNotifications from "../notifications/all-unread";
import ReviewableNotifications from "../notifications/reviewable";
import MessagesIcon from "../messages/messages-icon";
import ChatIcon from "../messages/chat-icon";
import AiBot from "../ai-bot/ai-bot";

export default class FNavItem extends Component {
  @service composer;
  @service currentUser;
  @service router;

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

  get isAiBot() {
    return this.args.tab?.function === "aiBot";
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
    if (this.isAiBot) {
      return this.args.aiBotDestination;
    }
    if (this.isSearch) {
      return this.args.searchDestination;
    }

    return this.args.tab?.destination;
  }

  // The tab that opens the chat (its own, Multi Tab's messages-and-chat, or a custom one
  // pointing at /chat) leads back to the forum from inside it, as the AI bot tab does
  // from its conversations: the same shuffle icon, to the last page outside.
  get exitsChat() {
    const route = this.router.currentRouteName || "";
    const inChat = route === "chat" || route.startsWith("chat.");
    const opensChat =
      this.isChat ||
      this.isMulti ||
      /^\/chat(\/|$)/.test(this.args.tab?.destination || "");
    return inChat && opensChat;
  }

  exitChat = () => {
    const chatState = getOwner(this).lookup("service:chat-state-manager");
    DiscourseURL.routeTo(chatState?.lastKnownAppURL || "/");
  };

  // The compose tab (function "compose", or a custom tab pointing at /new-topic): a reply
  // in a topic the user can post in, a new topic everywhere else, in the category being
  // viewed. The composer service's own entry points, so drafts reopen as usual.
  get isCompose() {
    return (
      this.args.tab?.function === "compose" ||
      /^\/new-topic(\/|\?|$)/.test(this.args.tab?.destination || "")
    );
  }

  get replyTopic() {
    if (!this.args.isTopicRoute) {
      return null;
    }
    const topic = getOwner(this).lookup("controller:topic")?.model;
    return topic?.details?.can_create_post ? topic : null;
  }

  compose = () => {
    const topic = this.replyTopic;
    if (topic) {
      this.composer.focusComposer({ topic });
    } else {
      this.composer.openNewTopic({
        category: getOwner(this).lookup("service:discovery")?.category,
      });
    }
  };

  get clickHandler() {
    if (this.isCompose) {
      return this.compose;
    }
    if (this.exitsChat) {
      return this.exitChat;
    }
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
    if (this.isAiBot) {
      return () => {};
    }

    return () => this.args.onNavigate(this.args.tab);
  }

  get showLabels() {
    return settings.f_nav_show_labels;
  }

  get manager() {
    return getOwner(this)?.lookup("service:ai-conversations-sidebar-manager");
  }

  get bots() {
    const availableBots = this.currentUser?.ai_enabled_chat_bots
      ?.filter((bot) => !bot.is_agent || bot.has_default_llm)
      .filter(Boolean);

    return availableBots ? availableBots.map((bot) => bot.model_name) : [];
  }

  get isHidden() {
    if (this.isAiBot) {
      return !this.manager || this.bots.length === 0;
    }
  
    return this.isChat && !this.args.canUseChat;
  }

  <template>
    {{#unless this.isHidden}}
      {{! Use <button> instead of a role="link" div so keyboard users get
          native Enter/Space handling without extra ARIA scaffolding. }}
      <button
        type="button"
        class="tab"
        data-destination={{this.destination}}
        {{on "click" this.clickHandler}}
      >
        {{#if this.exitsChat}}
          {{dIcon "shuffle"}}
        {{else if this.isCompose}}
          {{dIcon (if this.replyTopic "reply" @tab.icon)}}
        {{else if this.isHome}}
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
        {{else if this.isAiBot}}
          <AiBot />
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
            {{#if this.exitsChat}}
              {{i18n "sidebar.back_to_forum"}}
            {{else if (and this.isCompose this.replyTopic)}}
              {{i18n "topic.reply.title"}}
            {{else if (and this.isHome @isTopicRoute)}}
              {{i18n "js.back_button"}}
            {{else}}
              {{@tab.name}}
            {{/if}}
          </div>
        {{/if}}
      </button>
    {{/unless}}
  </template>
}
