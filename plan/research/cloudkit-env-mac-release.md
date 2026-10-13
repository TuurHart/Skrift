# CloudKit environment: local Release Mac build vs TestFlight phone

Researched 2026-10-13 for the Q366 OPEN line in `plan/RUN.md:358`. Read-only. No Bash was available, so the local checks below come from reading files Xcode wrote. I did not run `codesign`.

## 1. Development-signed Release Mac build, copied to /Applications, no `icloud-container-environment`

**What we saw:** `Skrift_Native/SkriftDesktop/SkriftDesktop.entitlements` sets `com.apple.developer.aps-environment = production` and has no `com.apple.developer.icloud-container-environment`. Which environment that build uses was unknown.

**Answer: Development.** Confidence high for build 188. It is inferred for the installed prod app, which nobody has checked.

Local evidence, from reading the build products of the Release build in `Skrift_Native/SkriftDesktop/build-release/` (build 188):
- `build-release/Build/Intermediates.noindex/SkriftDesktop.build/Release/SkriftDesktop.build/Skrift.app.xcent` is the entitlements file Xcode passes to codesign. It contains:
  - `com.apple.developer.aps-environment = development`. Xcode replaced the file's `production`.
  - `com.apple.security.get-task-allow = true`, which marks a development signature.
  - no `com.apple.developer.icloud-container-environment` key.
- `build-release/Build/Products/Release/Skrift.app/Contents/embedded.provisionprofile` is named "Mac Team Provisioning Profile: com.skrift.desktop", is Xcode-managed and has `ProfileDistributionType LIMITED` (a development profile). Its signing cert is "Apple Development: tiurihartog@icloud.com". The profile:
  - allows `com.apple.developer.icloud-container-environment = [Production, Development]`;
  - allows `com.apple.developer.aps-environment = development` only;
  - is locked to one provisioned device, `00008132-0014306A0E38801C`;
  - expires 2027-06-22.
- So `production` in the entitlements file never reaches the binary. Xcode rewrites `aps-environment` from the profile.

What others found:
- Apple CKContainer docs, "Testing Your Code Using the Development Container": "CloudKit uses your app's `com.apple.developer.icloud-container-environment` entitlement to discover whether you're using a `Development` or `Production` version of your provisioning profile." https://developer.apple.com/documentation/cloudkit/ckcontainer#Testing-Your-Code-Using-the-Development-Container
- Apple DTS (Ziqiao Chen), Aug 2025: "apps running on a device with Xcode by default use the `Development` environment … TestFlight and App Store apps by default use the `Production` environment." He checks the signed `aps-environment` value with `codesign -d --ent :-`. https://developer.apple.com/forums/thread/795826
- Apple `aps-environment` docs: "Xcode sets the value of the entitlement based on your app's current provisioning profile … if you're using a development provisioning profile, Xcode sets the value to `development`." https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment
- Quinn (DTS): a distribution profile's allowlist for `aps-environment` always contains `production`. https://developer.apple.com/forums/thread/703422
- Not found: an Apple statement of the exact rule cloudd applies when the key is absent. The answer above rests on DTS's "by default Development" for development-signed builds, plus the signed `aps-environment = development`.

Implication: the build configuration does not decide the environment. The signature does. A Release build signed with automatic development signing behaves like a Debug run from Xcode, so it uses the Development environment of `iCloud.com.skrift.mobile`.

The installed `/Applications/Skrift.app` (prod, e6245caa per RUN.md:358) was very likely built the same way, with `xcodebuild -configuration Release` and automatic signing. If so, the prod Mac has been reading and writing the Development environment of the prod container while the phone uses Production. Unverified: I did not read the prod app.

**Fix:** see section 3.

**Our next step:** run `codesign -d --entitlements :- /Applications/Skrift.app` and record whether `aps-environment` is `development` and whether `icloud-container-environment` is missing. If both hold, the prod Mac is on Development and the user's data is already split.

## 2. iOS app distributed through TestFlight

**What we saw:** the phone ships through TestFlight (last build 168, b46cd5ac). The current phone prod is build 170, an Ad Hoc build (e915d29b).

**Answer: Production, always, for TestFlight and the App Store.** Confidence high. Ad Hoc builds default to Production but can be switched in the export dialog.

What others found:
- Apple DTS (Ziqiao Chen), Aug 2026, Xcode 27.0 beta 5: "I don't see any way to change the iCloud environment for TestFlight distribution … we used to respect the value of the `com.apple.developer.icloud-container-environment` entitlement … It's not the case any more." For Custom → Release Testing (Ad Hoc): "There you can pick the iCloud environment. It is default to `Production`, and you can change it to `Development`." https://developer.apple.com/forums/thread/842909
- Forum answer, 2022: "TestFlight builds and releases in the store are unaffected by this entitlement—they will always use the production environment." https://developer.apple.com/forums/thread/707098
- Archived CloudKit Quick Start: "apps distributed via TestFlight or the store can't use the development environment." For Ad Hoc export, "you choose the development or the production environment". https://developer.apple.com/library/content/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html
- Apple staff, 2016: store uploads must carry `icloud-container-environment = Production`. Uploads have been validated for this since 2015-08-20. https://developer.apple.com/forums/thread/28387

**Fix:** nothing to fix for TestFlight. Build 170 (Ad Hoc) uses Production only if nobody picked Development in the export dialog.

