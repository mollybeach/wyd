# wyd?

**Find My Friends meets a social event concierge.** wyd helps you find your friends, discover the best events, and coordinate plans without giving up your privacy.

Built at **ETHGlobal Lisbon 2026** as a native SwiftUI iOS app.

<!-- Add screenshots to docs/ and link them here -->

---

## Why

At a big conference, the real question is always *"wyd?"* Where is everyone, what's worth going to, and which plan can the whole crew actually make? The answer is spread across group chats, Luma pages, and five different calendars. wyd puts it in one place, and you decide exactly how much each group of friends can see.

## Features

| Tab | What it does |
| --- | --- |
| **wyd?** | A chat concierge. Ask *"wyd tonight?"*, *"Where is everyone?"*, *"What's trending?"*, *"Find an event everyone can make"*, *"Networking events nearby"*, or *"Who's going to Sunset Boat Party?"*. Answers come from live backend data, with event cards you can join in one tap. |
| **Map** | A live MapKit map of events (colored by category, with friend-count badges), friends who share their location, and your own position. Toggle to show only events your friends are going to. |
| **Events** | **Browse** shows personalized recommendations and every event grouped by day, with category filters, event details and RSVP. **My Calendar** is a real day timeline that merges RSVPs, personal events, and synced calendars, with overlapping events laid side by side. |
| **Circles** | Groups of friends (e.g. *Hackathon Team*). For each circle you choose what you share. You can hide your events from one specific friend, add friends by username, and tap a friend to view the calendar they share with you. |
| **You** | Your upcoming schedule, personal events, connected calendars (Google, Luma, Partiful, Outlook, any `.ics` feed, or Apple Calendar), location sharing, conference mode, and sign out. |

## Privacy model

Privacy is enforced **on the server** in the SQL functions, not just hidden in the UI.

- **Per-circle sharing toggles** (`circle_members`):
  - **Free / Busy**: friends see a gray, untitled "Busy" block
  - **Public Events**: friends see titles of public events you're going to
  - **Approximate Location** / **Live Location**: friends see you on the map
  - New circles default to free/busy + public events **on**, locations **off**.
- **Per-friend override** (`friend_sharing.share_events`): hide your events from one person without leaving the circle.
- **Synced calendars are always private.** Events imported from ICS feeds or Apple Calendar are stored with `visibility = private` and never shown to friends, not even as their titles.
- **Location is opt-in, twice.** Nothing is sent until you turn on *Share my location* in the You tab, and iOS location permission is requested only at that moment, not at launch. Updates are throttled to once a minute.

## Getting started

### Requirements

- Xcode 16 or later (tested with Xcode 26.5)
- iOS 17.0+ simulator or device

### Run

```bash
open wydiOS/MyProject.xcodeproj
```

Select the **MyProject** scheme and an iPhone simulator, then press **⌘R**. The app talks to a hosted backend that's already running, so there's nothing else to set up.

### Demo account

| | |
| --- | --- |
| Email | `demo@wyd.app` |
| Password | `demo1234` |
| Username | `molly` |

The demo account belongs to a *Hackathon Team* circle with `alice`, `bob`, `priya`, `diego`, and `sofia`, who have RSVPs, locations, and calendars already seeded. You can also create your own account and add these usernames to a circle.

### Conference mode

The demo data covers ETHGlobal Lisbon (**July 24–27, 2026**). After those dates, every time-based query would return nothing. **Conference mode** (You → Demo) replays the event instead. The app's clock starts at the opening keynote and moves forward in real time from launch, so recommendations, "where is everyone", and the calendar all have data.

It turns on automatically once the real conference is over. Turn it off to use the actual date and time.

### Tests

```bash
cd wydiOS && xcodebuild test -project MyProject.xcodeproj -scheme MyProject -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Unit tests cover ICS parsing (CRLF line endings, folded lines, escapes, TZID, all-day events), concierge intent parsing, decoding Postgres numbers sent as strings, API error envelopes, the conference clock, and username normalization.

## Architecture

```
SwiftUI views ──► APIClient ──► LingCode Cloud backend (Postgres)
     │                            ├─ tables:  profiles, circles, circle_members, events,
     │                            │           rsvps, locations, friend_sharing, calendar_feeds
     │                            └─ RPCs:    wyd_recommend, wyd_friends_now, wyd_trending,
     │                                        wyd_friend_locations, wyd_my_calendar,
     │                                        wyd_friend_calendar, wyd_friends, wyd_visible_friends
     ├─ ConciergeEngine   rule-based intent parsing → RPC → natural-language reply
     ├─ ICSImporter       fetch + parse .ics / webcal feeds, dedupe by UID
     ├─ EventKitImporter  Apple Calendar import, dedupe by event identifier
     ├─ LocationManager   opt-in CoreLocation → locations table
     └─ WYDClock          real time or conference replay
