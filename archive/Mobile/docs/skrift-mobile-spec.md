# Skrift Mobile — Project Specification

## Overview

Skrift Mobile is an iPhone companion app for the Skrift desktop pipeline. It captures voice memos with rich contextual metadata (location, weather, barometric pressure, daylight, steps) and syncs them to the Mac for processing via Parakeet transcription, MLX enhancement, and Obsidian export.

The phone is a capture device, not a processing device. All transcription and LLM work happens on the Mac.

---

## Tech Stack

- **Framework:** Expo (React Native) with TypeScript
- **Audio:** `expo-audio` with background recording enabled
- **Sensors:** `expo-sensors` (Barometer/Pedometer), `expo-location`
- **HealthKit:** `react-native-health` (future, when Apple Watch is available)
- **Weather API:** OpenWeatherMap One Call API 3.0 (free tier)
- **Daylight calc:** `suncalc` npm package (pure math, no API)
- **Dev build:** `expo-dev-client` required (no Expo Go — native modules needed)
- **Apple Developer:** $99/year account recommended to avoid 7-day re-signing and enable TestFlight distribution

---

## Core Flow

```
Tap record (one tap from tab bar, recording starts immediately)
    → Audio recording + waveform visualization
    → Tap stop
    → Auto-capture metadata (GPS, weather, pressure, daylight, steps)
    → Review screen (metadata, tags, optional photo)
    → Save locally
    → Sync to Mac when on home WiFi (auto-retry, silent)
    → Mac pipeline: Parakeet → Sanitise → Enhance → Export to Obsidian
```

The record button in the tab bar starts recording immediately — no intermediate screen. The memory aid checklist is visible during recording as a glanceable prompt. One tap to start, one tap to stop, straight to review.

---

## Screens

### 1. Home (Memos list)

The default screen. Shows all locally stored memos as cards.

Each card displays:
- Title (placeholder until Mac generates one, e.g. "Voice memo · 4:32")
- Duration
- Date, time, day period (morning/afternoon/evening/night)
- Tags
- Sync status badge: "waiting" (amber) or "synced" (green)

Actions:
- Tap a card → Detail view
- Swipe left on a card → Delete
- Pull to refresh → Retry sync for waiting memos

Header shows memo count and pending sync count: "3 memos · 1 waiting to sync"

### 2. Record

Entered by tapping the center tab bar button. Recording starts immediately.

Shows:
- Memory aid checklist (read-only, glanceable prompts while recording)
- Live waveform visualization (dB metering from `expo-audio`)
- Timer (counting up)
- Stop button (replaces record button state)

Memory aid default prompts:
- What's on your mind?
- Why does it matter?
- What triggered this thought?
- Any people involved?
- Tags — say them out loud

Prompts are customizable in Settings.

On stop:
- Capture all metadata in one burst
- Navigate to Review screen

Audio format: .m4a (matches what the desktop backend already expects)

### 3. Review

Shown once after recording stops. This is the only time the user actively interacts with metadata before saving.

