# MinimalPaste → OpenShelf investigation

Research date: 2026-11-01, America/Los_Angeles. Goal: an independent free and open-source native macOS implementation with feature parity. Full behavioral equivalence is **not yet certified**.

## Target identity and evidence

- [Official product page](https://www.minimalpaste.com/) and [official download](https://www.minimalpaste.com/download), fetched November 1, 2026.
- Official download identifies **MinimalPaste 0.1.18, build 19**, bundle `app.clipshelf.Clipshelf`, minimum macOS 14, LSUIElement enabled.
- Downloaded DMG SHA-256: `d7cab4210b96265d7ed72ce97d34931c8749ba865595e104688cc4beda078767`.
- REA artifact inspection Evidence `ev_7c475bfe0ddd944f3c8e5fbc12b03c6f8402f70ae48205cfb130db83af9eac77`; nested inventory `ev_e298331a558a2987a8c9aedec354cd4316bd43f0ac621da4bd1b1becdb4c2374`. Graph manifest `agm_9528e4d705e3054aaa9f8118795240719612220aac0950e5bfcaeea518f6bb2d`: 170 nodes, 184 occurrences, no integrity contradictions reported.
- REA plist Evidence `ev_6a5c79f0056bcfdf79907482c66ceeed6f28d617fc418bc48425922d81f9e790`. Plist SHA-256 `433dc6d0de80ddfdf847534d095a792704c6e3c7f8aaf74b6d9353f0e33c19db`.
- Read-only native package inspection and bounded `strings` searches identified feature labels, settings keys, and Swift type names. These support feature candidates; they do not prove execution or original algorithms. No decompiled implementation was copied.
- Running-app accessibility inspection observed original General, History, and Appearance controls. It confirmed separate item colors / shelf backgrounds, window list / grid, history defaults of 1,000 items / one month, retention exemption for pinboards, folder tabs, and keyboard help.
- [Macfolio listing](https://macfolio.com/item/minimal-paste-search-clipboard-history-and-paste-faster) corroborates the public feature set. The official page supersedes secondary listings.

REA's DMG extraction operation reported that this format had no extraction reader. Native read-only mounting allowed metadata inspection. No claim of extraction success is made. All REA sessions were closed after use.

## Feature matrix

“Implemented” means the source contains the capability. Verification is tracked separately; untested does not mean equivalent.

| Capability | Original evidence | OpenShelf implementation | Verification / remaining gap |
|---|---|---|---|
| Local clipboard history | Official page, packaged labels | Native pasteboard polling, atomic local persistence | Automated save/reload and real-app restart recovery verified; long-running polling not certified |
| Text and rich text | Website and packaged types | Preserve original pasteboard representations | Rich HTML capture and restore tests pass |
| Images | Official page, packaged types | PNG/TIFF payload capture, display, copy/paste | Payload-preservation test passes; destination-app behavior pending |
| Links | Official page | Detection, search, browser opening | Detection exercised by demo; link metadata network/cache not exhaustively tested |
| Files, video, audio | Website, type-filter labels | File references, type filtering, Quick Look | Folder and missing-file tests pass; media playback depends on system Quick Look |
| Colors | Official page | Recognize hex and native color, render swatch | Demo hex color visually verified; native NSColor capture/restore covered by regression test |
| Global configurable shortcut | Official page, General UI | Carbon registered shortcut and recorder | Recorder changed to Shift-Command-Y and restored to Shift-Command-V; real invocation from TextEdit verified; collision UX pending |
| Live search and type filters | Website, settings labels | Search current history/group/folder, multi-type filters | Search reduced six demo clips to one; filters present in AX tree |
| Keyboard navigation | General UI help | Arrows, Return, Escape, Command-F, Command-1…9 | Save and Return demo paths verified; full shortcut matrix pending |
| Pins and colored named groups | Official page, packaged labels | Favorites + colored tabs, save picker, rename/delete, drag-to-group | Save-to-group and group filtering verified in demo; drag/drop pending |
| Pin retention exemption | Website, History UI | Pins and groups survive count/age pruning and clear history | Automated test passes |
| Folder and subfolder tabs | Website, General UI | Add/remove folders, enumerate newest-first, breadcrumbs | Stable IDs, containment, and file-preservation tests pass |
| Bulk select and paste | Official page | Command/Shift selection; newline text or multiple native payloads | Compound plain/HTML/RTF/RTFD writer; tests preserve bold text and image attachments; destination interoperability pending |
| Paste into previous app | Official page, Pasting labels | Restore prior app, verify activation, emit Command-V | Accessibility approval required for end-to-end check |
| Copy-only mode | Packaged Pasting labels | Setting and context-menu action | Core writer tested; UI fallback not exhaustively tested |
| Plain-text preference / Shift inversion | Packaged Pasting labels, General UI | Setting, Shift inversion, explicit action | Writer tests pass; full destination formatting comparison pending |
| Bottom / left / right / window | Official page, Appearance UI | Screen-aware geometry, attached/floating | Bottom, left, and window grid visually verified; right side pending |
| Window list / grid | Appearance UI | Compact rows and adaptive grid | Grid and left-side compact rows visually verified; window list still pending |
| Item color styles | Appearance UI | Colorful, Soft Light, Soft Dark | Controls verified; exact visual equivalence not claimed |
| Glass / frosted / image backdrop | Appearance UI, labels | Native material; image copy, blur, dim | Frosted visually verified; native Liquid Glass differs by OS |
| Confidential and password exclusion | Website and Privacy labels | Known apps + pasteboard markers + custom exclusions | Automated privacy test passes |
| Pause recording | Packaged menu/empty-state labels | Menu action and settings toggle | Core pause test passes |
| Age/count retention; clear history | Original History UI | Count/age settings, explicit clear, pin exemptions | Automated tests pass |
| Quick Look / browser opening | General UI | QLPreviewView for files, image/text preview, browser links | Text-file Quick Look verified with generated fixture; media/browser fidelity pending |
| Drag clips to tabs and other apps | Website / General labels | Own-process group references + native item providers | Compiled; end-to-end drag pending |
| Copy sound | Packaged Sounds labels | Native Pop sound on recorded copies | Compiled; audio check pending |
| Optional link metadata / local cache | Packaged Privacy labels | Apple's Link Presentation; disk cache; opt-in | Full URL hashed into a fixed-size key; network behavior not certified |
| Launch at login | General UI | SMAppService, approval/error handling | Requires installed bundle; not enabled during testing |
| Onboarding / menu bar / settings | Running UI and packaged labels | Native first-run notice, status menu, categorized settings | Shelf + settings runtime verified; wording and onboarding flow differ |
| Automatic signed updates | Plist + packaged update strings | Sparkle 2.9.6; signed appcast and archive generation; public GitHub release channel | Public signed feed/archive verified; released app reports up to date; update installation remains pending |
| License / trial / three-Mac limit | Official page | Removed: unrestricted MIT use | Intentional change required by free/open-source goal |

## Implementation decisions and unknowns

OpenShelf uses public SwiftUI, AppKit, Carbon hotkeys, Link Presentation, Quick Look, and Service Management. Its MIT license covers the independently written source, not the original product.

On macOS 26 and newer with a recent compiler, the glass background uses native SwiftUI Liquid Glass. macOS 14–15 and older compilers use native material as a fallback. The exact original animations, ranking, dedup rules, retention intervals, clipboard format priority, multi-selection order, link cache policy, and source-app attribution rules remain unknown. The implementation makes explicit conventional choices rather than claiming these are recovered originals.

History currently serializes binary representations into a local JSON document. Large image histories need performance and memory testing before claiming production parity. Folder search filters the current directory; recursive all-descendant search semantics in the original have not been established.

The original executable and artwork remain research-only outside this distributable project. No license validation was bypassed. No proprietary backend, signing key, or source is included.


## Native bulk-paste follow-up

The arm64 executable SHA-256 is `766055ea4249b462cf0d8d59e038529237187db5d52e9c0ee2981f6397711873`. Hopper literal procedure-name search for PasteboardWriter returned no named procedures (Evidence `ev_86298beaafae3af148d2f5ebbeba79b0c63adde344caa1535fbcb302bf3bae68`); this was a bounded name search, not proof of absent code.

Source-filename string search found `MinimalPaste/PasteboardWriter.swift` at `0x10018cb30` (`ev_2c0c8c78bb2521a6c88cf8c27cc6c28c6c15ed8246fd1795afbfa5c2568e209b`). Its references (`ev_917d6280fa0dfd018a4f5f66298aebd0c244525cf0c5ca947a4fb672697398f8`) led to writer `0x1000acc64` (`ev_c3c84b020c22961db07406286d04c41c9300413cff324cdc033a38ad97d47133`) and compound helper `0x1000aa214` (`ev_a8831bd59ce172de21c3da84f5e0ed3af13cc6a57a3e370357315457aa026172`). The static helper contains newline joining, attributed-string appends, RTF/RTFD serialization, HTML output, and embedded PNG data-URL construction. These observations support rich mixed bulk-paste capability; they do not prove every runtime branch or precise output equivalence. Hopper does not expose complete function-body ranges through its public API. The REA session was closed afterward.

OpenShelf's independently written `PasteComposer` now constructs one compound item, preserving native rich formatting and image attachments, with HTML and plain-text alternatives. HTML-only producers retain their source markup as clipboard data; OpenShelf does not import it through a web renderer that might fetch remote resources.

## Platform implementation references

The Liquid Glass implementation follows [Apple's custom-view guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). Direct paste now checks [Core Graphics event-posting access](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess%28%29), the capability used by its keyboard event. [Apple's signing requirements note](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) explains why an ad-hoc build's identity is tied to a specific binary; the observed permission mismatch is not yet attributed to one cause. Update integration follows [Sparkle's setup guide](https://sparkle-project.org/documentation/) and uses the stable 2.9.6 release.
