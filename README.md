# Native FixTool

Wcześniejsza nazwa: NI Fix Tool. Nowa nazwa nie zmienia warunków licencji.

**Nieoficjalne, niezależne narzędzie. Wyłącznie do bezpłatnego użytku prywatnego.** Korzystanie przez firmy i organizacje oraz do celów zawodowych lub komercyjnych jest zabronione. Nie jest produktem Native Instruments i nie jest przez tę firmę wspierane ani zatwierdzone. Narzędzie nie zastępuje licencji na produkty Native Instruments.

## Licencja

Od wydania **0.3.2** własny kod, aplikacja i dokumentacja są objęte [Native FixTool Private Use License 1.0](LICENSE), identyfikator `LicenseRef-NI-Fix-Tool-Private-Use-1.0`. To własna licencja wyłącznie do użytku prywatnego, nie MIT ani licencja open source. Źródła są dostępne na określonych w niej warunkach.

Osoba fizyczna może korzystać prywatnie i hobbystycznie. Zakaz obejmuje użycie na rzecz firmy lub organizacji, a także pracę zawodową, zlecenia, działalność gospodarczą i freelancing. Samo poinformowanie autora nie zezwala na użytek firmowy. Node.js i jego zależności oraz krój Roboto (SIL OFL 1.1) zachowują własne licencje. Warunki wcześniej zgodnie z prawem otrzymanych kopii starszych wydań pozostają bez zmian.

The original code, app and documentation are licensed for **private personal use only**. Company, organisational, business, commercial and professional use is prohibited. See [LICENSE](LICENSE); third-party components retain their own licences.

## Dokumentacja po polsku

- [CZYTAJ NAJPIERW.html](CZYTAJ%20NAJPIERW.html) — otwórz dwuklikiem, aby zacząć.
- [INSTRUKCJA.md](INSTRUKCJA.md) — wszystkie zadania, przyciski i typowe problemy.
- [Architektura i mapa plików](docs/ARCHITEKTURA.md).
- [Budowanie, testy i wydania](docs/ROZWOJ.md).
- [Dane, mechanizmy ochronne i odzyskiwanie](docs/BEZPIECZENSTWO-I-ODZYSKIWANIE.md).
- [Polecenia backendu](docs/CLI.md).
- [Przegląd kodu i wyniki](docs/AUDYT-KODU.md).
- [Testy aplikacji i lint](docs/TESTY-I-LINT.md).
- [Historia zmian](CHANGELOG.md) i [wykonana weryfikacja](VERIFICATION.md).

A local macOS utility for reconnecting existing Native Instruments libraries after a computer or system migration. It preserves authentic installation records on the library drive and checks evidence before restoring them.

The app reconnects libraries and can ask Native Access to update an existing installation. It does not manufacture version numbers, bypass activation, or mark missing applications and plug-ins as installed. Native Access remains responsible for ownership, activation, downloading and installing update content.

## Pobieranie i instalacja

