# Przejęcie rozwoju Native FixTool

Stan bazowy: **20.10.2026, aplikacja 0.3.5, build 8**. Dokument jest punktem
startowym dla osoby lub agenta bez historii rozmowy. Opisuje fakty historyczne;
stan konta, dysku, serwera, kolejki i zainstalowanego NI trzeba odczytać ponownie.

## Co rozwiązujemy

Po zmianie Maca lub macOS użytkownik zachowuje duży SSD z bibliotekami sampli,
ale nowa instalacja Native Access nie ma lokalnych informacji o ich instalacji.
Samo wskazanie Content location określa miejsce dla zawartości; nie zastępuje
rejestracji wszystkich znalezionych produktów. Konto określa dostępne licencje,
a lokalny demon NI przechowuje stan instalacji, lokalizacje i kolejkę.

Narzędzie łączy istniejący folder z właściwym licencjonowanym produktem przez
NI albo odtwarza autentyczny zapis po wymaganej weryfikacji. Nie skanuje każdego
WAV przy zwykłym wyświetlaniu stanu. Pełne haszowanie występuje przy porównaniu
manifestu i przy odtwarzaniu biblioteki bez deskryptora na podstawie receiptu.
Po naprawie wynik musi zostać potwierdzony przez NI w dokładnej lokalizacji.

Trzy zadania użytkownika:

| Zadanie | Oczekiwane zachowanie |
| --- | --- |
| Naprawa | Rozpoznać istniejące biblioteki bez ponownego pobierania posiadanych danych. |
| Aktualizacje | Zlecić właściwy UPDATE istniejącej instalacji; opcjonalnie porównać pliki, aby oszacować potrzebne dane. |
| Przeniesienie | Zachować autentyczne informacje na SSD; na nowym Macu zalogować się do uprawnionego konta i wykonać Naprawę. |

Nowe konto użytkownika macOS nie jest nowym kontem NI z przeniesionymi licencjami.
Biblioteka od innej osoby nie staje się zakupionym produktem przez skopiowanie
folderu lub zapisów. Licencje i aktywacja pozostają po stronie NI.

## Najpierw przeczytaj

1. [AGENTS.md](../AGENTS.md) — zasady pracy i niezmienniki.
2. [Architektura](ARCHITEKTURA.md) — moduły, przepływy i konkretne ścieżki.
3. [Bezpieczeństwo i odzyskiwanie](BEZPIECZENSTWO-I-ODZYSKIWANIE.md).
4. [Rozwój](ROZWOJ.md), [testy](TESTY-I-LINT.md) i [VERIFICATION](../VERIFICATION.md).
5. [Instrukcja użytkownika](../INSTRUKCJA.md) oraz [licencja](../LICENSE).

`README.md` jest opisem produktu, a nie pełnym kontraktem bezpieczeństwa.
Historyczne sekcje dokumentów zachowują poprzednie nazwy i starsze wyniki.
Nie traktuj zdania „nie opublikowano” w opisie dawnego testu jako aktualnego
statusu całego projektu.

## Technologia i miejsca wymagające ostrożności

| Obszar | Gdzie pracować i na co uważać |
| --- | --- |
| Natywne okno, PL/EN, stan GUI | `Sources/LibraryBridge.swift`; AppKit, nie Electron. Proces Node zwraca NDJSON. |
| Polecenia i operacje | `backend/cli.mjs`; plan, ponowna kontrola, blokada, kopie, przerwanie i raport. |
| Tożsamość i pliki | `backend/core.mjs`; kanoniczna ścieżka, device/inode, deskryptory, SHA-256 i ochrona ścieżek. |
| Autentyczne zapisy | `backend/vault.mjs`; oryginalne `installed_products`, receipts, kopie i ostrożny rollback. |
| Aktualizacje | `backend/updates.mjs`, `operations.mjs`; dokładny artefakt, manifest, fragmenty, świeży stan, UPDATE-only, potwierdzenie NI. |
| Sesja i katalog NI | `backend/cloud.mjs`; stały endpoint HTTPS, token w pamięci i stdin curl, bez eksportu podpisanych URL-i. |
| Adapter NI | `backend/native.mjs`, `native-bootstrap.mjs`; allowlista żądań, wersje, protobuf/ZMQ, lokalny runtime. |
| Pakowanie | `build.sh`, `scripts/package.sh`, `scripts/source-archive.py`; źródła do publicznego wydania są wybierane jawnie. |

