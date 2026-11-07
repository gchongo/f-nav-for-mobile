# F NAV for mobile (nautas)

Fork of [VaperinaDEV/f-nav-for-mobile](https://github.com/VaperinaDEV/f-nav-for-mobile)
for comunidad.criptonautas.co.

Changes:

- The bar also shows on `/chat`, in place of the chat's own footer, whose tabs are all in
  the chat sidebar, so the header's sidebar button (hidden by the chat plugin on phones)
  comes back. Core leaves room for the bar below the chat (`footer-nav-visible`), and it
  steps aside while the keyboard is up.
- Inside the chat, the tab that opens it (Chat, Multi Tab, or a custom one to `/chat`)
  leads back to the forum with the `shuffle` icon, as the AI bot button does from its
  conversations.
- A compose tab (function `compose`, or a tab pointing at `/new-topic`): replies inside a
  topic the user can post in, opens a new topic elsewhere, in the category being viewed.
