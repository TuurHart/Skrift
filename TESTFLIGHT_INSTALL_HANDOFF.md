# TestFlight: "Could not install Skrift" — handoff, updated 2026-08-29

**Root cause found 2026-08-30: every live TestFlight build on the whole account was
force-expired inside a 3-second window on 2026-08-26.** 29 builds, 5 apps. It is a known
Apple backend fault, Apple phone support has called it *"a backend issue on their side
requiring senior-advisor reversal"*, and it has been fixed for other developers. **Phone
Apple Developer Support and ask for a senior-advisor reversal** — see *What to do*.

This corrects the earlier conclusion in this doc that the fault was confined to Skrift's app
record. It is not. Skrift is simply the only app with a build uploaded *after* the event, so
it is the only one that can show the symptom.

## The symptom

TestFlight shows the build. Tapping Install gives:

> **Could not install Skrift.** The requested app is not available or doesn't exist.

Two phones (iPhone 17, iPhone 13), both Wi-Fi. Three builds — `0.2.0 (166)`, `(167)` and
`(168)` — fail identically, all showing Complete + "Testing" in ASC. **5 invites, 0 installs
on each.** June's `0.1.0 (4)` installed 4 times over 348 sessions on the same app record,
same group, same testers.

## The actual error (Console.app, device log)

```
Claiming Next PostInstallStatusJob with bundle ID: com.skrift.mobile,
  terminalReason: 1, failureReason: Error Downloading Install Data
postInstallData = "bundleID = com.skrift.mobile  appName = Skrift  platform = iOS
  appID = 6780161319  buildID = 232234897  buildVersion = 0.2.0 (166)
  appSizeInBytes = 14958820  fullPackageSizeInBytes = 14958820
  deltaPackageWasOffered = 0  priorInstalledVersion = (null)"
```

Other developers with the same message captured the HTTP layer underneath it:

```
POST https://testflight.apple.com/v2/accounts/<acct>/apps/<appID>/builds/<buildID>/install
  → code=404, serverFailureReason = "Error Downloading Install Data"
```

**A 404 from Apple's install endpoint.** The device never downloaded anything, never
validated anything. Nothing in the .ipa can cause a 404 on that URL.

## ROOT CAUSE — the 2026-08-26 mass expiry

`GET /v1/builds?filter[app]=<id>&fields[builds]=version,uploadedDate,expirationDate,expired`
across all 8 apps on team `9W82X49JZS`:

| expirationDate | app | builds | age at death |
|---|---|---|---|
| `2026-08-26T06:19:58-07:00` | Glot — Language Decks | v2–v12 (10) | 36–58 d |
| `2026-08-26T06:19:58-07:00` | Ponte | v1 | 35 d |
| `2026-08-26T06:19:59-07:00` | Glot Echo | v1–v13 (13) | 73–77 d |
| `2026-08-26T06:19:59-07:00` | **Skrift** | v1–v4 | 70–73 d |
| `2026-08-26T06:20:00-07:00` | Onderons | v2 | **18 d** |

**29 builds, 5 apps, a 3-second window.** None are 90-day expiries.

The 90-day clock is demonstrably fine on this account, which is what makes this deliberate
rather than drift:

| app | uploaded | expired | age |
|---|---|---|---|
| GFR Field Recorder v1 | 2026-05-14 | 2026-08-12 | **exactly 90 d** |
| Shhhcribble iOS v3 | 2026-05-25 | 2026-08-23 | **exactly 90 d** |
| Skrift 166/167/168 | 2026-08-29 | **2026-11-27** | correct 90 d, still live |

Something reversed every live build on the account at **2026-08-26 13:20 UTC** — three days
before Skrift 166 was uploaded. Builds uploaded since get correct expiry dates and still
cannot be installed.

