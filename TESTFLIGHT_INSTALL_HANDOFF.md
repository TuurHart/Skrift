# TestFlight: "Could not install Skrift" — handoff, updated 2026-08-29

**The build is exonerated. This is Apple's, and it needs a support ticket.** Three builds,
two device-family configurations, all `VALID` in App Store Connect, all with **0 installs**.
Nothing left in this repo will fix it — go straight to *What to do*.

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
no duplicates or orphans. All five testers are on the group. Every app-level attribute is
identical across Skrift, Onderons and Ponte (`contentRightsDeclaration`,
`streamlinedPurchasingEnabled`, `isOrEverWasMadeForKids`, availability, price schedule,
`appStoreState`) — only name, bundle id, SKU and locale differ, and two of the three install.

**The team's TestFlight is not broken.** Skrift broke somewhere in the window
2026-06-17 → 2026-08-29 (nothing was uploaded in between). Onderons installed twice from a
build uploaded **2026-08-08 — inside that window**. So this is not agreements, banking,
tax, membership, or anything account-wide — Skrift's app record alone (App ID `6780161319`)
serves 404s. Skrift, Onderons and Ponte are identical on availability (all three: no
`appAvailabilities` record) and on `appStoreState: PREPARE_FOR_SUBMISSION`, so
Pricing and Availability is not it either.

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

## Already ruled out — do NOT re-check

| suspect | verdict | evidence |
|---|---|---|
| **Marketing version 0.1.0 → 0.2.0** | **no** | **only one appStoreVersion exists (`1.0`); `0.2.0` is a clean preReleaseVersion** |
| **`UIDeviceFamily` `[1,2]` → `[1]`** | **no** | **build 168 tested it: Apple accepted it as iPhone-only (120×120 icon) and it still 404s** |
| The build, generally | no | three builds, two device-family configs, all VALID, all 0 installs |
| Team-level agreement / banking / tax | no | Onderons installed 2× from a build uploaded 2026-08-08 on the same team |
| Pricing and Availability | no | Skrift, Onderons and Ponte all have **no** `appAvailabilities` record; two of three install |
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

**1. Open the support case — this is the whole remedy.** https://developer.apple.com/contact.
The symptom set matches Apple's open `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING` defect
([thread 814565](https://developer.apple.com/forums/thread/814565) — live since Feb 2026,
30+ developers, unresolved Aug 2026): the app's beta contract detaches server-side, every
ASC field keeps reading healthy, and only Apple can re-provision it. Also file it in Feedback
Assistant and post the FB number into that thread, where Apple DTS is tracking it. Expect
weeks, so file it today. Paste-ready:

> TestFlight internal builds cannot be installed by any tester, including the Account Holder.
> Team `9W82X49JZS`, app **Skrift**, bundle id `com.skrift.mobile`, App ID `6780161319`.
> Three builds fail identically: `0.2.0 (166)`, `(167)` and `(168)`, all uploaded 2026-08-29.
> All three are `processingState: VALID`, `internalBuildState: IN_BETA_TESTING`,
> `buildAudienceType: INTERNAL_ONLY`, attached to our one internal group
> (`hasAccessToAllBuilds: true`), 5 testers invited — and `installCount` is **0** on all three.
> On device, TestFlight shows "Could not install Skrift. The requested app is not available or
> doesn't exist." The log gives `failureReason: Error Downloading Install Data` with a 404
> from `testflight.apple.com/v2/accounts/…/apps/6780161319/builds/<buildID>/install`
> (build ID `232234897` for 166).
>
> Build `0.1.0 (4)`, uploaded 2026-06-17 to the same app record, same group and same testers,
> installed 4 times over 348 sessions. Nothing was uploaded between 2026-06-17 and 2026-08-29.
>
> This is not account-wide: another app on the same team, **Onderons** (App ID `6799374697`),
> installed normally from a build uploaded **2026-08-08 — inside that window**. Every
> app-level attribute is identical between the two records, including availability and price
> schedule.
>
> We have ruled out the build itself. Build 168 is byte-identical to 167 except
> `TARGETED_DEVICE_FAMILY` `[1,2]` → `[1]`, and it fails the same way, so it is not device
> family. `betaLicenseAgreement` returns 200 for this app.
>
> This matches Developer Forums thread 814565
> (`ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING`). Please check whether the beta contract for
> this app is present, and re-provision it.

**2. Two cheap things worth trying while the case sits.** Neither is likely; both cost
minutes and nothing is at risk.

- **Make a fresh internal tester group** in ASC, add the testers and build 168 to it, and
  install from that. The current group was created 2026-06-14; a new one is the closest thing
  to re-provisioning the per-app beta plumbing that is in your hands.
- **Expire 166 and 167**, leaving 168 as the only live build in the group.

**3. Confirming signal, if you want it.** ASC → Skrift → TestFlight → try to create a public
link. **"Beta contract is missing for the app."** would confirm the diagnosis outright and is
worth quoting in the case.

**Do NOT change the bundle id.** It is a suggested workaround in some threads, it is reported
as *not* working in 814565, and for Skrift it would orphan the App Group, the iCloud container
and the whole CloudKit database.

**Do NOT burn more builds.** Three uploads across two device-family configurations have now
produced the identical 404. A fourth teaches nothing until Apple has touched the record.

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
