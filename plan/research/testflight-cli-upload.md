# TestFlight from the command line, no Xcode window (research 2026-10-01)

Local facts checked read-only on this Mac (Xcode 27.0, 27A266a):

- `security find-identity -v -p codesigning` lists `DD79A418CEE1B7406CC57D4CF65E4381C8F07703 "Apple Distribution: Tiuri Hartog (9W82X49JZS)"` as a valid identity, so its private key is in the login keychain. It expires 2027-06-10.
- App Store ("iOS Team Store Provisioning Profile") profiles already exist in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` for all three Release executables, and every one of them includes cert DD79A418:

| bundle id | profile UUID | created | expires | notes |
|---|---|---|---|---|
| com.skrift.mobile | cd5051fb-6d26-44c8-8c4c-6fece37f8a58 | 2026-08-29 | 2027-06-29 | has `group.com.skrift.mobile`, iCloud `iCloud.com.skrift.mobile`, `aps-environment=production` |
| com.skrift.mobile.share | 5e9ea8af-4844-4fe6-a832-56de4a23a561 | 2026-06-14 | 2027-06-10 | has `group.com.skrift.mobile` |
| com.skrift.mobile.widget | 4185862a-03f5-4416-8492-69c1daadd3a8 | 2026-06-14 | 2027-06-10 | no app group; the widget target requests none (`project.yml` comment at the widget target) |

- All three are `IsXcodeManaged=true` (made by the Organizer GUI uploads).
- glot-echo already ships this way. `/Users/tiurihartog/Hackerman/glot-study/echo/ExportOptionsManual.plist` uses `signingStyle=manual`, `signingCertificate=Apple Distribution` and two non-Xcode-managed profiles ("Glot Echo AppStore", "Glot Echo Widget AppStore"). Both profiles were created 2026-06-10 23:44, 11 minutes after cert DD79A418 was issued. The plist's comment says the "classic cert + profiles were created via the API".
- `Skrift_Native/SkriftMobile/ExportOptions.plist` has no `signingStyle` key. `xcodebuild -help` says: "Apps that were automatically signed when archived default to automatic … then Xcode will create provisioning profiles and managed cloud signing certificates as necessary". Our archive is automatically signed, so this export always asks for cloud signing.
- `SkriftShared.framework` is embedded too. It needs no profile.
- I did not read `~/.claude/projects/-Users-tiurihartog-Hackerman-glot-study/memory/glot-testflight-submit-config.md` or `reference_xcode_signing_keys.md`. The permission classifier blocked them as possible credential files. They may record the key's role.

## 1. What causes "Cloud signing permission error"

**What we saw:** `xcodebuild -exportArchive` with the ASC API key and `-allowProvisioningUpdates` failed with "Cloud signing permission error" and "No profiles for com.skrift.mobile{,.share,.widget} were found" (testflight.sh header, 2026-06-14).

**What others found:**
- The full error is `DeveloperAPIServiceErrorDomain Code=5 "Cloud signing permission error" … You haven't been given access to cloud-managed distribution certificates`. Keys with the Developer and App Manager roles fail. A key with the Admin role works. There is no setting that gives a lower-role API key the "cloud managed distribution certificate" access that a user can be given. Source: https://developer.apple.com/forums/thread/698117 (2022, still the canonical thread).
- WWDC21 session 10204: distribution cloud signing from `xcodebuild` needs an API key with the Admin role. https://developer.apple.com/wwdc21/10204 and the summary at https://wwdcnotes.com/documentation/wwdc21-10204-distribute-apps-in-xcode-with-cloud-signing/
- Program roles table: only Account Holder and Admin can create or revoke distribution certificates, create distribution profiles, or use cloud-managed distribution certificates. App Manager can upload builds. https://developer.apple.com/help/account/access/roles
- You can't edit a key after it is generated: "Once you generate an API key, you can't edit its name or access level. If you need to make changes, revoke the key and generate a new one." Revoked keys can't be reinstated. https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
- Even an Admin key fails in two known cases. With Developer ID there is a known bug: a local cert in the keychain is preferred over the cloud cert (Xcode 16.2, FB16835802): https://developer.apple.com/forums/thread/776036. The same error pair appears when an entitlement isn't approved for App Store distribution (Xcode 16, DTS reply): https://developer.apple.com/forums/thread/766722
- The role of key H3KF723D6Y is unconfirmed. Two pieces of evidence conflict. A key that minted the glot cert and profiles "via the API" would have to be Admin. But the Skrift memory note says `buildBundles` returns 403 for this key, and cloud signing failed. Both are consistent with an App Manager key, or with the glot cert being made by a different key.