**This is a documented Apple fault with the identical fingerprint.**
[Thread 813703](https://developer.apple.com/forums/thread/813703), developer `apecchillo`:

> Hit this exact issue starting July 15, 2026 at 22:13 PT: all 23 TestFlight builds across all
> 4 apps in our account expired simultaneously (same 2-second window), including a build
> uploaded 35 minutes earlier.

> A fresh replacement build processes to VALID and appears in TestFlight, but every install
> fails with "The requested app is not available or doesn't exist" — internal testers included.

> Submitting it for Beta App Review via the ASC API returns 422
> ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING, despite a current membership and an Active Free
> Apps Agreement.

> Apple phone support confirmed on July 16 this is a backend issue on their side requiring
> senior-advisor reversal. They also said that there are "no senior-advisors available, so
> expect a 2 business day turnaround time."

Same thread, others: *"2-day old builds 'expired' for no reason"* (`ijoe2026`), *"All of my
builds are expiring in 30 minutes"* (`josephktncl`). And an Apple DTS Engineer, a week later:

> Thank you for your patience while the TestFlight team looked into the recent issue… May I
> ask you to please open the TestFlight app today and try installing the latest build again.

So it does get fixed, by Apple, on request.

## Apple built the install packages. They just will not serve them.

`GET /v1/builds/<id>?include=buildBundles` → `GET /v1/buildBundles/<id>/buildBundleFileSizes`:

| build | thinned variants Apple generated | Universal download / install |
|---|---|---|
| 4 (June, **installed 4×**) | **114** | 12,349,294 / 13,690,880 |
| 166 (404s) | **114** | 37,677,603 / 44,332,032 |
| 167 (404s) | **114** | 37,677,466 / 44,332,032 |
| 168 (404s) | **114** | 34,377,232 / 40,725,504 |

Ingestion, re-signing, thinning and per-device asset generation all **completed** on the
failing builds — same 114 variants as the build that installed fine. The device log's
`appSizeInBytes = 14958820` for build 166 is Apple's own generated iPhone variant size.

**So the 404 is not "the package does not exist". The package exists and Apple is refusing to
authorize the download.** That is exactly what a revoked/detached beta entitlement looks like,
and it kills every remaining theory in which the .ipa broke Apple's processing.

The re-signed (uploaded) entitlements are also correct — `beta-reports-active: true`,
`get-task-allow: false`, `aps-environment: production`,
`icloud-container-environment: Production` on all three failing builds.

## What App Store Connect actually says (ASC API, read-only, 2026-08-29)

Queried with `~/.appstoreconnect/private_keys/AuthKey_H3KF723D6Y.p8`
(key `H3KF723D6Y`, issuer `3eb0862f-0eef-4f03-b387-1cfd34e8ff34`).

| | Skrift **168** | Skrift 167 | Skrift 166 | Skrift **4** (June) | Onderons **2** | Ponte **1** |
|---|---|---|---|---|---|---|
| uploaded | 08-29 | 08-29 | 08-29 | 06-17 | **08-08** | 07-22 |
| processingState | VALID | VALID | VALID | VALID | VALID | VALID |
| audience | INTERNAL_ONLY | INTERNAL_ONLY | INTERNAL_ONLY | INTERNAL_ONLY | INTERNAL_ONLY | INTERNAL_ONLY |
| internalBuildState | IN_BETA_TESTING | IN_BETA_TESTING | IN_BETA_TESTING | EXPIRED | EXPIRED | — |
| inviteCount | 5 | 5 | 5 | 5 | 2 | 3 |
| **installCount** | **0** | **0** | **0** | **4** | **2** | **4** |
| sessionCount | 0 | 0 | 0 | 348 | 150 | 14 |
| `UIDeviceFamily` | **1** | 1,2 | 1,2 | 1 | 1 | 1 |
| icon Apple picked | 120×120 iPhone | 152×152 iPad | 152×152 iPad | 120×120 iPhone | — | — |

Everything ASC exposes for 166/167/168 reads healthy: attached to the one internal group
(`isInternalGroup: true`, `hasAccessToAllBuilds: true`), `usesNonExemptEncryption: false`,
`betaLicenseAgreement` returns 200, exactly two clean `preReleaseVersions` (0.1.0, 0.2.0),
no duplicates or orphans. All five testers are on the group. Every app-level attribute the API
exposes is identical across Skrift, Onderons and Ponte — `contentRightsDeclaration`,
`streamlinedPurchasingEnabled`, `isOrEverWasMadeForKids`, `appStoreState`, price schedule
(all three: baseTerritory USA, no manual prices) — only name, bundle id, SKU and locale differ.

⚠️ **Territory availability is the one thing the API cannot answer.** `appAvailabilityV2`,
`/v2/appAvailabilities/{id}` and `availableTerritories` all 404 for **every** app on this team,
submitted or not — that is a null result, not a match. An earlier version of this doc read it
as "identical, therefore not the cause". Wrong. **Only the ASC web UI shows it.**

⚠️ **The "Onderons proves the team is fine" argument is RETRACTED.** Onderons' 2 installs
happened between 2026-08-08 and the 2026-08-26 expiry — entirely *before* the event. Skrift's
failing builds were uploaded three days *after* it. The control sits on the wrong side of the
boundary and proves nothing about the current state. Onderons has no live build today, so it
cannot even be re-run without a fresh upload.

⚠️ **`installCount 0` is NOT strong evidence.** Apple documents that tester metrics can take
up to 24 hours to appear, and all three builds were inside that window when measured. Lead
with the device log, which is direct and does not lag. (Re-checked 2026-08-30: still 0 on all
three, now outside the window for 166 — but the log remains the better evidence.)

⚠️ **`betaLicenseAgreement` returning 200 proves nothing** — it returns an identical
`agreementText: null` object on Onderons and Ponte too. Dropped from the case.

## Why 0.1.0 is not the answer — killed on data

**There is no `0.2.0` App Store version record to be broken.** The app has exactly ONE
`appStoreVersion`: `1.0`, `PREPARE_FOR_SUBMISSION`, created 2026-06-14. `0.2.0` exists only
as a `preReleaseVersion` — the thing TestFlight groups builds under — and it is clean. The
install endpoint is keyed on `appID` + `buildID`, both of which resolved (they are in the
device log). A 0.1.0 (168) archive would fail identically and cost an Organizer distribute
to learn nothing.

## `UIDeviceFamily` — tested and dead (build 168)

Every build on this team that installs was `[1]`, iPhone-only; the only two that 404'd were
the only two that were `[1,2]`. Inside Skrift's own record the flip looked exact: builds 1–4
iPhone-only and installed, 166/167 universal and never. So 168 was archived as an exact copy
of 167 with `TARGETED_DEVICE_FAMILY: "1"`.

Apple accepted it as iPhone-only — its `iconAssetToken` came back `AppIcon60x60@2x.png` at
120×120, where 166/167 returned the 152×152 iPad icon. So the change genuinely took effect
server-side.

**It made no difference. 168: `VALID`, `IN_BETA_TESTING`, 5 invited, 0 installs, same
"requested app is not available" on the phone.** Device family is not the cause, and the
correlation was the shared upload date all along. `project.yml` is back to `"1,2"`.

⚠️ Correction: 168 is **not** "identical to 167 except device family" — an earlier draft of
this doc said so and it is false. Dropping the iPad slice also removed
`Frameworks/libswiftCompatibilitySpan.dylib` and the whole `SwiftSupport/` directory, and
halved `Assets.car` (4,355,448 → 2,186,664 bytes). That makes 168 a *stronger* exoneration —
three materially different packages all 404 — but do not put the false claim in a ticket.

## Already ruled out — do NOT re-check

| suspect | verdict | evidence |
|---|---|---|
| **Marketing version 0.1.0 → 0.2.0** | **no** | **only one appStoreVersion exists (`1.0`); `0.2.0` is a clean preReleaseVersion** |
| **`UIDeviceFamily` `[1,2]` → `[1]`** | **no** | **build 168 tested it: Apple accepted it as iPhone-only (120×120 icon) and it still 404s** |
| The build, generally | no | three builds, two device-family configs, all VALID, all 0 installs |
| ~~Account-wide cause~~ | **RETRACTED — it IS account-wide** | 29 builds across 5 apps force-expired in a 3-second window 2026-08-26. Onderons' installs predate it; Skrift is just the only app with a build uploaded after |
| Pricing and Availability | **no — settled in the UI** | Skrift's App Availability is entirely unset (empty "Set Up Availability"), and **Onderons is unset too and installs fine**. Not Processing, not the cause. Pricing unset on both. |
| Build not assigned to the group | no | one internal group, `hasAccessToAllBuilds: true`, 166 + 167 both attached |
| Tester invites | no | all 5 on the group; 4 of them installed June's build (348 sessions) |
| Minimum iOS too high | no | 18.0, same as June; failing device is an iPhone 17 |
| Bad/corrupt single upload | no | 166 and 167 fail identically, both `processingState: VALID` |
| Network / cellular | no | both phones, both Wi-Fi |
| `mlx-swift` CudaBuild plugin | no | `isCudaEnabled()` false off Linux → `createBuildCommands` returns `[]` |
| Wildcard profile on SkriftWidget | no | `9W82X49JZS.*` — June's widget carries the identical wildcard profile and entitlements |
| Malformed bundle | no | verified in `SkriftMobile-167.xcarchive`: correct nesting, no symlinks, `_CodeSignature` present, SPM resource bundles well-formed |
| Version skew across bundles | no | app `com.skrift.mobile`, `.share`, `.widget` — all three at `0.2.0 (167)` |
| Entitlements not on the App ID | no | the embedded profile grants `increased-memory-limit`, `icloud-container-identifiers`, `icloud-services`, `aps-environment`, app-groups |
| Mach-O / SDK | no | arm64, `platform 2`, `minos 18.0`, `sdk 26.5` |
| Export compliance | no | `usesNonExemptEncryption: false` on both builds |

`libswiftCompatibilitySpan.dylib` (new since June, in `Frameworks/` + `SwiftSupport/`) is the
normal Xcode 26 back-deployment shim, correctly placed and signed.

## What to do

Nobody has ever fixed this from the developer side. Every resolution on record is Apple
flipping something server-side. Three confirmed fixes, all via Apple Support, all in
[thread 778597](https://developer.apple.com/forums/thread/778597) — `Jonas_G` (Apr '26,
~2 weeks of silence then *"resolved within 48 hours"*), `TumayHeron` (Jun '26,
*"I have reached the support and they handled it"*), `dominik_` (Jun '26, fixed then relapsed).

Run **both** routes. They are different queues.

### Route A — Feedback Assistant + thread 813703. The only responsive Apple human.

[Thread 813703](https://developer.apple.com/forums/thread/813703) is the live one — 38 replies,
updated within the last two days, with DTS Engineer **Albert Pascual** actively routing
Feedback numbers and replying within hours. He is explicit that he is not on the TestFlight
team but routes the bug so that team can answer privately through Feedback Assistant.

**His one specific instruction is the thing most people get wrong — the sysdiagnose:**

> please make sure you upload the sysdiagnose as well… for the team to have actionable items
> to review.

So, in order:

1. Install Apple's **TestFlight logging profile** (`TestFlightLoggingProfile.mobileconfig`)
   from [developer.apple.com/bug-reporting/profiles-and-logs](https://developer.apple.com/bug-reporting/profiles-and-logs/).
2. Reproduce the failed install on the phone.
3. Take a **sysdiagnose immediately** (hold both volume buttons + side button ~1.5s; it lands
   in Settings → Privacy & Security → Analytics & Improvements → Analytics Data).
4. File in Feedback Assistant with the sysdiagnose, App ID `6780161319`, and the expiry table
   from *ROOT CAUSE* above.
5. Post the FB number into thread 813703, tagging the DTS Engineer.

### Route B — developer.apple.com/contact, Developer Program Support.

This is the route that produced all three confirmed fixes. Expect 1–2 weeks to first contact.
Apple publishes no dial-in number — [the contact form](https://developer.apple.com/contact/)
requests a callback ([worldwide telephone hours](https://developer.apple.com/support/worldwide-telephone-hours/)).

**Ask for a "senior-advisor reversal" by name.** That phrase is Apple's own internal mechanism
for this, from what phone support told `apecchillo` on 2026-07-16: *"this is a backend issue on
their side requiring senior-advisor reversal… there are no senior-advisors available, so expect
a 2 business day turnaround time."*

**Do NOT file a DTS Technical Support Incident.** [Code-level Support](https://developer.apple.com/support/technical/)
covers Apple frameworks, APIs and tools only, and explicitly excludes App Store Connect issues.

### Paste-ready

> TestFlight builds cannot be installed by any tester, including the Account Holder.
> Team `9W82X49JZS`, app **Skrift**, bundle id `com.skrift.mobile`, App ID `6780161319`.
>
> **This is account-wide, and it began with a mass build expiry.** On **2026-08-26 at
> 13:19:58–13:20:00 UTC**, 29 TestFlight builds across 5 of my apps were expired inside a
> 3-second window: Glot — Language Decks v2–v12, Ponte v1, Glot Echo v1–v13, Skrift v1–v4,
> Onderons v2. None were near 90 days — Onderons v2 was **18 days old**, Ponte v1 was 35.
> The 90-day clock works correctly on this account otherwise: GFR Field Recorder v1
> (2026-05-14 → 2026-08-12) and Shhhcribble iOS v3 (2026-05-25 → 2026-08-23) are both exactly
> 90 days, and my new builds get correct 2026-11-27 dates.
>
> Since that event, every new build fails to install. Skrift `0.2.0` builds **166, 167 and
> 168**, all uploaded 2026-08-29, are `processingState: VALID`,
> `internalBuildState: IN_BETA_TESTING`, `buildAudienceType: INTERNAL_ONLY`, attached to my
> internal group, 5 testers invited. On device: "Could not install Skrift. The requested app is
> not available or doesn't exist", with `failureReason: Error Downloading Install Data` and a
> 404 from `testflight.apple.com/v2/accounts/…/apps/6780161319/builds/<buildID>/install`.
> Three devices, including an iPad with a fresh TestFlight install.
>
> **The builds themselves are fine and your own systems say so.** For all three failing builds
> `/v1/buildBundles/<id>/buildBundleFileSizes` returns **114 thinned variants** — the same count
> as build `0.1.0 (4)`, which installed 4 times over 348 sessions. Ingestion, re-signing and
> asset generation all completed; the re-signed entitlements are correct
> (`beta-reports-active: true`, `get-task-allow: false`, `aps-environment: production`). The
> packages exist and are simply not being served.
>
> Skrift's builds are the only ones on my account uploaded after 2026-08-26, which is why this
> app is the one showing the symptom — the others have nothing installable left to test with.
>
> This matches Developer Forums threads **813703** and **814565**. Please perform the
> senior-advisor reversal on the beta contract for team `9W82X49JZS`.

### Meanwhile — Ad Hoc gets your 5 testers unblocked today

The bug is purely in TestFlight's delivery service. `kricke` in 813703, 5 days ago:
*"Works perfectly fine when installed via Xcode."* Signing and the binary are untouched.

Ad Hoc needs **no App Store Connect at all** — App ID, distribution cert, device list and
profile all live in Certificates, Identifiers & Profiles. You have 100 device slots per
product family per membership year.

Collect the 5 UDIDs → register them → create an Ad Hoc profile → Organizer → Distribute App →
**Ad Hoc** → choose **Production** CloudKit at export (TestFlight always forces production, so
this keeps testers on the same database) → hand out the `.ipa`, via Apple Configurator or an
HTTPS-hosted `itms-services://` manifest they tap in Safari.

Friction to plan for: **each tester must enable Developer Mode** (Settings → Privacy & Security
→ Developer Mode → restart) — Apple exempts TestFlight from this but not Configurator installs.
First launch also needs to reach `ppq.apple.com` or the app may not launch. No crash reports,
no update flow, no tester management: you re-send a file each time.

### Do not

- **Do NOT burn another build.** `erkanozsoy` in 813703 tested a **native Swift Hello World,
  build 1** and it 404s too. Nothing you compile changes this.
- **Do NOT change the bundle id** — reported as not working, and for Skrift it would orphan the
  App Group, the iCloud container and the whole CloudKit database.
- **Remove/re-add the build to the group** has no source tied to this failure mode; it is
  generic invite-sync folklore. Harmless, but do not spend a support round on it.

## Context you need

- Archives 165/166/167/168 are in Organizer, all verified well-formed. **167 is the one to
  re-distribute once Apple restores the contract** — it is the universal build. 168 exists
  only as the device-family experiment; it is iPhone-only and should not ship.
- `project.yml` is back to `TARGETED_DEVICE_FAMILY: "1,2"` and bumped to `CFBundleVersion 169`,
  so nothing can accidentally ship a second, different "168".
- **Nobody is blocked but the other testers.** Tuur's iPhone 13, iPad Pro and Mac all run this
  exact code as Dev builds (`com.skrift.mobile.dev`) over `devicectl`.
- Dev and prod are separate bundle ids and containers — installing or deleting one never
  touches the other.
- Bump `CFBundleVersion` in `project.yml` before every device/TestFlight build; the plists are
  generated, so that file is the only place it lives.
- Housekeeping, unrelated to this bug: the `SkriftShared` framework target in
  `Skrift_Native/SkriftMobile/project.yml:293` still carries `CURRENT_PROJECT_VERSION: "28"`
  while the app and both extensions are at 167. Harmless today (Apple only enforces
  app↔extension parity) — fold it into the next version bump.

## Sources

- [TestFlight Beta Contract Missing – ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING](https://developer.apple.com/forums/thread/814565) — the tracking thread
- [Processed internal TestFlight builds fail to install](https://developer.apple.com/forums/thread/818810)
- [TestFlight install fails: "The requested app is not available or doesn't exist" (Internal testing)](https://developer.apple.com/forums/thread/812811)
- [TestFlight users unable to update app](https://developer.apple.com/forums/thread/744799) — the 404 capture
- [ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING – External TestFlight unavailable, internal builds not downloadable](https://developer.apple.com/forums/thread/815893)
- ⭐ [TESTFLIGHT: The requested app is not available or doesn't exist](https://developer.apple.com/forums/thread/778597) — the **"Processing" territory** cause, quoted above, plus two developers whom Apple Support fixed
- [Could not install … not available or doesn't exist](https://developer.apple.com/forums/thread/673860) — "Removed from Sale" app state, and testers whose account country is outside the app's territories
