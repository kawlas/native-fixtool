# Budowanie, testy i wydawanie

Przy przejmowaniu projektu zacznij od [AGENTS.md](../AGENTS.md) i
[przewodnika przejęcia](PRZEJECIE-PROJEKTU.md). Zawierają aktualny status publikacji,
niezmienniki silnika, ograniczenia i zakres testów, których jeszcze nie wykonano.

Kod i bieżące wydanie 0.3.5 podlegają [Native FixTool Private Use License 1.0](../LICENSE). Kompilacja nie zmienia warunków: dozwolony jest tylko użytek prywatny, bez użycia firmowego, organizacyjnego, zawodowego lub komercyjnego. Poniższe instrukcje techniczne nie udzielają dodatkowych praw do użycia.

## Wymagania

Mac z macOS 14+, narzędzia Apple Command Line Tools (`xcrun`, `swiftc`, `lipo`, `codesign`), zsh, Python 3 i curl. Do uruchomienia funkcji NI potrzebna jest własna instalacja Native Access w `/Applications/Native Access.app`, działający NTKDaemon i konto z licencjami.

W projekcie na pulpicie zachowano pobrane runtimy, archiwa, poprzednie wydania i lokalne dowody testów. Źródła i dokumentacja do udostępnienia są mniejsze i niezależne od tych materiałów.

## Kompilacja

W Terminalu przejdź do folderu projektu. Wszystkie ścieżki ze spacjami muszą być w cudzysłowach:

```sh
cd "$HOME/Desktop/Native FixTool — projekt"
chmod +x build.sh scripts/*.sh
./build.sh
```

Skrypty wyznaczają katalog projektu ze swojego położenia. Nie wymagają starej lokalizacji `Projects/LibraryBridge`.

Przy czystym archiwum źródeł najpierw pobierz dwa Node:

```sh
./scripts/fetch-node.sh
```

Wersja Node i sumy są przypięte; pobranie jest weryfikowane przed rozpakowaniem. Skrypt nie zastępuje automatycznie istniejącego `vendor/node-*`. Jeśli chcesz zmienić runtime, przenieś wcześniejszy katalog świadomie, zaktualizuj sumy i powtórz testy. Aplikacja nie potrzebuje zależności npm. Narzędzia deweloperskie do lintowania instaluje osobno `./scripts/setup-lint.sh`; sprawdzenie wykonuje `./scripts/lint.sh`. Szczegóły i wyniki są w [TESTY-I-LINT.md](TESTY-I-LINT.md).

Kompilacja buduje świeży pakiet w katalogu tymczasowym `.build`, aby stare moduły nie pozostawały w nowym wydaniu. Dopiero po podpisaniu i weryfikacji zastępuje własny pakiet w `dist`. Nie zmienia aplikacji w `/Applications` ani danych bibliotek.

## Sprawdzenia kodu

```sh
vendor/node-arm64/bin/node --test tests/*.test.mjs
zsh -n build.sh scripts/*.sh
for f in backend/*.mjs; do vendor/node-arm64/bin/node --check "$f"; done
codesign --verify --deep --strict "dist/Native FixTool.app"
lipo -info "dist/Native FixTool.app/Contents/MacOS/LibraryBridge"
```

Na fizycznym Macu Intel użyj `vendor/node-x64/bin/node`. Rosetta może sprawdzić wykonanie x64 na Apple Silicon, ale nie zastępuje fizycznego Maca Intel.

Testy backendu używają katalogów tymczasowych i atrap API. Nie instalują produktów, nie piszą do systemowych wpisów NI i nie rozpoczynają pobierania sampli.

## Sprawdzenie działającego adaptera bez instalowania

```sh
vendor/node-arm64/bin/node backend/cli.mjs discover
vendor/node-arm64/bin/node backend/cli.mjs scan --library /Volumes/MUZA/NI
vendor/node-arm64/bin/node backend/cli.mjs updates --library /Volumes/MUZA/NI
```

Odczyty tworzą lokalne plany/raporty i lokalny runtime, ale nie zmieniają rejestracji, preferencji ani kolejki NI. Nie wykonuj w testach poleceń zapisujących na prawdziwej bibliotece bez osobnego celu i sprawdzonego planu.

## Sprawdzenia UI

Można użyć wcześniej zachowanego wyniku NDJSON zawierającego rzeczywiste dane `rows` i `updates`:

```sh
open "dist/Native FixTool.app" --args \
  --scan-result "/pełna/ścieżka/do/wyniku.ndjson" \
  --ui-smoke-output "/pełna/ścieżka/do/ui-report.json"
```

Tryb jest jawnie oznaczony jako podgląd. Zapisy i pobieranie są wyłączone. Przypadki puste, błędu dostępu oraz przykładowe pozycje problemowe są symulowane i opisane w raporcie. `--compact` ustawia mniejsze okno. `--capture` i `--capture-scenarios` zapisują obraz własnego okna do lokalnej ścieżki; część automatycznych zrzutów może pomijać warstwy kompozytora.

Po teście zamknij jego okno i otwórz zainstalowaną aplikację bez flag podglądu. Nie pozostawiaj użytkownikowi okna z wyłączonymi działaniami. Nie traktuj tych testów jako certyfikacji VoiceOver, pełnej obsługi klawiatury lub potwierdzenia migracji na drugi komputer.

## Wydanie lokalne

```sh
./scripts/package.sh
python3 scripts/source-archive.py
```

W `dist` powstają aplikacja, wersjonowany DMG, SHA-256 oraz wersjonowany ZIP źródeł. Numer wydania pochodzi z `Info.plist`; stopka GUI odczytuje tę samą wartość.

Przed wydaniem zaktualizuj `CFBundleShortVersionString`, rosnący `CFBundleVersion`, instrukcję, README, dziennik zmian i weryfikację. Przejrzyj zawartość źródeł ZIP. Nie udostępniaj całego roboczego `.build` ani prywatnych wyników skanowania.

## Podpis publiczny — osobny etap

```sh
./scripts/sign-and-notarize.sh \
  "Developer ID Application: Your Name (TEAMID)" \
  "istniejacy-profil-notary-keychain"
```

Wymaga Twoich danych Apple w pęku kluczy. Podpisuje Node i aplikację, tworzy i podpisuje DMG, wysyła DMG do notaryzacji, dodaje ticket i przelicza SHA-256. Nie dołączaj certyfikatów, kluczy ani haseł do repozytorium. W tej sesji ten etap nie był uruchamiany.

## Obsługa nowej wersji Native Access

Nie usuwaj kontroli wersji tylko po to, żeby aplikacja ruszyła. Zweryfikuj format paczki, codec, protokół i semantykę wszystkich żądań na własnej instalacji. Najpierw odczyty, potem kontrolowane operacje na osobnych danych. Dodaj testy zgodności i rollbacku; dopiero wtedy rozszerz adapter. Prywatne API NI może się zmienić.