Adapter pobiera potrzebne moduły i codec z **własnej zainstalowanej aplikacji
Native Access**, nie z naszego repo. Kontroluje wersję i rozpoznawany układ paczki.
Kod wydobyty z NI zostaje w lokalnym katalogu runtime; nie wolno dołączać go do
repozytorium ani dystrybucji. Nie usuwaj tej kontroli po aktualizacji NI.

Zgodność obecnego adaptera: **Native Access 3.26.0 / NTKDaemon 1.32 (R0),
protokół 8.1.4**. Dla nieobsługiwanej wersji operacje wymagające tego adaptera
mają zakończyć się odmową, bez zmian w rejestracji. Lokalna inwentaryzacja i
weryfikacja manifestu nie uprawniają do obchodzenia tej blokady.

Nie zmieniaj przy samym rebrandingu:

- bundle ID: `app.librarybridge.mac`; wykonywalny plik: `LibraryBridge`;
- `~/Library/Application Support/Library Bridge/` — runtime, raporty, plany, sesje;
- `<wybrany folder>/.library-bridge/` — `receipts`, `backups`, `reports`, `operation.lock`;
- identyfikatora licencji: `LicenseRef-NI-Fix-Tool-Private-Use-1.0`.

Zapisy NI są w `/Users/Shared/Native Instruments/installed_products/`, a część
preferencji w `/Library/Preferences/com.native-instruments.*.plist`.
`/Applications/Native Instruments` zawiera aplikacje, natomiast
`~/Documents/Native Instruments` presety i ustawienia. Obecność danych w
Documents sama w sobie nie oznacza błędnego przeniesienia bibliotek sampli.

## Reguły, których testy mają pilnować

- Własność produktu, jednoznaczna tożsamość, dokładny folder i wersja pochodzą
  z dowodów. Nie przypisujemy wersji serwera do starszych lokalnych plików.
- Descriptor `.nicnt` służy do identyfikacji i zgłoszenia lokalizacji do NI;
  nie jest dowodem pełnej zgodności wszystkich sampli.
- Receipt jest zaufaną lokalną kopią, nie certyfikatem NI. Bez deskryptora
  odtworzenie wymaga pełnego zapisanego inwentarza i zgodności wszystkich SHA-256.
- Ponowna kontrola musi nastąpić także bezpośrednio przed każdym zleceniem:
  inny klient może w międzyczasie zmienić kolejkę, folder, licencję lub wersję.
- Manifesty blokują traversal, symlinki, niejednoznaczny katalog, duplikaty
  i nieobsługiwane deklaracje XML/fragmenty. Nie osłabiaj walidacji dla wygody.
- Żądamy tylko `DEPLOYMENT_TYPE_UPDATE`. Nowa sesja zawiera tylko rzeczywiście
  przyjęte deployment IDs. Sukces wymaga odpowiedzi NI z docelową wersją.
- Blokada narzędzia nie jest transakcją z NI i nie zatrzymuje innych klientów.
  Przerwanie, wznowienie i rollback muszą zachować cudze i późniejsze zmiany.
- Aplikacja może wznawiać własne wstrzymane zadanie; nie może zbiorczo kasować
  kolejki. Obsługa częściowego niepowodzenia jest częścią poprawnego wyniku.

## Jak uruchomić i sprawdzić

W czystym checkoutcie, na Macu z macOS 14+ i Apple Command Line Tools:

