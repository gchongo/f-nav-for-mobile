import { apiInitializer } from "discourse/lib/api";
import DiscourseURL from "discourse/lib/url";
import FNav from "../components/f-nav/f-nav";

function highlight(destination) {
  const tabs = document.querySelectorAll(".f-nav .tab");
  tabs.forEach((tab) => {
    if (compareURLs(tab.dataset.destination, destination)) {
      tab.classList.add("active");
    } else {
      tab.classList.remove("active");
    }
  });
}

function compareURLs(url1, url2) {
  if (!url1 || !url2) {
    return false;
  }
  // Clean URL parameters and trailing slashes
  const cleanURL1 = url1.replace(/(\?|#).*/g, "").replace(/\/$/, "");
  const cleanURL2 = url2.replace(/(\?|#).*/g, "").replace(/\/$/, "");

  // Exact match check
  if (cleanURL1 === cleanURL2) {
    return true;
  }

  // Special case for home page
  if (cleanURL1 === "/" || cleanURL1 === "") {
    return cleanURL2 === "/" || cleanURL2 === "";
  }

  // For other pages, check if paths match
  return cleanURL2.startsWith(cleanURL1 + "/") || cleanURL2 === cleanURL1;
}

function resolveMyAlias(url, username) {
  if (!url) {
    return "";
  }
  if (url.startsWith("/my/")) {
    return url.replace("/my/", `/u/${username}/`);
  }
  return url;
}

function updateDataDestinations(username) {
  const tabs = document.querySelectorAll(".f-nav .tab");
  tabs.forEach((tab) => {
    const originalDestination = tab.dataset.destination;
    if (originalDestination?.startsWith("/my/")) {
      tab.dataset.destination = resolveMyAlias(originalDestination, username);
    }
  });
}

// ── Long-press on the chat switcher tabs (Starred / Channels / DMs) opens
// that view's options menu (filter / sort / new channel / new DM …) — the
// same menu the chat's own top-navbar ellipsis button opens, invoked
// directly through the float-kit menu service with the view's section data.
// No layout change: the switcher tabs keep working exactly as before.
const LP_MS = 500;
let lpTimer = null;
let lpStart = null;

const SECTION_FOR = {
  starred: "starred",
  channels: "channels",
  "direct-messages": "dms",
};

// chat plugin menu deps, resolved lazily at runtime (the plugin's modules
// are registered under discourse/plugins/chat/…; the theme id in component
// paths varies, so module names are searched, not hardcoded)
let chatMenuDeps = null;
const chatMenu = () => {
  if (chatMenuDeps) {
    return chatMenuDeps;
  }
  const container = window.Discourse?.__container__;
  const menu = container?.lookup("service:menu");
  const componentName = Object.keys(window.require.entries || {}).find(
    (name) => /components\/chat-channel-list-sidebar-menu/.test(name)
  );
  const libName = Object.keys(window.require.entries || {}).find((name) =>
    /lib\/chat-channel-list-options/.test(name)
  );
  if (!container || !menu || !componentName || !libName) {
    return null;
  }
  chatMenuDeps = {
    menu,
    component: window.require(componentName).default,
    options: window.require(libName).CHANNEL_LIST_SECTION_OPTIONS,
  };
  return chatMenuDeps;
};

export default apiInitializer("1.8.0", (api) => {
  const user = api.getCurrentUser();

  if (!user) {
    return;
  }

  api.onPageChange(() => {
    const navElement = document.querySelector(".f-nav");
    if (navElement) {
      updateDataDestinations(user.username_lower);
    }
  });

  const tabs = settings.f_nav_tabs;
  if (tabs.length === 0) {
    return;
  }

  // Highlight the corresponding tab when the page changes
  api.onAppEvent("page:changed", (data) => {
    const resolvedURL = resolveMyAlias(data.url, user.username_lower);
    highlight(resolvedURL);
  });

  tabs.forEach((tab) => {
    if (tab.destination) {
      const route = api.container.lookup(`route:${tab.destination}`);
      if (route) {
        route.reopen({
          actions: {
            didTransition() {
              const resolvedDestination = resolveMyAlias(tab.destination, user.username_lower);
              highlight(resolvedDestination);
              this._super(...arguments);
              return true;
            },
          },
        });
      }
    }
  });

  // Long-press detection on the chat switcher tabs. Only the three list
  // tabs (Starred / Channels / DMs) have option menus.
  document.addEventListener("pointerdown", (event) => {
    const button = event.target.closest?.(".c-footer .c-footer__item");
    if (!button) {
      return;
    }
    const key = (button.id || "").replace("c-footer-", "");
    // only the ACTIVE view's tab summons its options menu; inactive tabs
    // just navigate on short press and do nothing on long press
    if (!SECTION_FOR[key] || !button.classList.contains("--active")) {
      return;
    }
    lpStart = { x: event.clientX, y: event.clientY };
    lpTimer = setTimeout(() => {
      lpTimer = null;
      navigator.vibrate?.(10);
      const deps = chatMenu();
      if (!deps) {
        return;
      }
      const section = SECTION_FOR[key];
      deps.menu.show(button, {
        component: deps.component,
        contentRole: "menu",
        identifier: "chat-channel-list-options-menu",
        modalForMobile: true,
        placement: "right-start",
        data: { section, ...deps.options[section] },
      });
    }, LP_MS);
  });

  // A long press cancels when the finger moves away or lifts early — the
  // short press then does its normal navigation.
  document.addEventListener("pointermove", (event) => {
    if (
      lpTimer &&
      lpStart &&
      (Math.abs(event.clientX - lpStart.x) > 10 ||
        Math.abs(event.clientY - lpStart.y) > 10)
    ) {
      clearTimeout(lpTimer);
      lpTimer = null;
    }
  });

  ["pointerup", "pointercancel"].forEach((evt) =>
    document.addEventListener(evt, () => {
      if (lpTimer) {
        clearTimeout(lpTimer);
        lpTimer = null;
      }
    })
  );

  // FNav component connector
  api.renderInOutlet("above-footer", FNav);
});
