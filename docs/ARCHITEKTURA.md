# Architektura i mapa projektu

## Warstwy

```text
AppKit / Sources/LibraryBridge.swift
    │ Process, argumenty jako tablica, stdout NDJSON
    ▼
dołączony Node → backend/cli.mjs
    ├── core.mjs        rozpoznawanie folderów, plany, blokady, SHA-256
    ├── vault.mjs       kopie i autentyczne dane instalacji
    ├── updates.mjs     wersje, manifesty, porównanie, potwierdzenie
    ├── operations.mjs  ponowna kontrola przed aktualizacją, wznowienie po naprawie
    ├── cloud.mjs       metadane z oficjalnego API NI
    └── native.mjs → native-bootstrap.mjs → lokalny NTKDaemon
```

Interfejs jest natywny; nie ma serwera WWW, npm ani frameworka frontendowego. GUI i proces Node są rozdzielone. GUI dekoduje kolejne linie JSON typu `progress`, `result` i `error`. Jedna instancja GUI wykonuje jedną operację backendu naraz. Główna kolejka AppKit obsługuje interfejs, osobne zadanie odczytuje stdout procesu.

## Pliki źródłowe

| Plik | Odpowiedzialność |
| --- | --- |
| `Sources/LibraryBridge.swift` | Modele wyników, stan pracy, uruchamianie backendu, okno, tabele, wybór folderu, podsumowania, PL/EN, lokalne sprawdzenia UI. |
| `backend/cli.mjs` | Polecenia, preflight, obsługa przerwania, raporty, spięcie naprawy i aktualizacji. |
| `backend/core.mjs` | Kanoniczny katalog, tożsamość dysku/folderu, rozpoznanie produktów, plany, blokada, parsowanie Metalink, haszowanie. |
| `backend/vault.mjs` | Odczyt oryginalnych wpisów NI, kopie, zapis danych na dysku i ostrożne odtworzenie wpisu. |
| `backend/updates.mjs` | Wybór dokładnego artefaktu wersji, ścieżki manifestu, porównanie całych plików i fragmentów, UPDATE-only, wynik NI. |
| `backend/operations.mjs` | Ponowne sprawdzenie zmiennego stanu NI tuż przed każdym zleceniem i wznowienie zadania wstrzymanego przez naprawę. |
| `backend/cloud.mjs` | HTTPS GET do stałego API NI; token tylko w pamięci, nagłówek przez stdin curl. |
| `backend/native.mjs` | Lista dozwolonych żądań, tryb odczytu/zapisu, kontrola NTKDaemon, protobuf/ZMQ. |
| `backend/native-bootstrap.mjs` | Kontrola wersji aplikacji NI i lokalne przygotowanie adaptera z plików zainstalowanego NI. |
| `tests/*.test.mjs` | Testy w katalogach tymczasowych i z atrapą API, bez prawdziwych instalacji. |
| `Info.plist` | Nazwa, wersja, identyfikator pakietu, minimalny macOS, opis dostępu do dysku. |
| `build.sh` | Kompilacja dwóch architektur, dołączenie Node i lokalne podpisanie. |
| `scripts/fetch-node.sh` | Pobranie przypiętych archiwów Node i weryfikacja SHA-256. |
| `scripts/package.sh` | Obraz DMG i suma SHA-256. |
| `scripts/source-archive.py` | Archiwum wyłącznie kodu i dokumentacji do udostępnienia. |
| `scripts/sign-and-notarize.sh` | Osobny proces podpisu Developer ID i notaryzacji przez właściciela. |

## Przepływ naprawy

1. Odczyt produktów i licencji z NTKDaemon. Foldery są porównywane z dokładną zarejestrowaną ścieżką.
2. Rozpoznana instalacja jest tylko wyświetlana. Przy brakującej rejestracji identyfikacja opiera się na UPID w `.nicnt`, ewentualnie nazwie i licencjonowanym SNPID.
3. Brak własności, konflikt kopii, inna działająca lokalizacja lub niejednoznaczność blokują automatyczną naprawę.
4. Plan zapisuje stan i tożsamość katalogu. Po zatwierdzeniu następuje ponowny odczyt, blokada operacji i kopia oryginalnych wpisów.
5. Typowa biblioteka trafia do oficjalnego żądania `locateLibraryRequest`. Biblioteka bez deskryptora wymaga autentycznego pełnego zapisu i zgodności SHA-256 każdego zapisanego pliku.
6. Odświeżenie produktów i potwierdzenie dokładnej lokalizacji przez NI. Nowy wpis z kopii jest usuwany, jeśli NI nie potwierdzi również zapisanej wersji.
7. Ewentualne usunięcie zbędnego pobierania dotyczy wyłącznie wybranych, potwierdzonych, aktualnych produktów. Zadanie wstrzymane przez naprawę jest wznawiane, jeśli nadal czeka w stanie paused.