```sh
chmod +x build.sh scripts/*.sh
./scripts/fetch-node.sh
./build.sh
./scripts/setup-lint.sh
./scripts/lint.sh
```

Runtime: przypięty Node **24.22.0**, arm64 i x64, sprawdzany względem przypiętych
sum. Pobieranie runtime korzysta z serwera Node; `setup-lint.sh` pobiera wyłącznie
narzędzia deweloperskie z npm z wyłączonymi skryptami instalacyjnymi. Działająca
aplikacja nie kontaktuje się z rejestrem npm i nie potrzebuje `node_modules`.

Testy bez instalowania czegokolwiek przez NI:

```sh
# Apple Silicon:
vendor/node-arm64/bin/node --test tests/*.test.mjs
# Intel, albo osobna kontrola x64 pod Rosettą:
vendor/node-x64/bin/node --test tests/*.test.mjs
```

Użyj odpowiedniej architektury; x64 na Apple Silicon wymaga Rosetty.
Testy korzystają z plików tymczasowych i atrap API. Nie potrzebują konta NI.
Polecenia odczytujące rzeczywisty NI to `discover`, `scan` i `updates`;
tworzą lokalny runtime/plany, ale nie zmieniają instalacji ani kolejki.
Pełna składnia i skutki wszystkich poleceń: [CLI.md](CLI.md).

UI ma tryb `--scan-result <plik.ndjson> --ui-smoke-output <raport.json>`
z wyłączonym zapisem. Sposób uruchomienia jest w [ROZWOJ.md](ROZWOJ.md).
Zapisane skany użytkownika nie są publicznymi fixture'ami. Bez nich trzeba
uzyskać własny odczyt lub przygotować jawnie syntetyczne dane zgodne z modelami
`LibraryRow`, `UpdateRow`, `ResultEvent`; nie używać ich w normalnej instalacji.
Po testach zamknij podgląd i pozostaw zwykłą aplikację bez flag QA.

## Co rzeczywiście sprawdzono

- 0.3.5 po poprawieniu nazwy: **36/36 backend**, **33/33 UI**, lint,
  uniwersalny build i poprawność podpisu ad hoc.
- **George Duke Soul Treasures 1.0.0 → 1.3.1**, rzeczywisty przepływ GUI:
  zachowane 472 pliki / 3 855 689 370 bajtów; pobrane 48 brakujących .nki /
  1 788 805 bajtów treści odpowiedzi HTTP 206. Potem 520/520 zgodnych plików
  w niezależnym pełnym audycie. Początkowe 48 błędów checksum oznaczało dokładnie
  brakujące pliki; nie wolno przepisać tego wyniku jako „0 ERROR”. Brak FATAL.
- **Scene – Lotus 1.1.1 → 1.1.2**: 387/387 plików zgodnych przed i po,
  0 GET w logu tego zadania; nie oznacza to zerowej komunikacji całego Maca.
- Po ostatniej operacji: 332/332 bibliotek rozpoznanych, brak aktywnych zadań,
  12 obsługiwanych aktualizacji bibliotek oraz Ozone wymagający instalatora NI.
  To wynik z tamtej chwili, nie bieżący stan po uruchomieniu przez kolejnego agenta.
- Przez rzeczywisty przycisk Przeniesienie odświeżono 332 autentyczne receipts,
  0 błędów. Nie wykonano migracji na fizycznie drugi komputer.

Dowody i dokładny zakres są w [VERIFICATION.md](../VERIFICATION.md) i
[TESTY-I-LINT.md](TESTY-I-LINT.md). Prywatne surowe raporty na komputerze autora
są w `.build/`; ich brak po `git clone` jest zamierzony.

## Czego nadal nie zrobiono

1. Fizycznej migracji na drugi Mac, osobnego fizycznego Intela i urządzenia
   z macOS 14. Testy x64 pod Rosettą nie zastępują tych sprawdzeń.
2. Pełnego VoiceOver, ręcznej nawigacji całego UI klawiaturą i systemowego
   powiększenia 200%. Same role AX i fokus nie stanowią certyfikacji dostępności.
