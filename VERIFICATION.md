# 0.3.5 — Native FixTool

The application, menu, window, documentation and packages now use **Native FixTool** (previously NI Fix Tool). The existing bundle identifier and local data locations are preserved so recognised libraries and preferences remain available. The private-use terms and their existing licence identifier are unchanged.

**33/33 native UI checks and 36/36 backend tests passed** after the corrected Native FixTool name, together with ESLint, Prettier, strict swift-format, zsh syntax and Python AST checks. Universal build and ad-hoc signature verification passed.

The rename changes no NI update/repair logic. Version 0.3.5 is prepared for a public pre-release under `kawlas/native-fixtool`; publishing status is verified separately. Earlier reports below retain their historical application name.

# 0.3.4 — Native Access style, 2026-10-20

- Universal AppKit build with process-local bundled Roboto (Google Fonts, SIL OFL 1.1).
- **33/33 native UI checks passed**, including actual bundled-font registration. Existing saved collection data is real; failure states remain explicitly simulated and preview writes disabled.
- **36/36 backend tests passed** on arm64; backend behavior is unchanged by the visual redesign.
- ESLint, Prettier, strict swift-format, zsh syntax and Python AST checks passed.
- Actual macOS Accessibility presses exercised the new navigation and text filter tabs; the Available tab changed its selected value. Regular and compact rendered views were inspected. A first visual draft lost button targets during cell replacement; the order was corrected and the final checks/real navigation passed.
- The Native Access light interface was inspected locally for typography and colors. No NI logos, artwork or font binaries were copied. The independently sourced Roboto licence is included in application resources and the source archive.
- A real GUI-driven George Duke Soul Treasures update completed (1.0.0 → 1.3.1): 472 existing files reused, 48 missing instrument files downloaded. The 48 HTTP 206 response bodies totalled **1,788,805 bytes**, compared with 3,857,478,175 bytes of complete content. The task log contains 48 initial checksum detections, exactly matching the 48 previously missing files, and no FATAL entries. The app was relaunched into 0.3.4 and recognised the same session and NI-confirmed result. Details: [live test](docs/TESTY-I-LINT.md).
- Independent post-update SHA-256/piece comparison matched **520/520** files against the same official NI artifact; 0 bytes remain missing/different.
- The actual Migration / Save library information button refreshed **332 receipts with 0 errors**. The portable George Duke receipt now retains the authentic NI 1.3.1 record.
- Collection after completion: **332/332 recognised**, no recovery/review entries or active jobs; 12 eligible library updates remain, plus Ozone which requires NI's installer.
- Physical second-Mac migration, physical Intel/macOS 14 testing and Developer ID notarisation remain unperformed. No Apple Developer credentials are available.
- Local evidence: `.build/qa-computer-use/` (not distributed).

# Verification — 0.3.3 (NI Fix Tool)

- **36/36 backend tests passed on arm64 and x64 under Rosetta.** New fault simulations cover PID-check permission errors, stale/invalid locks, rollback failure, concurrent record changes and piece reuse across stream boundaries.
- **32/32 native UI checks passed** with the final 0.3.3 build. Real saved scans were used; failure/cancellation/empty/busy/session states are explicitly simulated in read-only mode. Preview protections remained enabled.
- **Lint passed with no errors or warnings:** ESLint recommended rules with `--max-warnings 0`, Prettier, strict Apple swift-format, zsh syntax and Python AST parsing. Pinned npm packages are development-only; they are excluded from the app and source ZIP.
- A genuine official UPDATE was executed using the installed **0.3.2** engine: **Scene – Lotus 1.1.1 → 1.1.2**, exact original location. All 387 files / 1,292,603,943 bytes matched before submission. NI confirmed completion, and the full deployment log contained 387 successful verifications, 0 HTTP GET requests and 0 ERROR/FATAL lines. This is log evidence, not a measurement of all system network bytes.
- A separate post-update SHA-256 audit again matched **387/387 files** against the current official target manifest, with the same artifact and file names/sizes. The authentic portable receipt was refreshed. Raw XML equality was not used because signed URLs can change.
- The stale pre-update plan was correctly rejected after completion. Inventory remained **332/332 recognised**, and available updates decreased **14 → 13**. The other updates were not started.
- A fresh universal 0.3.3 app built successfully. Its update request adapter is unchanged except formatting; lock/rollback and cancellation diagnostics were improved and covered by the simulations above.