Sections:
- **Recording card** — duration, timestamp, play button to listen back
- **Captured metadata** (read-only, auto-populated):
  - Location (place name, reverse geocoded)
  - Weather (conditions + temperature)
  - Barometric pressure (hPa) + trend (rising/steady/falling)
  - Day period
  - Daylight hours (sunrise/sunset times)
  - Steps today
  - HealthKit data (future: last night's sleep, resting HR)
- **Tags** — manual input, supports spoken hashtags like `#inzicht`, `#realisatie`, `#filosofatie`
- **Photo** — optional, from camera or library

Actions:
- **Save** — stores memo locally, queues for sync
- **Send to Mac** — only shown when Mac is reachable (health check to FastAPI endpoint). If Mac is unreachable, this button does not appear. Memos sync automatically when the Mac becomes available.

### 4. Detail

Shown when tapping a memo from the Home list. Read-only view of a saved memo.

Shows:
- Title and recording info
- Play button to listen back
- Tags
- Full metadata
- Sync status with explanation ("Waiting for Mac — will sync when connected to home WiFi" or "Synced · 2 minutes ago")

Actions:
- Delete (top right)
- Edit tags (before sync only)

### 5. Settings

Sections:

**Mac connection**
- Status indicator (connected/disconnected)
- Device name (e.g. "Tiuri's MacBook Pro")
- Connection info (IP:port)
- QR code scan button for first-time setup (Electron app generates QR encoding local IP + port)
- Last sync timestamp

**Appearance**
- Theme toggle: Light / Dark (matches desktop app's token system)

**Metadata capture**
- Toggles for each metadata source: Location, Weather + pressure, Daylight hours, Step count, HealthKit
- HealthKit defaults to off (no Apple Watch currently)

**Memory aid prompts**
- Edit button → editable list of checklist prompts

**Storage**
- Local memo count and size
- Clear synced memos (removes local copies after confirmed sync)

---

## Metadata Capture

All metadata is captured in a single burst when the user stops recording.

### Always available (iPhone)

| Data | Source | Notes |
|------|--------|-------|
| GPS coordinates | `expo-location` | |
| Place name | `expo-location` reverse geocoding | e.g. "Príncipe Real, Lisbon" |
| Weather conditions | OpenWeatherMap API | e.g. "Clear, 18°C" |
| Barometric pressure | OpenWeatherMap API | hPa, from same API call as weather |
| Pressure trend | OpenWeatherMap API | Compare current pressure to 3hrs ago from hourly data. >1.5 hPa diff = "rising", <-1.5 = "falling", else "steady" |
| Day period | Timestamp | Bucketed: morning (6-12), afternoon (12-17), evening (17-21), night (21-6) |
| Sunrise / sunset | `suncalc` npm package | Calculated from GPS + date, no API needed |
| Daylight hours | `suncalc` | Derived from sunrise/sunset |
| Step count | `expo-sensors` Pedometer | Today's count, no watch needed |

### Future (with Apple Watch)

| Data | Source | Notes |
|------|--------|-------|
| Last night's sleep | `react-native-health` (HealthKit) | Duration + quality |
| Resting heart rate | `react-native-health` (HealthKit) | |
| Heart rate variability | `react-native-health` (HealthKit) | |

### Metadata JSON structure

```json
{
  "capturedAt": "2026-04-02T21:34:00+01:00",
  "location": {
    "latitude": 38.7167,
    "longitude": -9.1500,
    "placeName": "Príncipe Real, Lisbon"
  },
  "weather": {
    "conditions": "Clear",
    "temperature": 18,
    "temperatureUnit": "C"
  },
  "pressure": {
    "hPa": 1013.2,
    "trend": "rising"
  },
  "dayPeriod": "evening",
  "daylight": {
    "sunrise": "07:12",
    "sunset": "19:58",
    "hoursOfLight": 12.77
  },
  "steps": 8432,
  "tags": ["inzicht", "filosofatie"],
  "photoFilename": null,
  "healthKit": null
}
```

---

## Sync

### Connection model

The phone connects directly to the Mac's FastAPI backend over local WiFi. No cloud relay, no iCloud Drive.

- The Mac runs Skrift desktop with the backend on `http://<local-ip>:8000`
- The phone discovers the Mac via QR code (first time) or stored IP (subsequent)
- Before showing "Send to Mac," the phone pings `GET /api/system/health` to verify reachability

### Sync behaviour

- **At home (Mac reachable):** Memo is POSTed immediately to `/api/files/upload` with audio + metadata JSON as multipart form data. Phone shows "synced" badge.
- **Away from home (Mac unreachable):** Memo is saved locally. No "Send to Mac" button shown. When the phone detects the Mac (periodic background check or on app open), it auto-syncs all pending memos silently.
- **Notification:** iOS local notification when sync completes: "3 memos synced to Skrift"
- **Storage cleanup:** User can manually clear synced memos in Settings to free phone storage.

### What the phone sends

Multipart form POST to `/api/files/upload`:
- `audio`: the .m4a file
- `metadata`: JSON string (see structure above)
- `photo`: optional image file

---

## iOS Share Sheet Integration

The app registers as a Share Extension target for audio file types. This enables:

- **Voice Memos app:** Long press a memo → Share → Skrift. Opens the Review screen with the audio pre-loaded.
- **WhatsApp:** Long press a voice message → Share → Skrift. Same flow.
- **Any app** that can share audio files.

This bridges the gap between the current Voice Memos workflow and the new app. Users can continue recording in Voice Memos and share to Skrift afterwards.

Implementation: Expo Share Extension (requires native config in Xcode, community packages available).

---

## Lock Screen Quick Record

On iPhone 15 Pro and newer, the Action Button can be mapped to an iOS Shortcut that opens Skrift and immediately starts recording. This is configured by the user in iOS Settings, not by the app.

The app also supports a Lock Screen widget (via `expo-widget`) that acts as a quick-launch button.

---

## Desktop Backend Changes

The existing Skrift desktop backend needs the following changes to accept phone memos:

### Upload endpoint extension

`POST /api/files/upload` currently accepts audio files. Extend to accept:
- `metadata` field (JSON string) in the multipart form
- `photo` field (optional image file)

When metadata is present:
1. Write metadata fields into `status.json` alongside existing fields
2. Pre-populate tags from metadata (same mechanism as Apple Notes hashtag extraction)
3. Store photo in the file's output folder

### Pipeline behaviour

Phone memos flow through the same pipeline as desktop uploads:
- Parakeet transcribes the audio (same as always)
- Sanitise links names (same as always)
- Enhance generates title, summary, copy edit, and additional tag suggestions (on top of phone-provided tags)
- Phone tags appear as pre-existing tags (accent colour), LLM suggestions appear as new (amber/dashed)
- Export compiles everything into Markdown with extended YAML frontmatter

### Extended YAML frontmatter

```yaml
title: "On letting go of control"
date: 2026-04-02
time: "21:34"
lastTouched:
firstMentioned:
author: Tiuri
source: voiceMemo
confidence: 0.9
location: "Príncipe Real, Lisbon"
weather: "Clear, 18°C"
pressure: 1013.2
pressureTrend: rising
dayPeriod: evening
daylight:
  sunrise: "07:12"
  sunset: "19:58"
  hoursOfLight: 12.77
steps: 8432
tags:
  - inzicht
  - filosofatie
  - philosophy
summary: >
  Reflection on the Stoic concept of control as active practice...
```

Existing fields (`title`, `date`, `lastTouched`, `firstMentioned`, `author`, `source`, `confidence`, `tags`, `summary`) remain unchanged. New metadata fields slot in alongside them. Old memos without phone metadata simply have these fields absent — Obsidian and Dataview handle missing properties gracefully.

### Frontend inspector update

When a file has phone metadata, show a "Capture context" section in the right inspector panel:
- Location
- Weather + pressure + trend
- Day period
- Daylight
- Steps
- Photo thumbnail (if present)

Read-only, for reference while reviewing the note.

---

## Build Order

### Phase 1 — Recording + local storage (1 week)
1. Expo project setup with `expo-dev-client`
2. Audio recording with background support and waveform metering
3. One-tap record from tab bar (starts immediately)
4. Local storage of recordings with metadata JSON sidecar
5. Home screen with memo list
6. Review screen with playback

### Phase 2 — Metadata capture (1 week)
1. GPS + reverse geocoding
2. OpenWeatherMap API integration (weather, pressure, trend)
3. Suncalc daylight calculation
4. Pedometer step count
5. Tag input on Review screen
6. Photo attachment

### Phase 3 — Sync to Mac (1 week)
1. QR code scanning for Mac discovery
2. Health check ping to detect Mac availability
3. POST audio + metadata to backend
4. Local queue with retry logic
5. Sync status badges on memo cards
6. iOS notification on sync completion
7. Backend changes: extended upload endpoint, metadata flow-through to status.json

### Phase 4 — Polish + extras (1 week)
1. Light/dark theme
2. Share Sheet extension (receive audio from Voice Memos, WhatsApp)
3. Settings screen (all toggles, QR scan, storage management)
4. Customizable memory aid prompts
5. Swipe to delete
6. Extended YAML frontmatter in export
7. Inspector "Capture context" section on desktop

### Phase 5 — Future
1. HealthKit integration (sleep, HR, HRV) when Apple Watch available
2. Lock screen widget
3. Action Button shortcut documentation
4. Desktop backfill script for adding metadata fields to existing vault notes

---

## Constraints

- **Offline-first:** The phone must work fully without network. Memos are never lost.
- **No cloud:** All sync happens over local WiFi directly to the Mac. No servers, no accounts, no subscriptions.
- **Audio format:** .m4a to match existing backend expectations.
- **Single user:** This is a personal tool. No auth, no multi-user, no sharing.
- **Battery:** Background recording is enabled but used only during active recording. No continuous sensor polling.
- **Privacy:** Location and health data stay on the phone and Mac. Weather API calls use coordinates but no personal data is sent externally.