Gotowy instalator DMG jest publikowany osobno jako wydanie testowe. Pobierz go
z sekcji [Releases](https://github.com/kawlas/native-fixtool/releases) repozytorium, otwórz DMG i przeciągnij Native FixTool do Applications.
Bieżący pakiet ma podpis lokalny (ad-hoc) i nie przeszedł notaryzacji Apple;
szczegóły pierwszego otwarcia i ograniczeń znajdziesz w [instrukcji](INSTRUKCJA.md).
Nie wyłączaj globalnie Gatekeepera.

## Current release

Version **0.3.5**, a pre-release build. The app is universal: Apple Silicon and Intel, macOS 14 or newer. The Native Access adapter currently supports **Native Access 3.26.0 / NTKDaemon 1.32 (R0), protocol 8.1.4**. Both application and daemon versions are checked.

Other Native Access versions fail closed before registration changes. Local inventory and offline manifest verification remain available. Supporting a future NI release requires testing its adapter; there is no promise that an undocumented vendor interface will work forever.

The included local build is ad-hoc signed. It has not been Developer ID signed or notarized. The release script prepares the same app for public distribution when the owner supplies their own Developer ID signing identity and an existing notary keychain profile. No signing credentials are included.

## Use — three tasks, one guided flow

The first screen presents **Repair / Updates / Migration** (Polish: **Naprawa / Aktualizacje / Przeniesienie**). Choose the problem you want to solve. Each screen explains the next action; selecting products is separate from confirming changes.

1. Open and sign into Native Access with the account holding your licences.
2. Choose a task, then select the parent folder containing your individual library folders. The folder picker can start at the content location read from your existing NI settings. No sample files are moved by folder selection.
3. The relevant list loads automatically. The UI explains every filter and the difference between choosing products, comparing files and applying changes.
4. Review the selected operation. Only the explicit **Start repair** or **Start updates** confirmation begins a write/install operation.

**Repair filters**, using names familiar from Native Access:

- **All / Wszystkie:** all folders in the selected collection. A filter changes only the displayed list.
- **Installed / Zainstalowane:** NI already recognises this exact installation. It does not need recovery.
- **Available / Dostępne:** content already exists on the drive and can be submitted for reconnection. This is not an invitation to download the whole product again.
- **Problems / Problemy:** cannot be repaired automatically; a plain-language reason is shown beside the library.

**Select for repair / Zaznacz do naprawy** only selects eligible rows in the visible list. **Review repair plan / Sprawdź plan naprawy** shows a summary; **Start repair / Rozpocznij naprawę** performs it. Selection is never treated as consent to write.

**Migration / Przeniesienie:** on the old Mac, save library information on the library drive. On the new Mac or after reinstalling macOS, connect that drive, sign into the same NI account, and choose Repair. A new macOS user is supported; the app does not transfer licences between NI accounts.

**How it works / Jak to działa?** explains filters, buttons, comparison, update limits and the difference between sample libraries on an SSD and user presets/settings in Documents. History and technical reports are available separately.

The app is available in Polish and English. macOS may ask for permission to access your selected removable volume. Use the folder picker to choose and grant access to the correct folder.

## What counts as evidence

- **Recognised by NI:** Native Access reports an installed, unbroken content product at this exact folder. This is an NI registration check, not an assertion that every sample has been hashed.
- **Ready to reconnect:** the existing `.nicnt` descriptor matches a unique product owned by the signed-in account, and recognised content exists beside it. The app submits the location to NI and reads the resulting state back.
- **Receipt to verify:** an authentic earlier NI registration is retained on this drive. For a library without `.nicnt`, every file in its saved installation must match its saved SHA-256 before the original record can be restored. The recorded version is preserved; the current server version is never substituted.
- **Registered elsewhere:** the product already has a valid working location. It is left alone.
- **Needs review:** missing or ambiguous identity, duplicate copies claiming one product, conflicting records, changed files, inaccessible paths, or another condition that cannot be resolved truthfully.

Saved local receipts are backups, not vendor-signed certificates. They should originate from a working installation you trust. Descriptor-only receipts are retained for reference and cannot be used to fabricate a fully verified installation.

## Updates: inspect, compare, then use NI

1. Choose **Updates** and select your library folder. The list loads automatically; **Refresh list** checks it again. The app reads installed/target versions from NI and the authenticated official content catalogue. It does not start a content download.
2. Select libraries (or use **Select all**) and choose **Check download size**. This fetches only official manifests and reads existing files on the drive. Whole-file SHA-256 and aligned vendor piece hashes show matching files, matching data and estimated missing/changed piece bytes. A large scan can take time; it is optional before starting an update. A zero estimate means current bytes match the target manifest, not that the installed-version record was changed.
3. Choose **Review update plan**, then **Start updates** and review the selected products. The app rechecks ownership, installed and target versions, exact target artifact, registered path, manifest root and NI Content location. Selected products with existing NI jobs are blocked to prevent duplicates. Other jobs are preserved; new updates join the existing NI queue. Authentic installation records are backed up; this is not a full backup of sample content.
4. Only `DEPLOYMENT_TYPE_UPDATE` is requested. NI queues and performs the actual verification, downloading, installation and version registration. No full/reinstall request, direct version edit or fabricated completion is used.
5. The session view polls NI and displays confirmation only when NI reports the installed target version. Pause/resume controls address only deployments created in that app session. Pausing during integrity checking can cause a repeat scan. Closing Native FixTool leaves accepted NI jobs under NI's control.

**Full content size is not transfer size.** The tested downloader uses aria2 `--check-integrity=true`; matching files/pieces can be retained. Estimated piece transfer excludes metadata, retries and protocol overhead and can differ from actual NI network use. A changed monolithic installer can still require a full download. The app cannot supply binary deltas absent from the vendor format or guarantee faster disk hashing. Successful-verification and HTTP GET counts refer only to the inspected portion of available NI logs, not measured total network bytes.

NI owns final integrity checks, so comparison followed by installation may read the same data twice. Skip comparison when you only want NI to run a correctly targeted update. A changed volume, unsupported NI version, unowned product or ambiguous target is blocked before starting an app-managed update. App/plugin installers remain in Native Access.

The library context menu retains advanced verification against a manually selected local official Metalink manifest. That separate offline audit does not establish the authenticity of an arbitrary XML file.

## Data and recovery

Library content is not deleted or replaced by **repair** or **comparison**. Starting a reviewed update hands installation to NI, which can replace library files. The app does not request NI passwords or persist login tokens. It has no telemetry. Update analysis obtains the existing NI session from the local daemon and uses it only in memory for authenticated HTTPS GET requests to the fixed NI download API. Credentials are passed to the system curl client through standard input, never command-line arguments or reports. Signed sample URLs are not saved or exported. NI handles the actual content downloads and activation.

Portable data is stored inside the selected library parent:

```text
.library-bridge/
  receipts/       Authentic records; full file hashes for descriptorless libraries
  backups/        Original records retained before repair or migration backup
  reports/        Repair and backup results
  operation.lock  Prevents concurrent mutations for this collection
```

Local reports and reviewed scan plans are stored in `~/Library/Application Support/Library Bridge/`. Reports contain product names and local paths, so inspect them before sharing.

A stale operation lock from another computer is not silently removed. Inspect its host/date and confirm that no operation is running before removing it. Cancellation finishes the current registration write safely and records partial results. Only a newly created receipt record that NI fails to recognise is rolled back automatically; existing records are never overwritten by receipt restoration.

Downloads are paused when necessary for repair. The exact download paused by the repair is resumed if it remains paused, including after a handled error. Already user-paused jobs are left alone. A failed resume is recorded so it can be resumed in NI. Redundant queued downloads are cancelled only for selected products whose exact recovered location and matching installed/target version have been confirmed by NI. Other downloads and genuine updates are preserved.

## Build and test

The project uses native AppKit and an included Node runtime, with no npm runtime dependencies or web frontend. Development-only lint tools are installed separately with `scripts/setup-lint.sh` and checked with `scripts/lint.sh`; they are not included in the app. NI modules are extracted from the user's own installed Native Access at runtime; proprietary NI application code is not redistributed in the app.

```sh
# First checkout / downloaded source archive:
chmod +x build.sh scripts/*.sh
./scripts/fetch-node.sh
./build.sh
vendor/node-arm64/bin/node --test tests/*.test.mjs
```

`fetch-node.sh` downloads pinned official Node 24.22.0 archives for both macOS architectures and verifies them against pinned SHA-256 checksums. Node's complete third-party license notices are included in the application resources.

Create a local disk image:

```sh
./scripts/package.sh
```

For a public release, use `scripts/sign-and-notarize.sh` with your own signing identity and notary profile. This uploads the supplied release to Apple's notary service; it is a separate release action, not part of ordinary builds.

## Verification performed

See [VERIFICATION.md](VERIFICATION.md) for executed checks and limits. A successful unit test is not a claim that a physical migration to a second Mac has been tested.

## References

[NI: reconnect an existing Komplete library collection](https://support.native-instruments.com/support/solutions/articles/69000879369-reinstalling-a-komplete-bundle-without-re-downloading-kontakt-libraries)

[NI: repair and relocate](https://support.native-instruments.com/support/solutions/articles/69000879243-using-the-repair-relocate-function-in-native-access)

[Apple: notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Native FixTool is independent software and is not affiliated with or endorsed by Native Instruments. Native Instruments and Native Access are their respective owner's trademarks.

[aria2: integrity checking and piece reuse](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-check-integrity)