Full test details, scope and remaining limits: [docs/TESTY-I-LINT.md](docs/TESTY-I-LINT.md). At the 0.3.3 stage, that live update exercised reuse of already-matching files; the subsequent 0.3.4 section above records the additional live missing-file test. No physical migration, physical Intel or full accessibility certification is claimed.

## Earlier licensing verification — 0.3.2

Release 0.3.2 changes the original-code licence to NI Fix Tool Private Use License 1.0 and adds an unofficial/private-use notice to Start, Help, About and documentation. Third-party Node notices are preserved. Previously received older releases retain their original terms. No library-repair/update logic changes are included.

Completed checks: a fresh universal arm64/x86_64 build; **30/30 backend tests**; **25/25 native UI checks** in labelled read-only mode; zsh/Python syntax and documentation links. The app's original-code licence is byte-identical to the root LICENSE, and Node-LICENSE.txt is byte-identical to the pinned Node distribution's original notice. Ad-hoc signature verification passed. Historical functional verification remains below; no live NI installation or download was started for the licence change.

## Earlier audit verification — 0.3.1

The full working project was moved to the Desktop. Source, build scripts and the app do not require its previous absolute path.

- **30 backend tests passed** on arm64 after the audit fixes. New cases cover a late duplicate job, changed preferences/ownership/location, cancellation before submission, selective repair-download resumption and daemon version gating.
- JavaScript and zsh syntax checks passed.
- A clean universal build completed from the Desktop path, including spaces and a non-ASCII dash. Ad-hoc signature verification passed.
- The packaged backend read the current NI content preference and confirmed **332/332 registered library folders**, no recoverable/review rows and **14 available updates**. No update or repair was started for this review.
- Full Polish user/developer documentation and a reproducible shareable-source archive script were added. Historical scans, build evidence, old releases and runtimes remain local and are excluded from that source archive.

Additional completed checks:
- **30/30 backend tests also passed with the packaged x64 runtime under Rosetta.** This is not physical Intel testing.
- **25/25 native UI checks passed** with the newly built 0.3.1 app, in labelled read-only mode. Test input/output used a temporary folder after a Desktop file-access prompt blocked the first preview attempt; no OS permissions were bypassed. The test window was closed after use.
- All local documentation links resolve, and the source-archive Python script passes syntax parsing.

Audit findings, fixes and remaining limits: [docs/AUDYT-KODU.md](docs/AUDYT-KODU.md). Historical checks are retained separately.

## Earlier UI verification — 0.3.0

The 0.3 release changes the native UI and adds a read-only discovery command. It preserves the existing NI repair/update adapters and safety checks.

Executed checks:
- Existing 23 backend tests passed after the discovery command was added.
- `discover` read the actual NI content-folder preference without requiring a library argument, starting downloads or changing preferences.
- Packaged arm64 update analysis read 14 remaining updates. Packaged x64 Node under Rosetta read all 332 library folders as registered, with 0 recoverable and 0 review rows. Rosetta is not physical Intel hardware testing.
- **25 native UI checks passed.** They exercise the user-approved task names, familiar NI filters, nonempty recovery/problem fixtures, selection without writes, update review, read-only preview restrictions, both languages, native control roles and programmatic keyboard focus. Saved scans contain actual NI data; empty/busy/permission and example recovery states are explicitly simulated in read-only QA.
- Current-run before/after captures cover start, recovery, updates, migration, help, folder choice guidance, reading progress and denied-access guidance. Compact (980 × 700) and regular (1180 × 800) native windows were inspected. These are macOS layouts, not browser/mobile testing. Some regular-size automated captures omit compositor/layer content and are not accepted as complete-window evidence; compact captures and native control checks are retained.