**Fix:** stop asking for cloud signing. Use manual signing with the local cert and profiles (section 2). To keep automatic signing instead, revoke this key and generate a new Team key with the Admin role. The role can't be changed in place.

**Our next step:** add `signingStyle=manual` to the Skrift export plist (section 2). Leave the key's role as it is.

## 2. The non-cloud route: local cert and profiles, manual export

**What we saw:** the local cert and all three App Store profiles already exist (table above). Nothing new needs to be created today.

**What others found:**
- Export options: `signingStyle` (manual/automatic), `signingCertificate` (name, SHA-1, or selector such as "Apple Distribution"), and `provisioningProfiles` ("bundle identifiers … values are the provisioning profile name or UUID"). From `xcodebuild -help` on Xcode 27.0.
- Frameworks must not be listed in `provisioningProfiles`: https://developer.apple.com/forums/thread/680155 and https://developer.apple.com/forums/thread/696074
- Whether a manual export accepts Xcode-managed profiles is not confirmed. The error "is Xcode managed, but signing settings require a manually managed profile" is documented for build-time signing (https://discuss.bitrise.io/t/ionic-ios-automatic-code-signing-error-provisioning-profile-is-xcode-managed-signing-settings-require-a-manually-managed-profile/5139). I found nothing saying `-exportArchive` rejects them. Unverified locally, because the brief forbids signing.
- If new profiles or a new cert are ever needed (an expired cert, a new capability, or if the export rejects the Xcode-managed profiles):
  - fastlane `get_certificates` (cert) creates the private key and CSR itself, gets the certificate, and imports it into the keychain. It accepts `api_key_path`, so the owner never runs a CSR by hand. https://docs.fastlane.tools/actions/get_certificates/
  - fastlane `get_provisioning_profile` (sigh) takes `app_identifier`, `api_key_path` and `cert_id`, and "will never touch or use the profiles which are created and managed by Xcode". https://docs.fastlane.tools/actions/get_provisioning_profile/
  - The API key JSON needs `key_id`, `issuer_id` and `key`, or use the `app_store_connect_api_key` action with `key_filepath`. match, cert, sigh and pilot all support it. https://docs.fastlane.tools/app-store-connect-api/
  - Both cert and sigh need an Admin-role Team key. Only Admin or Account Holder can create distribution certs and profiles (https://developer.apple.com/help/account/access/roles). Individual keys can't use the provisioning endpoints (https://developer.apple.com/tutorials/data/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api.md).
  - fastlane is not installed on this Mac (`which fastlane` finds nothing). Homebrew is.
- To use the API directly: `POST /v1/certificates` takes a CSR (https://developer.apple.com/documentation/appstoreconnectapi/post-v1-certificates). A CSR can be scripted with `openssl req -new -newkey rsa:2048 -nodes`. The exact attribute names `csrContent`/`certificateType=DISTRIBUTION` and `profileType=IOS_APP_STORE` are unconfirmed: Apple's doc pages rendered empty when fetched.

**Fix:** create `ExportOptionsManual.plist` next to the existing one:
```
method=app-store-connect  destination=upload  teamID=9W82X49JZS
signingStyle=manual
signingCertificate=DD79A418CEE1B7406CC57D4CF65E4381C8F07703
provisioningProfiles:
  com.skrift.mobile        = cd5051fb-6d26-44c8-8c4c-6fece37f8a58
  com.skrift.mobile.share  = 5e9ea8af-4844-4fe6-a832-56de4a23a561
  com.skrift.mobile.widget = 4185862a-03f5-4416-8492-69c1daadd3a8
manageAppVersionAndBuildNumber=false   (default YES; we bump SKRIFT_BUILD in project.yml)
uploadSymbols=true
```
Export with `xcodebuild -exportArchive … -exportOptionsPlist ExportOptionsManual.plist -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_H3KF723D6Y.p8 -authenticationKeyID H3KF723D6Y -authenticationKeyIssuerID <issuer>`. Leave out `-allowProvisioningUpdates` so it cannot go to the cloud. If the Xcode-managed profiles are rejected, make three non-managed ones with sigh (Admin key needed) and reference them by name, as glot-echo does.

**Our next step:** run the manual export once with `destination=export` (no upload). The `.ipa` and its `codesign -d --entitlements` output show whether the Xcode-managed profiles are accepted.

## 3. Is `xcrun altool --upload-app` still alive in Xcode 26/27?

**What we saw:** Xcode 27.0's `altool` is version 27.0.5 (2.1) and still ships `--upload-app -f <file>`. It also has `--upload-package <file>` with `--wait` and `--build-status`. Auth is `--api-key <id> --api-issuer <id>`. It finds `AuthKey_<id>.p8` by itself in `~/.appstoreconnect/private_keys`. Xcode ships no `iTMSTransporter` in `ContentDelivery.framework/Resources` (only `altool` and `TransporterShim`).

**What others found:**
- Apple's upload page still lists altool (with `--upload-app`) alongside Xcode, Transporter, the API and Xcode Cloud. https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
- Bitrise changelog (2025-09-17): "'--upload-app' is deprecated". `--upload-package` takes optional inputs (app id, bundle id, versions) on Xcode 26. "Xcode 26 altool does not return failed exit code", so the output has to be parsed. https://discuss.bitrise.io/t/deploy-to-app-store-connect-application-loader-formerly-itunes-connect-v2-0-0/25564
- Xcode 26 altool may upload to the wrong app when another app's bundle id shares the prefix. Apple: "if a parameter is not supplied, and the bundle id prefix matches another app, it will simply upload to whichever one was updated most recently". The workaround is `--apple-id <numeric app id>`. https://developer.apple.com/forums/thread/803105
- Xcode 26.2 "Cannot determine the Apple ID from Bundle ID" (error 19) is fixed by passing `--apple-id`. https://help.codemagic.io/articles/6636894916-fixing-ios-build-errors-with-xcode-26-2-and-altool-verification-issues
- notarytool replaced altool for notarization only. It has no iOS upload command. Not found in an Apple doc; stated in the newly.app guide (https://newly.app/guides/app-store-connect-cli), which is unconfirmed.
- Uploads from a new Xcode are refused until App Store Connect allows that version (error 90534, Xcode 26.5 RC, 2026-05). https://developer.apple.com/forums/thread/825428. Whether Xcode 27.0 (27A266a) is accepted today is unconfirmed. Check https://developer.apple.com/help/app-store-connect/release-notes/

**Fix:** you don't need altool if the export uses `destination=upload`. If you upload separately:
`xcrun altool --upload-package build-archive/export/SkriftMobile.ipa --api-key H3KF723D6Y --api-issuer <issuer> --apple-id 6780161319 --wait`, then grep the output for `ERROR` and don't trust the exit code. 6780161319 is Skrift's ASC app id from the TestFlight memory note. Whether `--apple-id` is accepted with `--upload-package` on 27.0 is unconfirmed; the help text lists it only under asset packs.

**Our next step:** prefer `destination=upload`. Keep the altool line as the fallback.

## 4. The shortest path to one command with no Xcode window

1. Write `Skrift_Native/SkriftMobile/ExportOptionsManual.plist` as in section 2.
2. Change `testflight.sh`:
   - Read the key from `~/.appstoreconnect/private_keys/AuthKey_H3KF723D6Y.p8`.
   - Archive into a fresh `-derivedDataPath` (stale-DerivedData gotcha in the TestFlight memory note).
   - Export with the manual plist and without `-allowProvisioningUpdates`.
   - Add a pre-flight that fails if any of the three profile UUIDs or cert DD79A418 is missing or expires within 30 days.
3. Dry run: `destination=export`, then check the `.ipa` entitlements against the profiles.
4. Real run: `destination=upload`. Check that the build appears with `/v1/builds?filter[app]=6780161319` (read-only recipe in the memory note).
5. Owner, once, by hand: none for today's path. The archive already signs headlessly.
6. Owner, once, and only if step 3 rejects the Xcode-managed profiles or before 2027-06-10 when the cert and profiles expire: generate a new Admin-role Team key in ASC (Users and Access → Integrations → Team Keys). Download its `.p8` to `~/.appstoreconnect/private_keys/`. Then fastlane cert and sigh create everything with no Xcode window.
7. Owner, once, only for a new capability (for example App Groups on the widget): no CLI path was found that adds a capability without an Admin key. With an Admin key, the ASC API `bundleIdCapabilities` endpoint might do it (unconfirmed). Otherwise it is a developer.apple.com web visit, not Xcode.

## Things to try first

1. Export with `signingStyle=manual`, cert DD79A418 and the three profile UUIDs above, `destination=export`, no `-allowProvisioningUpdates`. This alone should remove the cloud-signing call (xcodebuild -help; forum 698117).
2. If that works, switch to `destination=upload` with the existing API key flags. App Manager is enough to upload (roles page). This is the whole one-command path.
3. Before 2027-06-10, or if step 1 rejects Xcode-managed profiles: have the owner create an Admin-role Team key, then use `fastlane cert` and `fastlane sigh` with `api_key_path`. Don't change H3KF723D6Y; Apple doesn't allow it, and EAS uses that key.