3. Obsługi innych wersji Native Access/NTKDaemon. Wymaga nowego przeglądu
   adaptera i testów, nie samej zmiany numeru w warunku.
4. Podpisu Developer ID i notaryzacji Apple. Nie ma dostarczonych danych Apple;
   lokalne `codesign --verify` potwierdza spójność podpisu, nie zaufanie Gatekeepera.
5. Uniwersalnych delt binarnych: aplikacja nie tworzy ich z instalatorów NI.
   Zmieniony monolityczny pakiet nadal może wymagać pełnego pobrania.
6. Gwarancji zgodności prywatnego API w przyszłości lub kompletnego audytu
   bezpieczeństwa przez niezależny zespół. Wynik skanu wzorców kluczy to tylko
   jedno ze sprawdzeń, nie dowód braku wszystkich możliwych sekretów.

Najpierw odtwarzaj build i testy na danym hoście. Dalsze prace dobieraj do nowego
zlecenia, nie uruchamiaj kolejnych prawdziwych aktualizacji jako zadania w tle.

## Repozytorium, wydania i bezpieczne przekazanie

- Repo publiczne: <https://github.com/kawlas/native-fixtool>.
- Wydanie testowe: <https://github.com/kawlas/native-fixtool/releases/tag/v0.3.5>.
- Opublikowano DMG universal, jego `.sha256` i ZIP źródeł. Wszystkie trzy sumy
  zgadzały się z digestami GitHub po publikacji. Wtedy sprawdzono 46/46 plików
  na `main` względem projektu; ta liczba rośnie wraz z dokumentacją.
- W czasie publikacji sprawdzono 15/15 przypadków `.gitignore` oraz wzorce
  kluczy/tokenów w wybranych źródłach. Nie opublikowano plików `.env`, danych
  konta, lokalnego runtime NI ani prywatnych raportów. Ignorowanie nie usuwa
  sekretu z wcześniejszego commitu: w takim przypadku potrzebna jest osobna
  reakcja na ujawnienie, a nie samo dopisanie reguły.
- `v0.3.5` i jego assety opisują historyczne wydanie. Późniejsze poprawki
  formatowania konfiguracji i przewodnik na `main` mogą być nowsze niż tag.
  Nie podmieniaj cicho istniejących assetów ani nie przesuwaj wydanego taga.
- Nowe wydanie: zwiększ wersję i build w `Info.plist`, zsynchronizuj
  `package.json`/lock i dokumentację, wykonaj adekwatne kontrole, zbuduj i sprawdź
  DMG/archiwum. Do notaryzacji służy osobny `sign-and-notarize.sh` wymagający
  własnych danych Apple. Bez niej oznacz wydanie jako testowe/ad hoc.
- `source-archive.py` wybiera pliki; nowe pliki głównego katalogu trzeba
  dopisać do jego listy. Dokumenty `docs/*.md` są dołączane automatycznie.
  Po zmianie sprawdź faktyczną listę ZIP-a, nie tylko `.gitignore`.
- Uwierzytelnienia nie przenoszą się z agentem. Sprawdź aktualne konto i prawo
  zapisu do `kawlas/native-fixtool`. Nie publikuj na przypadkowo podłączonym
  koncie innej osoby. Wcześniejszy zapis odbywał się przez zalogowaną przeglądarkę,
  bo użyty konektor odmawiał zapisu; nie oznacza to, że nowa sesja ma te same prawa.

Po swojej pracy dopisz tutaj zmianę stanu i ograniczeń; wyniki sprawdzeń zapisz
w `VERIFICATION.md`. Konkretną wiedzę potrzebną następnej osobie utrzymuj w repo,
a prywatne ścieżki, surowe logi i dowody tylko lokalnie. Ten dokument zmniejsza
zależność od rozmowy, ale nie daje gwarancji, że każdy agent go przeczyta lub
prawidłowo wykona wszystkie instrukcje.
