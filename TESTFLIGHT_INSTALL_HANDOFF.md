# TestFlight: "Could not install Skrift" — handoff, updated 2026-08-29

**The marketing-version experiment is dead — do not run it.** Killed on ASC data, not
reasoning: there is no `0.2.0` App Store version record to be broken. The replacement
experiment is archived and waiting: **build 168, iPhone-only**. One Organizer distribute.

## The symptom

TestFlight shows the build. Tapping Install gives:

> **Could not install Skrift.** The requested app is not available or doesn't exist.

Two phones (iPhone 17, iPhone 13), both Wi-Fi. Two builds, `0.2.0 (166)` and `(167)`, fail
identically. ASC shows both as upload Complete + "Testing, expires in 90 days".
**5 invites, 0 installs.** June's `0.1.0 (4)` installed fine on the same setup.

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

| | Skrift 167 | Skrift 166 | Skrift **4** (June) | Onderons **2** | Ponte **1** |
|---|---|---|---|---|---|
| uploaded | 08-29 | 08-29 | 06-17 | **08-08** | 07-22 |
| processingState | VALID | VALID | VALID | VALID | VALID |
| audience | INTERNAL_ONLY | INTERNAL_ONLY | INTERNAL_ONLY | INTERNAL_ONLY | INTERNAL_ONLY |
| internalBuildState | IN_BETA_TESTING | IN_BETA_TESTING | EXPIRED | EXPIRED | — |
| inviteCount | 5 | 5 | 5 | 2 | 3 |
| **installCount** | **0** | **0** | **4** | **2** | **4** |
| sessionCount | 0 | 0 | 348 | 150 | 14 |
| `UIDeviceFamily` | **1,2** | **1,2** | 1 | 1 | 1 |

Everything ASC exposes for 166/167 reads healthy: attached to the one internal group
(`isInternalGroup: true`, `hasAccessToAllBuilds: true`), `usesNonExemptEncryption: false`,
`betaLicenseAgreement` returns 200, exactly two clean `preReleaseVersions` (0.1.0, 0.2.0),
no duplicates or orphans. All five testers are on the group.

**The team's TestFlight is not broken.** Onderons installed twice from a build uploaded
2026-08-08, three weeks *after* whatever broke Skrift. So this is not agreements, banking,
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

## The real remaining variable: `UIDeviceFamily`

Every build on this team that installs is `[1]`, iPhone-only. The only two that 404 are the
only two that are `[1,2]`. Inside Skrift's own record the flip is exact: builds 1–4 were
iPhone-only and installed (348 sessions); 166/167 are the first universal ones and neither
has ever installed. ASC also now represents these builds with the **iPad** icon
(`AppIcon76x76@2x~ipad.png`, 152×152) where June's used the iPhone one.

That is a correlation with a mechanism — flipping an existing app record from iPhone-only to
universal is a state change on Apple's backend, and a failed re-provision there produces
exactly a missing install package. It is **not proof**; universal builds obviously work for
everyone else, and the two failing builds share an upload date, so date is confounded.

It is, however, the one variable left that is both testable and inside the fault's boundary.

## Already ruled out — do NOT re-check

| suspect | verdict | evidence |
|---|---|---|
| **Marketing version 0.1.0 → 0.2.0** | **no** | **only one appStoreVersion exists (`1.0`); `0.2.0` is a clean preReleaseVersion** |
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

## What to do, in order

**1. Distribute build 168 — already archived and waiting.** `SkriftMobile-168.xcarchive`
in Organizer, identical to 167 except `TARGETED_DEVICE_FAMILY: "1"`. One variable, one
Organizer distribute (TestFlight Internal Only), one install attempt.

- **168 installs** → the universal switch is what this app record choked on. Restore
  `"1,2"` for 169 and try again; if 169 fails, the ticket now names Apple the exact trigger,
  which is worth far more than "it doesn't install".
- **168 fails** → the build is fully exonerated. Go to step 2.

**Either way, put `"1,2"` back before 169** — `project.yml` carries the `⚠️` markers, and
this branch must not merge to `main` carrying `"1"`. The iPad wave is shipped work.

**2. If 168 fails, open the case.** https://developer.apple.com/contact. The symptom set
matches Apple's open `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING` defect
([thread 814565](https://developer.apple.com/forums/thread/814565) — live since Feb 2026,
30+ developers, unresolved Aug 2026): the app's beta contract detaches server-side, every
ASC field keeps reading healthy, and only Apple can re-provision it. Also file it in
Feedback Assistant and post the FB number into that thread, which is where Apple DTS is
tracking it. Paste-ready:

> TestFlight internal builds cannot be installed by any tester, including the Account Holder.
> Team `9W82X49JZS`, app **Skrift**, bundle id `com.skrift.mobile`, App ID `6780161319`,
> builds `0.2.0 (166)` and `0.2.0 (167)` (build ID `232234897`). Both are `processingState:
> VALID`, `internalBuildState: IN_BETA_TESTING`, attached to our one internal group, 5
> testers invited, and `installCount` is 0 for both. On device, TestFlight shows "Could not
> install Skrift. The requested app is not available or doesn't exist"; the log gives
> `failureReason: Error Downloading Install Data` with a 404 from
> `testflight.apple.com/v2/accounts/…/apps/6780161319/builds/232234897/install`.
> Build `0.1.0 (4)`, uploaded 2026-06-17 the same way, installed 4 times over 348 sessions.
> Another app on the same team (Onderons, App ID 6799374697) installed normally from a build
> uploaded 2026-08-08, so this is not account-wide. The only structural change to Skrift
> between the build that installs and the builds that do not is `UIDeviceFamily` going from
> `[1]` to `[1,2]`. This matches Developer Forums thread 814565
> (`ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING`). Please check whether the beta contract for
> this app is present, and re-provision it.

**Do NOT change the bundle id.** It is a suggested workaround in some threads, it is reported
as *not* working in 814565, and for Skrift it would orphan the App Group, the iCloud container
and the whole CloudKit database.

## Context you need

- Repo `main` clean and pushed (`fc8777d6`). Archives 165/166/167 in Organizer, all verified
  well-formed — keep 167, it is the one to re-distribute once Apple restores the contract.
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