**Our next step:** read the signed entitlements of the build-170 `.app` inside its IPA (`codesign -d --entitlements :- Payload/SkriftMobile.app`) and confirm `com.apple.developer.icloud-container-environment = Production`.

## 3. Making a locally installed, development-signed Mac app use Production

**What we saw:** the Mac must sync the same Production private database as the TestFlight phone. Today the signed binary carries nothing that selects Production.

What others found:
- Setting the key in the entitlements file works for development-signed builds, macOS included:
  - A macOS developer added `com.apple.developer.icloud-container-environment = production` to the entitlements: "now when I run the app in debug mode, it syncs with my production container" (NSPersistentCloudKitContainer, Nov 2022). https://developer.apple.com/forums/thread/719135
  - Same result on iOS with NSPersistentCloudKitContainer. The key must be in the `.entitlements` file, not Info.plist, and in the entitlements file of the configuration you actually build. https://developer.apple.com/forums/thread/707098
- The provisioning profile must allow the value. Otherwise macOS kills the app at launch:
  - 2015/2016 reports: "killed … because its use of the com.apple.developer.icloud-container-environment entitlement is not allowed", from a development export (radar 24383404). https://developer.apple.com/forums/thread/17854
  - Our local profile does allow it. `embedded.provisionprofile` (section 1) lists `icloud-container-environment = [Production, Development]`, so `Production` should pass. This is verified from the profile only; I have not seen a launch with the key set.
- Value spelling: Apple's documented values are `Development` and `Production`, capitalised. https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-container-environment
  - Apple staff's 2016 fix uses `<string>Production</string>`. https://developer.apple.com/forums/thread/28387
- Export alternatives:
  - **Development export with an environment picker.** Old Xcode's "Export a Development-signed Application" asked for the container environment and wrote the key. https://developer.apple.com/library/content/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html
  - The xcodebuild `-exportOptionsPlist` key `iCloudContainerEnvironment` does the same for non-App Store exports (Development or Production, default Development). https://gist.github.com/wilsolutions/e9533f6c32641af85e48b0f5ed380472 (copy of the `xcodebuild -help` text; run `xcodebuild -help` locally for your Xcode's wording)
  - DTS confirms the picker still exists for iOS Custom → Release Testing in Xcode 27 beta (thread 842909 above). Not found: confirmation that the macOS Custom → Debugging export in Xcode 26/27 still shows the picker.
  - **Developer ID (Direct Distribution).** Production is the norm, and the app runs on any Mac, not just provisioned device `00008132-…`. It needs a Developer ID certificate, a Developer ID provisioning profile that carries iCloud/CloudKit, and notarization. If that profile expires, the app stops launching. https://developer.apple.com/support/developer-id/
  - Write-up, Oct 2026: "builds you run from Xcode use development, while App Store and Developer ID builds use production." https://flaviocopes.com/mac-iphone-sync/
  - Not found: an Apple doc stating that the Developer ID export writes `icloud-container-environment = Production`. Verify on the exported app with codesign.
- Known trap for distribution-signed Mac builds: Core Data/CloudKit apps synced in debug but not after Developer ID or TestFlight signing until `CloudKit.framework` was added to "Frameworks, Libraries, and Embedded Content". Fix reported by the original posters only, never confirmed by Apple. https://developer.apple.com/forums/thread/719135 and https://developer.apple.com/forums/thread/717838
- Side effect I could not resolve: with development signing, Xcode still forces `aps-environment = development` (section 1). Not found: whether CloudKit silent pushes for the Production environment reach an app registered with sandbox APNs. Expect sync on push to be unreliable until checked. Polling or fetch-on-activate still works.

**Fix (recommended):** add this to the Release file `Skrift_Native/SkriftDesktop/SkriftDesktop.entitlements` only. The `.dev.entitlements` file stays as it is, because Dev uses the separate `.dev` container.
```xml
<key>com.apple.developer.icloud-container-environment</key>
<string>Production</string>
```
Keep the value literal, per the CLAUDE.md signing lesson. The existing Mac Team Provisioning Profile already allows it, so no new profile is needed for this Mac. Developer ID is the longer-term path if the app must run on a second Mac or outlive the 2027-06-22 profile.

**Our next step:** add the key, rebuild Release, then confirm:
- `Skrift.app.xcent` and `codesign -d --entitlements :- <built app>` show `Production`;
- the app launches without an AMFI "not allowed" kill;
- a new record appears in the CloudKit Console under the Production environment of `iCloud.com.skrift.mobile`.

Before installing, deploy the prod schema (RELEASE.md steps). A Production write of a missing field or record type fails, where Development created it silently.

## Things to try first
1. `codesign -d --entitlements :- /Applications/Skrift.app`. If it shows `aps-environment development` and no `icloud-container-environment`, the prod Mac has been on Development and the user's data is already split. Then decide how to reconcile it before the switch.
2. Add `com.apple.developer.icloud-container-environment = Production` to `SkriftDesktop.entitlements` and rebuild Release. Check the `.xcent` and codesign output, launch it, and confirm a write lands in the Production environment in CloudKit Console.
3. Deploy the missing Production schema listed in RUN.md:358 (MemoEditHead, the new Memo, MemoEnhancement and VocabularyRecord fields) before installing that build. Also confirm the build-170 Ad Hoc IPA carries `Production`.