```

### Project layout

```
wydiOS/
├── MyProject.xcodeproj
├── MyProject/
│   ├── MyProjectApp.swift      app entry, injects SessionStore + LocationManager
│   ├── ContentView.swift       auth routing + 5-tab TabView
│   ├── Config.swift            backend URL, anon key, venue coordinates
│   ├── WYDClock.swift          "now", with conference replay mode
│   ├── Models.swift            Decodable models, category colors/icons, date formatting
│   ├── APIClient.swift         POST /select|insert|update|delete|rpc, response envelope
│   ├── Session.swift           sign in / sign up / restore, token in UserDefaults
│   ├── AuthView.swift
│   ├── ConciergeEngine.swift   intent parser + answer composer
│   ├── ConciergeView.swift     chat UI, event cards, suggestion chips
│   ├── EventMapView.swift
│   ├── EventsView.swift        browse, detail, RSVP
│   ├── CalendarView.swift      day timeline (yours or a friend's)
│   ├── CirclesView.swift       circles, share toggles, add friends
│   ├── ProfileView.swift       schedule, calendar feeds, privacy, demo settings
│   ├── ICSImporter.swift
│   ├── EventKitImporter.swift
│   └── LocationManager.swift
└── MyProjectTests/
```

The Xcode project uses file-system synchronized groups, so any new `.swift` file in `MyProject/` is added to the target automatically.

### Backend API

Every request is a `POST` to `https://lingcode.dev/api/cloud/be/<backend-id>/<endpoint>`, authorized with `Bearer <user token>` (or the anon key before sign-in). Responses look like `{ "ok": true, "data": … }` on success and `{ "ok": false, "error": …, "message": … }` on failure.

| Endpoint | Body |
| --- | --- |
| `auth/signup`, `auth/signin` | `{ email, password }` → `{ user, token }` |
| `select` | `{ table, where?, limit? }` |
| `insert` | `{ table, row, returning }` |
| `update` | `{ table, where, patch, returning }` |
| `delete` | `{ table, where }` |
| `rpc` | `{ fn, args }` |

| RPC | Args | Used by |
| --- | --- | --- |
| `wyd_recommend` | `p_user, p_now, p_limit` | Concierge, Events, Map |
| `wyd_friends_now` | `p_user, p_now` | Concierge "where is everyone" |
| `wyd_trending` | `p_now, p_limit` | Concierge "what's trending" |
| `wyd_friend_locations` | `p_user` | Map |
| `wyd_my_calendar` | `p_user, p_from, p_to` | My Calendar |
| `wyd_friend_calendar` | `p_viewer, p_friend, p_from, p_to` | Friend calendar (privacy-filtered) |

## Calendar sync

Any iCalendar feed works:

- **Google Calendar**: Settings → your calendar → *Secret address in iCal format*
- **Luma**: calendar page → *Subscribe* → copy the feed URL
- **Partiful**: event → *Add to calendar* → `.ics` link
- **Outlook, Meetup**, and most event apps also publish `.ics` feeds

`webcal://` links are converted to `https://` automatically. Re-syncing only imports events it hasn't seen before, matched by the event's UID.

## Known limitations & next steps

- **Naming**: the Xcode target is still `MyProject` with bundle ID `com.example.MyProject`. Rename it and set a real team before shipping to TestFlight.
- **Backend SQL isn't versioned here.** The tables and RPC functions live in the LingCode Cloud project. Export them into this repo (e.g. `backend/schema.sql`).
- **Legacy column**: `circle_members.sharing_level` is left over from the old single-level sharing model. The app no longer reads it, and it can be dropped.
- **Seeded demo data** is fixed to July 2026. Conference mode handles this, but a re-seed script would make fresh demos easier.
- **The concierge is rule-based.** Swapping `ConciergeEngine.parse` for an LLM with tool calls to the same RPCs would handle open-ended questions.
- **Circles loading is N+1** (one request per circle and member). Fine at demo scale; a single `wyd_my_circles` RPC would be better.
- Upserts (`locations`, `friend_sharing`) are done as delete + insert.
- No push notifications yet (e.g. "3 friends just RSVP'd to Closing Party").
- On-chain integrations (Sui, World, The Graph) were intentionally left out of this client.