No new library repairs, sample downloads or update installations were started for the UI redesign. The previous update verification is retained below. No physical second-Mac migration, full manual keyboard traversal, VoiceOver session, 200% OS zoom, macOS 14 device or physical Intel hardware test was performed. Native roles/focus checks do not establish full accessibility compliance.

The build is ad-hoc signed, not Developer ID signed/notarized. Public release still needs the distributor’s Apple signing credentials. No public upload was performed. Application support/portable vault paths retain the earlier Library Bridge name for compatibility.

## Earlier update verification — 0.2.0

Tested on the development Mac with Native Access 3.26.0 / NTKDaemon 1.32.0.

- **23 backend tests passed**, including partial-piece reuse estimates, exact target selection, ambiguous artifacts, path traversal, symlinks, manifest consistency, ownership, changed plans, duplicate jobs, UPDATE-only requests and completion at the exact registered location.
- Packaged x64 Node under Rosetta also read the live update catalogue successfully (14 remaining updates). This is not a physical Intel hardware test.
- **12 native UI smoke checks passed** with labelled, read-only real scan data, covering both languages, table/search/filter/navigation, preview write protection and the update route.
- The live update catalogue returned exactly 16 initially available updates, all content libraries with exact target artifacts. Metadata and current manifests were obtained through authenticated NI HTTPS requests without starting sample downloads.
- Soul Sessions: every one of 316 target files matched SHA-256; 431,780,962 bytes were already present. The app requested an official UPDATE (1.0.1 → 2.0.0). NI completed the deployment, logged 316 successful integrity checks with no errors, and confirmed version 2.0.0 at the original folder. No version field was edited directly by Library Bridge.
- An unrelated Nacht update was preserved and completed under NI's control. The remaining update count became 14. Those 14 updates were not started by Library Bridge.
- Estimates are derived from local byte comparisons and vendor piece hashes; they are not OS network byte measurements. A zero estimate does not imply zero metadata/protocol traffic.

No physical second-Mac migration, physical Intel hardware, macOS 14 machine or exhaustive VoiceOver/keyboard audit was performed. Existing 0.1.0 migration verification is retained below. The new release remains ad-hoc signed, not Developer ID signed/notarized; public release needs the distributor’s Apple credentials. No public upload was performed.

## Earlier migration verification — 0.1.0

Tested on the development Mac with Native Access 3.26.0, NTKDaemon 1.32.0 and protocol 8.1.4.

- Live read-only scans using both packaged arm64 Node and x64 Node under Rosetta recognised all 332 selected library folders as registered; no recoverable or review rows remained.
- 13 backend tests passed: identity and ownership checks, duplicates, existing locations, offline state, changed volume identity, missing/corrupt files, traversal and symlink refusal, cancellation, operation locks, authentic version restoration without overwrite, descriptor-only receipt refusal, and registry aliases.
- 10 native UI smoke checks passed using a clearly labelled read-only saved live scan: table data, write protection, search, filters, both languages, navigation and control actions.
- Universal AppKit executable built for arm64 and x86_64. Both bundled Node runtimes exercised the installed NI adapter. Ad-hoc signature verification passed.
- Portable vault contains 332 authentic registration receipts. Five descriptorless libraries have full SHA-256 inventories covering 4,118 files and 3,722,890,681 bytes. Other receipts preserve metadata and descriptor evidence, not a claim that every sample byte was audited.
- Separately, all 3,161 files for Hazy Days and Rare Vibrations matched their cached vendor manifests. Native Access then completed its own integrity checks and registration.

## Limits

No physical second-Mac migration, physical Intel Mac, macOS 14 machine, full VoiceOver audit or exhaustive manual keyboard traversal was tested. Rosetta is not a physical Intel test. Native Access versions other than 3.26.0 are rejected before registration writes. Development GUI access to removable storage encountered the normal macOS permission prompt; saved-scan UI tests do not substitute for granting that permission.

The local build is ad-hoc signed, not Developer ID signed or notarized. Public release requires the distributor’s Apple credentials and the included signing/notarization script. No public upload was performed.

Native Access owns installation/update behaviour. Existing matching files can be reused during vendor integrity checks; changed monolithic installers may still require complete downloads. The application does not promise universal delta updates or future vendor compatibility.
