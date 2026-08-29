# TestFlight: "Could not install Skrift" — handoff, updated 2026-08-29

**The build is not the problem, and neither is the marketing version.** The 2026-08-29
"revert to 0.1.0 and re-archive" experiment is dead — see *Why 0.1.0 is not the answer*.
Do not spend an Organizer distribute on it.

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

## DIAGNOSIS — `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING`

Apple backend defect, live since February 2026, 30+ developers in
[thread 814565](https://developer.apple.com/forums/thread/814565), still unresolved as of
August 2026. The per-app or team-level **beta contract detaches on Apple's servers**. The
reported symptom set is Skrift's, item for item:

- Build processes fine, shows "Ready to Test" / "Testing", visible in TestFlight.
- Every internal tester — the Account Holder included — gets "The requested app is not
  available or doesn't exist", 404 + "Error Downloading Install Data".
- Agreements, banking and tax all show **Active**; no pending agreements.
- External beta submission returns HTTP **422 `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING`**,
  and creating a public link says **"Beta contract is missing for the app."**
- New builds, new tester invites, reinstalling TestFlight, new app records: none of it works.
- Fix is a support case → Apple re-provisions the contract on the backend.

## Why 0.1.0 is not the answer

The marketing version is not a parameter of the failing request. The install endpoint is
keyed on `appID` + `buildID`; both resolved correctly (they are in the log). No case in any
of the reported threads involves a version string. A 0.1.0 (168) archive would fail the same
way and cost a manual Organizer distribute to learn nothing.

## Already ruled out — do NOT re-check

| suspect | verdict | evidence |
|---|---|---|
| **Marketing version 0.1.0 → 0.2.0** | **no** | **not a parameter of the 404'd request; no reported case involves it** |
| Minimum iOS too high | no | 18.0, same as June; failing device is an iPhone 17 |
| Internal-only restricts testers | no | all testers on the ASC team; June shipped the same way |
| Bad/corrupt single upload | no | 166 and 167 fail identically |
| Network / cellular | no | both phones, both Wi-Fi |
| `mlx-swift` CudaBuild plugin | no | `isCudaEnabled()` false off Linux → `createBuildCommands` returns `[]` |
| Wildcard profile on SkriftWidget | no | `9W82X49JZS.*` — **verified: June's widget carries the identical wildcard profile and identical entitlements** |
| Malformed bundle | no | verified in `SkriftMobile-167.xcarchive`: correct nested structure, no symlinks, `_CodeSignature` present, SPM resource bundles well-formed |
| Bundle id nesting / version skew | no | verified: app `com.skrift.mobile`, `.share`, `.widget` — all three at `0.2.0 (167)` |
| Entitlements not on the App ID | no | verified: the embedded profile grants `increased-memory-limit`, `icloud-container-identifiers`, `icloud-services`, `aps-environment`, app-groups |
| Mach-O / SDK | no | verified: arm64, `platform 2`, `minos 18.0`, `sdk 26.5` |
| Build state in ASC | no | Complete + Testing, compliance answered |

`libswiftCompatibilitySpan.dylib` (new since June, in `Frameworks/` + `SwiftSupport/`) is the
normal Xcode 26 back-deployment shim, correctly placed and signed.

## What to do, in order

**1. ASC → Skrift → Pricing and Availability.** The one cause in this class you control.
Set App Availability to all countries/regions and **Save even if it already looks right** —
several developers with this exact 404 found the app record had no availability committed.
Free, self-fixable, do it first.

**2. Split account-wide vs Skrift-only — free, no build.** Two other apps on team
`9W82X49JZS` uploaded to TestFlight this summer:

| app | bundle id | App ID | uploaded |
|---|---|---|---|
| Onderons | `tuurhart.onderons` | 6799374697 | build 2, 2026-08-08 |
| Ponte | `com.glot.ponte` | 6793568700 | build 1, 2026-07-22 |

Try installing either from TestFlight. **Both fail → team-level contract, one ticket covers
everything. They install → Skrift's app record alone is detached**, and the ticket names
App ID 6780161319 specifically.

**3. Confirm it.** ASC → Skrift → TestFlight → try to create a **public link** (or add an
external group and submit for beta review). **"Beta contract is missing for the app."** or a
422 `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING` confirms the diagnosis outright.

**4. Open the case.** https://developer.apple.com/contact — Apple has to re-provision it;
there is no developer-side fix. Also file it in Feedback Assistant and post the FB number
into [thread 814565](https://developer.apple.com/forums/thread/814565), which is where Apple
DTS is tracking this. Paste-ready:

> TestFlight internal builds cannot be installed by any tester, including the Account Holder.
> Team `9W82X49JZS`, app **Skrift**, bundle id `com.skrift.mobile`, App ID `6780161319`,
> builds `0.2.0 (166)` and `0.2.0 (167)` (build ID `232234897`). Both show Complete and
> "Testing, expires in 90 days" in App Store Connect. On device, TestFlight shows "Could not
> install Skrift. The requested app is not available or doesn't exist." The device log gives
> `failureReason: Error Downloading Install Data` with a 404 from
> `testflight.apple.com/v2/accounts/…/apps/6780161319/builds/232234897/install`.
> Build `0.1.0 (4)`, uploaded 2026-06-17 the same way, installed without a problem. 5 invites,
> 0 installs. This matches Developer Forums thread 814565
> (`ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING`). Please check whether the beta contract for
> this app / team is present, and re-provision it.

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
