# Moving imported Apple Notes into "Imported to Skrift" / "Not imported yet"

Researched 2026-09-30, open web only, no project code read, no Notes data opened. Local checks were
read-only against `/System/Applications/Notes.app` (Notes 4.13, macOS 26.6 build 25G72): `sdef`, its
Info.plist, `/System/Library/ScriptingDefinitions/CocoaStandard.sdef` and `man 5 sdef`. Nothing was
run against Notes, so every "works" below is **unverified on this Mac** until the test in "Things to try first".

## 1. Create a folder and move a note by script; iCloud, sync, permission

**What we saw:** the plan needs Notes to create two folders and move each imported note into one of them.

**What others found:**
- The dictionary allows it. Notes pulls in the Cocoa standard suite, which defines `make` ("Create a new
  object") and `move` ("Move an object to a new location"). `folder` has `folder` and `note` elements, and
  `account` has `folder` elements (from reading `sdef /System/Applications/Notes.app` and `CocoaStandard.sdef`).
  Notes sets `NSAppleScriptEnabled = true` (its Info.plist).
- Working JXA from third-party automation docs: `Notes.move(noteSpecifier, { to: targetFolder })`, and a
  missing folder is created with `f = Notes.Folder({ name: seg }); container.folders.push(f)` under
  `Notes.accounts.byName("iCloud")` ([automating-notes skill](https://skillselion.com/skills/spillwavesolutions/automating-mac-apps-plugin/automating-notes)).
  PyXA wraps the same call as `note.move_to(folder)` (same page).
- **Moves across accounts break.** "Native AppleScript moves across accounts can trigger a Core Data
  cross-store save error"; one MCP server works around it by copying and then deleting, which gives the note
  a new ID ([apple-notes-mcp](https://glama.ai/mcp/servers/taylorarndt/apple-notes-mcp)). The skill doc above
  says the same: "Crossing accounts effectively copies and may change IDs". So each account (iCloud,
  On My Mac, Gmail…) needs its own pair of folders.
- Sync: iCloud keeps notes and folders the same on every device signed in to the account
  ([Apple: Add and remove folders in Notes on Mac](https://support.apple.com/en-al/guide/notes/apd558a85438/4.13/mac/26)).
  A page confirming that a **scripted** move syncs to the iPhone: not found. It is likely, because the command
  runs inside Notes.app's own model (`ICScriptingNote`, `ICScriptingFolder` in the sdef), the same place a
  drag lands. Still unconfirmed.
- Whether a move changes the note's modification date or its `ZIDENTIFIER`: not found.
- Permission. A hardened-runtime app needs the `com.apple.security.automation.apple-events` entitlement,
  "whether the app may prompt the user for permission to send Apple events to other apps"
  ([Apple entitlement doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)).
  It also needs `NSAppleEventsUsageDescription`, which "is required if your app uses APIs that send Apple
  events" ([Apple Info.plist doc](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)).
  The user sees an Automation prompt once and can change it later in Privacy & Security > Automation.
- Shortcuts also has "Create Folder" and "Move Notes to Folder" (added in iOS 16 / macOS 13)
  ([Matthew Cassinelli](https://matthewcassinelli.com/ios16-actions-shortcuts/)). Whether Shortcuts can pick
  a note by its UUID: not found.

**The fix or workaround:** `make new folder at account "iCloud" with properties {name:"Imported to Skrift"}`,
then `move note id "<x-coredata id>" to folder "Imported to Skrift" of account "iCloud"`. Always target the
folder **in the note's own account** and never move across accounts.

**Our next step:** on a throwaway iCloud note, run the move from `osascript`, then check on the iPhone 13 that
the note shows up in the new folder, and compare its modification date before and after.

## 2. Matching an AppleScript note to the database UUID

**What we saw:** the importer knows `ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER`, but AppleScript addresses notes as
`x-coredata://…/ICNote/p123`.

**What others found:**
- A Core Data URI is `x-coredata://<store UUID>/<Entity>/p<Z_PK>`. The `p` number is the row's `Z_PK`, and
  the UUID identifies the store file and "usually does not change"
  ([fatbobman, NSManagedObjectID](https://fatbobman.com/en/posts/nsmanagedobjectid-and-persistentidentifier/)).
  The store UUID lives in `Z_METADATA` ([fatbobman, Core Data tables](https://fatbobman.com/en/posts/tables_and_fields_of_coredata/)).
- For Notes specifically, a published script (Ventura, 2022) strips the `p` from the AppleScript id and runs
  `SELECT ZIDENTIFIER from ZICCLOUDSYNCINGOBJECT WHERE Z_PK = <n>` to get the UUID
  ([Hook forum, zsbenke](https://discourse.hookproductivity.com/t/using-the-built-in-notes-url-scheme/6071)).
  AppleScript accepts `first note whose id is "x-coredata://…"` (same source).
- Core Data tracks the highest used `Z_PK` per entity in `Z_PRIMARYKEY` so IDs stay unique
  (fatbobman, Core Data tables, above). A deleted note's number therefore should not point at a different
  note later. No test of that was found.
- The AppleScript id is local to one Mac and is useless on another device
  ([gig3m/applenotes](https://github.com/gig3m/applenotes), cited in `apple-notes-export.md`).

**The fix or workaround:** go the other way from the Hook script. Read `Z_PK` next to `ZIDENTIFIER` at import
time. Right before moving, take the store-UUID prefix from any live AppleScript id (for example the account's
`id`), build `x-coredata://<UUID>/ICNote/p<Z_PK>`, fetch that note, and **check its `name` against `ZTITLE1`**
before moving it. If they differ, skip the move and leave the note where it is. Never cache the x-coredata
string across runs.

**Our next step:** on the throwaway note, confirm that the built id resolves to the right note and that the
account id carries the same store UUID as `Z_METADATA.Z_UUID`. Both are unverified.

## 3. Writing NoteStore.sqlite directly

**What we saw:** the SQL route would be one `UPDATE … SET ZFOLDER = …`. The answer is no.

**What others found:**
- Notes keeps note bodies as CRDTs so edits from several devices can merge
  ([Simon Willison](https://simonwillison.net/2021/Dec/9/notes-on-notesapp/)). A row changed behind its back
  goes through none of that sync machinery. Which columns mark a change as "needs upload": not found.
- A real case, 2026-08-05: an AI tool edited Bear's own SQLite database directly and iCloud sync broke on Mac
  and iOS. Bear support: "the only way to return to a normal situation is to reset your online data"
  ([Bear community](https://community.bear.app/t/using-ai-to-operate-the-app-it-directly-modified-the-sqlite-database-causing-icloud-sync-to-become-unavailable/19693)).
- Even when you know the schema, "it is still best to avoid directly manipulating the database as Apple may
  change its underlying implementation at any time"
  ([fatbobman](https://fatbobman.com/en/posts/tables_and_fields_of_coredata/)).
- File level: a copy of the database that is paired with the wrong or missing `-wal` journal, or two
  connections that do not see each other's locks, lead to corruption ([sqlite.org, How To Corrupt](https://www.sqlite.org/howtocorrupt.html)).
  Notes has the file open the whole time. Obsidian reads a copy for this reason (`apple-notes-export.md` §4).
- Apple's rule for Mac App Store apps is to use "only … the appropriate macOS APIs for modifying user data
  stored by other apps" ([App Review 2.4.5(i)](https://developer.apple.com/app-store/review/guidelines/)).

**The fix or workaround:** keep the database strictly read-only (open a copy, or open with
`?mode=ro`). Do every change through Notes, via Apple Events or Shortcuts.

**Our next step:** make the importer's SQLite open call read-only and add a test that fails if the
connection can write.

## 4. Sandboxed Mac App Store build: DB read and Apple Events

**What we saw:** the feature needs Full Disk Access (for the DB) and Apple Events to Notes (for the move).

**What others found:**
- **FDA does not lift the sandbox.** Quinn (Apple DTS), Nov 2025: granting FDA to a sandboxed app "doesn't
  bypass the App Sandbox checks. The app will only be able to access items within its static or dynamic
  sandbox" ([forums 807142](https://developer.apple.com/forums/thread/807142)).
- An unsandboxed launch agent **with** FDA still could not list `group.com.apple.notes`. Quinn blamed the
  macOS 14 container data protection: "AFAIK there's no way to bypass this"
  ([forums 740455](https://developer.apple.com/forums/thread/740455), Oct 2023). Unsandboxed apps holding FDA
  do read the store, though (loran, Obsidian; see `apple-notes-export.md` §1). So the rule depends on which
  process holds the permission, and the exact rule is unconfirmed.
- Whether a sandboxed app can read the store after the user picks the `group.com.apple.notes` folder in an
  open panel: not found.
- **Apple Events to Notes from a sandboxed app are not allowed on the store.** Notes declares one scripting
  access group, `com.apple.Notes.openlocation`, and it covers only `open note location` (from reading the
  sdef). The `move`/`make` commands are open to any group (`access-group identifier="*"` in
  `CocoaStandard.sdef`), but "any element without an access group is not accessible from a sandboxed
  application" (`man 5 sdef`), and `note` and `folder` have none. An Apple DTS engineer, Aug 2026, answering
  exactly this question for Notes: "It is not permitted to utilize a temporary exception to circumvent the
  sandbox restrictions … there is no direct, publicly accessible API that enables a sandboxed application to
  create a system Note" ([forums 840990](https://developer.apple.com/forums/thread/840990)).
- How the Mac App Store app "Exporter" gets at Notes: not found.

**The fix or workaround:** ship the Notes import and the folder moves in a **Developer ID (notarized),
non-sandboxed** build, with the Apple Events entitlement and usage string from §1. A Mac App Store build
cannot read the store via FDA or move notes by Apple Events. The only store-safe route found is a
user-installed Shortcut ("Move Notes to Folder") opened by URL, and whether that can target one note by ID is
not found.

**Our next step:** write down in SPEC.md Decisions which Mac distribution this feature ships in, before any
code.

## 5. Locked notes through AppleScript

**What we saw:** the importer has to know about locked notes and should not break on them.

**What others found:**
- The dictionary has `password protected` (boolean, read-only) on `note` (from reading the sdef). So
  AppleScript can tell that a note is locked.
- In the database, a locked note's title (`ZTITLE1`), dates and folder are not encrypted. The body and
  attachments are ([Ciofeca Forensics](https://www.ciofecaforensics.com/2020/07/31/apple-notes-revisited-encrypted-notes/)).
  Both public parsers read `ZISPASSWORDPROTECTED` (from reading the library source:
  [apple_cloud_notes_parser `lib/AppleNoteStore.rb`](https://raw.githubusercontent.com/threeplanetssoftware/apple_cloud_notes_parser/master/lib/AppleNoteStore.rb),
  [obsidian-importer `src/formats/apple-notes.ts`](https://raw.githubusercontent.com/obsidianmd/obsidian-importer/master/src/formats/apple-notes.ts),
  which skips any row where it is set).
- macnotesapp 0.8.2 (AppleScript based): "unlocked password-protected notes can be accessed but locked notes
  cannot" ([PyPI](https://pypi.org/project/macnotesapp)). Whether AppleScript `name` returns the title of a
  locked note, and whether `move` works on one: not found. The only claims found come from AI-generated skill
  pages, so they are not used here.

**The fix or workaround:** take the title and the locked flag from the DB (`ZTITLE1`,
`ZISPASSWORDPROTECTED`) rather than from AppleScript. Never read `body`/`plaintext` of a note with
`password protected = true`.

**Our next step:** lock the throwaway note and record what `name`, `body`, and `move` return for it.

## Things to try first

1. **Decide distribution first** (§4). The DB read and the Notes moves both need a non-sandboxed Developer ID
   build. On the Mac App Store neither works, per two Apple DTS answers.
2. **One throwaway-note run** in a test iCloud folder the user creates: build the x-coredata id from
   `Z_METADATA`+`Z_PK`, `make` the folder, `move` the note, then check it on the iPhone 13. Repeat with the
   note locked. This settles §1 sync, §2 matching and §5 in about ten minutes.
3. **Flag the side effect before building:** moving every unimported note into "Not imported yet" wipes out
   his existing folder layout. Moving only imported notes into "Imported to Skrift" keeps it. Shortcuts'
   "Add Tags to Notes" would mark notes without moving them, but AppleScript cannot add tags
   ([macnotesapp limitations](https://pypi.org/project/macnotesapp)).
