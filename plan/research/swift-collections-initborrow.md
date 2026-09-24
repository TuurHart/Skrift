# swift-collections 1.7.0 + Xcode 27.0: `_swift_initBorrow` missing at launch on iOS 26.x

Researched 2026-09-24. Toolchain on this Mac: Xcode 27.0 (27A266a). Sim runtimes installed: iOS 26.3 (23D8133), iOS 26.5 (23F77).
Local checks were read-only against existing build products and a scratch xcodegen project in the session scratchpad.

## 1. Why swift-collections ≥1.7 references `swift_initBorrow`, and which runtime has it

**What we saw:** dyld aborts at launch on iOS 26.3/26.5 sims: `Symbol not found: _swift_initBorrow … Expected in: libswiftCore.dylib`.

**What others found:**
- Same symptom, same versions, filed upstream: [apple/swift-collections#733](https://github.com/apple/swift-collections/issues/733) "missing _swift_initBorrow at launch on iOS 26.5". swift-collections 1.7.0 (a66de878), Xcode 27.0 (27A266a), Swift 6.4, deployment target 18.6, iPhone 17 Pro Max sim on 26.5. Launches on iOS 27. The reporter traced the symbol to `InternalCollectionsUtilities/Optional+Extras.o` and `BorrowingIteratorProtocol+Extras.o`. Open, no maintainer reply as of 2026-09-24.
- Root cause is in the compiler: [swiftlang/swift#92574](https://github.com/swiftlang/swift/pull/92574) "Add proper availability for newly-introduced borrowing runtime functions" (DougGregor, opened 2026-09-24, rdar://188247062, approved by tbkka, not merged, targets `main`). The diff changes `swift_getBorrowTypeMetadata`, `swift_initBorrow` and `swift_dereferenceBorrow` in `include/swift/Runtime/RuntimeFunctions.def` from `AlwaysAvailable` to a new `BorrowingAvailability`, adds `FEATURE(Borrowing, (6, 4))`, and adds a test checking that `swift_initBorrow` becomes `extern_weak` below the 6.4 runtime. So Swift 6.4 in Xcode 27.0 treats these runtime calls as always present and strong-links them.
- 1.7.0 release notes: minimum toolchain Swift 6.2, and the package's own borrowing iterator types were replaced with the standard library's `Iterable` / `BorrowingIteratorProtocol` ([release 1.7.0](https://github.com/apple/swift-collections/releases/tag/1.7.0)).
- From reading the library source (checkout at `Skrift_Native/SkriftMobile/build/SourcePackages/checkouts/swift-collections`, tag 1.7.0): `Sources/InternalCollectionsUtilities/Optional+Extras.swift` builds a `Ref` from `Builtin.unprotectedAddressOfBorrow`, and `BorrowingIteratorProtocol+Extras.swift` returns `Ref<Element>?`. Both are inside `#if compiler(>=6.4)` and marked `@available(SwiftStdlib 6.4, *)`. `Package.swift:104` defines `SwiftStdlib 6.4` as `macOS 27.0, iOS 27.0, …`. The source availability is correct. The compiler ignores it for the runtime call.
- Related 1.7.0 regression on the same day: [apple/swift-collections#732](https://github.com/apple/swift-collections/issues/732), a new `@rpath/libswiftCompatibilitySpan.dylib` dependency that fails on an Intel Mac running macOS 15.8. Open.
- Same symbol on a real device (the path is `/private/var/containers/Bundle/Application/…`): [OpenFlutter/fluwx#776](https://github.com/OpenFlutter/fluwx/issues/776), opened 2026-09-24, no resolution.

**Verified locally:**
- `nm -m` on this worktree's 1.7.0 build: `Optional+Extras.o` and `BorrowingIteratorProtocol+Extras.o` both carry `(undefined) external _swift_initBorrow`, and `SkriftMobile.debug.dylib` has `(undefined) external _swift_initBorrow (from libswiftCore)`. The reference is strong (no `weak` marker). The dylib's `minos` is 18.0 and `sdk` is 27.0.
- `nm -gU` on the sim runtimes' `RuntimeRoot/usr/lib/swift/libswiftCore.dylib`: iOS 26.3 and iOS 26.5 do **not** export `_swift_initBorrow`. The iOS 27 simulator SDK's `usr/lib/swift/libswiftCore.tbd` does (line 8336).
- I compared 15 local `SkriftMobile.debug.dylib` builds. Two were built with swift-collections 1.7.0 and SDK 27.0, and both reference `_swift_initBorrow` once. Thirteen were built with 1.6.0 (SDKs 26.2, 26.5 and 27.0), and none reference it. That includes `agent-afc3389529eaf415c`, built with 1.6.0 and SDK 27.0. The trigger is 1.7.0 combined with the Swift 6.4 compiler. Xcode 27 alone does not cause it.

**The fix or workaround:** the real fix is swiftlang/swift#92574. It is unmerged and not in any Xcode release yet. Until a toolchain ships it, stay on swift-collections 1.6.0.

**Our next step:** pin swift-collections to 1.6.0 (see section 3). Watch #92574 and #733 for the toolchain or package release that carries the fix.

## 2. Upstream fix release, compiler flag or deployment-target setting

**What we saw:** fresh checkouts resolve to the newest swift-collections, and the brief says that is 1.7.0 or 1.9.0.

**What others found:**
- There is no fixed swift-collections release. The tags page ([apple/swift-collections/tags](https://github.com/apple/swift-collections/tags), fetched 2026-09-24) lists 1.7.0 (2026-09-23) as newest. The local SwiftPM cache (`~/Library/Caches/org.swift.swiftpm/repositories/swift-collections-9a58d5cf`) agrees. **I found no 1.9.0 tag.** All 25 local checkouts are 1.6.0 or 1.7.0. Treat "1.9.0" in the brief as unconfirmed.
- The compiler fix is [swiftlang/swift#92574](https://github.com/swiftlang/swift/pull/92574). It is open on `main`, and I found no cherry-pick to a release branch. No Xcode version is named.
- Compiler or linker flag: not found. No source documents a Swift or ld flag that weak-links this one runtime symbol. I did not invent one.
- Deployment target: the missing symbol only matters below the Swift 6.4 runtime, which is iOS/macOS 27 per the package's `Package.swift:104` and the `FEATURE(Borrowing, (6, 4))` line in #92574. Raising the app's deployment target to iOS 27 would avoid the crash, but the app would no longer install on iOS 26 devices. That is not a real option.
- `#if compiler(>=6.4)` guards the code (library source), so an older toolchain such as Xcode 26.x would not emit the call. That fits the 1.6.0/1.7.0 table above, but I did not rebuild 1.7.0 with Xcode 26 to confirm it.

**The fix or workaround:** pin to 1.6.0. Neither a flag nor a deployment-target change is viable.

**Our next step:** add a line to BUGS.md saying: "unpin swift-collections when a toolchain containing swiftlang/swift#92574 ships, or when #733 closes with a release".

## 3. Keeping a transitive dependency below a version in xcodegen, and whether real devices crash

**What we saw:** the generated `.xcodeproj`'s `Package.resolved` is gitignored, so every fresh checkout re-resolves to the newest swift-collections.

**What others found:**
- XcodeGen's `packages:` accepts `exactVersion`, `minorVersion` (up to next minor), `from`/`majorVersion`, `minVersion`+`maxVersion`, `branch` and `revision` ([XcodeGen ProjectSpec.md](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)).
- The conflict between a generated xcodeproj and an uncommitted `Package.resolved` is a known, still-open XcodeGen issue: [yonaskolb/XcodeGen#743](https://github.com/yonaskolb/XcodeGen/issues/743) (open since 2019). See also [#1460](https://github.com/yonaskolb/XcodeGen/issues/1460).
- Committing only `Package.resolved` through a gitignore exception (`*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/*` plus `!…/Package.resolved`) is described by [Christian Tietze](https://christiantietze.de/posts/2023/12/ignore-generated-xcode-xcworkspace-files-in-git-except-package-resolved/). [Jesse Squires](https://www.jessesquires.com/blog/2024/05/29/swiftpm-package-resolved-xcode/) reports that Xcode sometimes deletes `Package.resolved` and recommends restoring it from git.
- `xcodebuild -help` on Xcode 27.0 lists `-onlyUsePackageVersionsFromResolvedFile` and `-disableAutomaticPackageResolution`. Both refuse any version not recorded in `Package.resolved`.
- From reading library source (the checkouts' `Package.swift`): the only packages that declare swift-collections are `swift-jinja` and `swift-transformers`, both with `from: "1.0.0"`. A 1.6.0 pin satisfies both.

**Verified locally (scratch project, xcodegen 2.45.4, Xcode 27.0):**
- A top-level `packages:` entry `SwiftCollectionsPin: {url: https://github.com/apple/swift-collections, exactVersion: 1.6.0}` that no target depends on still becomes an `XCRemoteSwiftPackageReference` in the pbxproj. With it, `xcodebuild -resolvePackageDependencies` resolved `swift-collections @ 1.6.0` (revision a0cb0954) under swift-async-algorithms 1.1.5.
- The control run (same project, pin removed) resolved `swift-collections.git @ 1.7.0`. The pin URL has no `.git` suffix and the transitive URL does, but SwiftPM still treated them as the same package.

**Real device on iOS 26.x:** yes, it should crash the same way. The binary's reference is strong, and the iOS 26.3 and 26.5 runtimes' libswiftCore do not export the symbol. fluwx#776 shows the identical dyld error on a device path. That the device's libswiftCore matches the simulator's is an inference. **Not tested on the iPhone 13: unverified.**
- Separate risk for iOS 18–25 devices (the app's `minos` is 18.0): both the 1.6.0 and the 1.7.0 builds link `@rpath/libswiftCompatibilitySpan.dylib`, and neither embeds it in the `.app`. The iOS 26 sim runtimes ship it in `/usr/lib/swift`. Older OSes may not have it, which matches the failure pattern in #732. Not tested.

**The fix or workaround:** add the `exactVersion: 1.6.0` entry to `packages:` in `Skrift_Native/SkriftMobile/project.yml`, and to the desktop project.yml if it resolves swift-collections too. This is verified to work in scratch. Optionally, also commit `Package.resolved` through the gitignore exception so every other dependency stays pinned.

**Our next step:** add the pin, run `xcodegen generate`, then `xcodebuild -resolvePackageDependencies`. Confirm that `Package.resolved` shows 1.6.0, and that `nm -m …/SkriftMobile.debug.dylib | grep initBorrow` prints nothing before relaunching on the iOS 26.5 sim.

## Things to try first

1. Add `exactVersion: 1.6.0` for `https://github.com/apple/swift-collections` under `packages:` in both project.ymls. Regenerate, resolve and `nm`-check for `_swift_initBorrow`, then launch on the iOS 26.5 sim.
2. Commit `Package.resolved` through a gitignore exception, and have `gate.sh` pass `-onlyUsePackageVersionsFromResolvedFile`, so another fresh-checkout drift fails loudly.
3. Log a BUGS.md unpin trigger pointing at swiftlang/swift#92574 and swift-collections#733/#732. Before any App Store build that still targets iOS 18, check whether `libswiftCompatibilitySpan.dylib` needs to be embedded.