## Przepływ aktualizacji

Katalog pochodzi z uwierzytelnionego API NI. Wybór wymaga jednego artefaktu content/path/all pasującego do wersji docelowej. Zbieżny numer wersji przy wielu artefaktach nie wystarcza.

Manifest musi zawierać jeden katalog główny zgodny z nazwą zarejestrowanego folderu. Odrzucamy wyjście przez `..`, powtórzone ścieżki, niedozwolone deklaracje XML i nieobsługiwane fragmenty. Audyt sprawdza całe pliki SHA-256 i udostępnione przez NI fragmenty SHA-1/SHA-256 podczas jednego odczytu. Kontroluje zmianę pliku podczas odczytu.

Przed pierwszym zleceniem sprawdzane są manifesty wszystkich wybranych produktów i zapisywana jest kopia wpisów. Bezpośrednio przed każdym zleceniem ponownie odczytywane są preferencje, produkty i kolejka, a następnie porównywane z zatwierdzonym planem. Wysyłany jest wyłącznie `DEPLOYMENT_TYPE_UPDATE`. Instalację i pobieranie wykonuje NI.

NI nie udostępnia transakcji obejmującej sprawdzenie i zlecenie z innej aplikacji. Ostatnia ponowna kontrola ogranicza ryzyko równoczesnej operacji, ale nie daje matematycznej gwarancji wykluczenia innego klienta. Nie uruchamiaj tego samego produktu jednocześnie w obu aplikacjach.

## Lokalizacje danych

| Miejsce | Co zawiera |
| --- | --- |
| Wybrany folder, np. `/Volumes/MUZA/NI` | Istniejące biblioteki. |
| `<folder>/.library-bridge/receipts/` | Oryginalne wpisy; dla bibliotek bez deskryptora także lista i hasze plików. |
| `<folder>/.library-bridge/backups/` | Kopie wpisów sprzed operacji. |
| `<folder>/.library-bridge/reports/` | Raporty naprawy i zapisu do przeniesienia. |
| `<folder>/.library-bridge/operation.lock` | Host i PID operacji zmieniającej dane. |
| `~/Library/Application Support/Library Bridge/` | Plany, raporty, sesje aktualizacji, lokalny adapter runtime. |
| `/Users/Shared/Native Instruments/installed_products/` | Oryginalne wpisy produktów NI, np. `ContentDir`, `ContentVersion`. |
| `/Library/Preferences/com.native-instruments.*.plist` | Systemowe preferencje produktów NI; aplikacja nie udaje ich wersji. |
| `/Applications/Native Instruments` | Aplikacje NI, odrębne od sampli. |
| `~/Documents/Native Instruments` | Presety i ustawienia użytkownika, odrębne od sampli. |

Identyfikator `app.librarybridge.mac`, nazwa katalogu wsparcia i `.library-bridge` pozostają dla zgodności ze starszymi wersjami. Nazwa widoczna dla użytkownika to Native FixTool.

## Zgodność

macOS minimum 14, uniwersalny plik wykonywalny arm64/x86_64 i dwa przypięte Node 24.22.0. Adapter wymaga Native Access 3.26.0 oraz odpowiedzi NTKDaemon `{major: 1, minor: 32, build: " (R0)"}`. Protokół żądań: 8.1.4. NI nie publikuje gwarancji stałości tego interfejsu. Zmiana wersji wymaga ponownej analizy i testów.

## Warstwa wizualna 0.3.4

Natywne AppKit zachowuje logikę zadań i modalne zatwierdzanie. `AccessStyle`
ustala wspólne kolory i krój Roboto. `AccessButtonCell` rysuje płaskie przyciski,
a `AccessTabsCell` zakładki tekstowe, zachowując natywne kontrolki i ich role
dostępności. Roboto jest rejestrowane tylko w procesie aplikacji z `Resources/Fonts`;
nie instalujemy czcionek w systemie. Jego odrębna licencja SIL OFL jest dołączona
w `Fonts/OFL.txt`. Paleta odpowiada jasnemu interfejsowi Native Access 3.26.0;
okno aplikacji ma jawny jasny wygląd również przy ciemnym motywie macOS.
