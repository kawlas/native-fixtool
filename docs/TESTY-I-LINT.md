# Test aplikacji, prawdziwa aktualizacja i lint — 20.10.2026

## Test przez rzeczywiste okno — George Duke Soul Treasures

20.10.2026 wykonano pełny przebieg przez macOS Accessibility: wybór `/Volumes/MUZA/NI`
w systemowym oknie folderu, Aktualizacje, zaznaczenie wyłącznie George Duke,
porównanie SSD, podsumowanie z jednym produktem i przycisk Rozpocznij aktualizacje.
To były rzeczywiste kontrolki działającej aplikacji, bez flag podglądu i bez
wywołania `update-start` w CLI. Start nastąpił w 0.3.3; po zamknięciu GUI i
instalacji 0.3.4 ta sama zapisana sesja została odnaleziona, a NI potwierdziło koniec.
Nie uruchomiono drugiego zlecenia.

| Kontrola | Wynik |
| --- | --- |
| Wersja | 1.0.0 → 1.3.1 |
| Folder | `/Volumes/MUZA/NI/George Duke Soul Treasures Library`, bez zmiany |
| Przed startem | 472 zgodne pliki; 48 rzeczywiście brakujących plików .nki |
| Zachowane dane | 3 855 689 370 bajtów zgodnych plików |
| Potrzebne dane | 1 788 805 bajtów, szacunek po pełnym porównaniu |
| Log pobierania | 48 GET, 48 odpowiedzi HTTP 206, suma Content-Length 1 788 805 bajtów |
| Zakończenie | 520 wpisów Download complete; NI potwierdziło 1.3.1 i oryginalny folder |
| Pozostałe aktualizacje | 12 bibliotek obsługiwanych przez narzędzie oraz Ozone wymagający instalatora NI |
| Kolekcja po aktualizacji | 332/332 rozpoznane, 0 do naprawy i 0 problemowych |

Suma Content-Length opisuje treść odpowiedzi tego zadania, nie cały ruch sieciowy
Maca. NI najpierw czytało i sprawdzało istniejące pliki; cały etap NI zajął około
6 minut, a pobranie brakujących instrumentów nastąpiło na końcu. Mały transfer
nie oznacza pominięcia weryfikacji dysku. Log zawiera 48 początkowych wpisów
Checksum error detected: każdy odpowiada dokładnie jednemu plikowi, którego
brak stwierdzono przed startem. To wykryte braki do pobrania, nie 48 błędów
końcowego wdrożenia. Brak wpisów FATAL. Po zakończeniu ponownie policzono SHA-256 wszystkich 520 plików i porównano
je z tym samym oficjalnym artefaktem NI: 520/520 zgodnych, 0 bajtów do uzupełnienia.

Przycisk Przeniesienie → Zapisz dane bibliotek na dysku uruchomiono w rzeczywistym GUI 0.3.4: 332 zapisane lub potwierdzone wpisy, 0 błędów. Autentyczny zapis George Duke na SSD zawiera teraz ContentVersion 1.3.1.

Dowody prywatne: `.build/qa-computer-use/`; nie są dołączane do wydania.

## Wcześniejszy test — Scene – Lotus

Za zgodą użytkownika wykonano jeden oficjalny UPDATE przez silnik zainstalowanej aplikacji **0.3.2**. Nie edytowano wersji ani rejestracji ręcznie. Interfejs sprawdzono osobno w bezpiecznych symulacjach; nie automatyzowano kliknięcia Start w działającym GUI.

| Kontrola | Wynik |
| --- | --- |
| Produkt i wersje | Scene – Lotus, 1.1.1 → 1.1.2 |
| Folder | `/Volumes/MUZA/NI/Scene - Lotus Library` — bez zmiany |
| Porównanie przed startem | 387/387 zgodnych plików, 1 292 603 943 bajty; szacunek transferu fragmentów 0 bajtów |
| Zlecenie | Oficjalne `DEPLOYMENT_TYPE_UPDATE` przyjęte przez NI |
| Wynik NI | Wersja 1.1.2 potwierdzona w dokładnym folderze, brak aktywnego zadania |
| Log zadania | 387 zakończonych weryfikacji, 0 żądań GET, 0 linii ERROR/FATAL |
| Ponowne haszowanie po aktualizacji | 387/387 zgodnych z oficjalnym manifestem; ten sam artefakt i lista plików/rozmiarów |
| Dane do przeniesienia | Odświeżony autentyczny receipt Scene – Lotus na SSD |
| Stary plan po ukończeniu | Odrzucony: stan wersji się zmienił |
| Cała kolekcja po operacji | 332/332 rozpoznane, 0 do naprawy i 0 problemowych |
| Aktualizacje pozostałe | 13, wcześniej 14; nie uruchamiano pozostałych |

Zero żądań GET dotyczy sprawdzonego logu tego zadania, nie pomiaru całego ruchu sieciowego komputera. Zapytania o metadane i aktywację nadal mogą generować ruch. Rzeczywisty test obejmuje sytuację, w której docelowe dane były już obecne. Na tym wcześniejszym etapie niezerowy transfer sprawdzono jedynie w symulacjach; opisany wyżej test George Duke uzupełnia ten zakres rzeczywistym wdrożeniem.

Pierwsza dodatkowa asercja błędnie wymagała identycznego surowego XML. Manifest zawiera odświeżane podpisane linki. Test poprawiono: sprawdza artefakt, listę plików/rozmiarów i ponownie SHA-256 wszystkich plików względem aktualnych danych NI. Podpisane URL-e nie trafiają do dokumentacji.

## Symulacje i poprawki

**36 testów backendu** przeszło na arm64 i ponownie przez x64 pod Rosettą. Zakres: własność, brakujące i zmienione pliki, zgodne fragmenty, granica odczytu 4 MiB, ucięte pliki, symlinki, ścieżki, tożsamość dysku, konflikty produktów, stare plany, duplikaty, zmiana preferencji i własności, przerwanie, odmowa demona, UPDATE-only, dokładna lokalizacja i autentyczne odtwarzanie.

Nowe testy wykryły i potwierdzają poprawki: EPERM podczas sprawdzania PID nie oznacza martwego procesu; nieprawidłowy PID nie może prowadzić do sygnalizowania grupy procesów; błąd rollbacku jest raportowany, a pozostałe wpisy nadal są obsługiwane. Wpis zmieniony później przez NI jest zachowywany.

Rozszerzone sprawdzenia AppKit korzystają z zapisanej rzeczywistej kolekcji. Pozycje przykładowe i stany błędów są jawnie symulowane z wyłączonym zapisem. Obejmują filtry, wyszukiwanie, wybór, podsumowania, PL/EN, kontrolki dostępności, pusty folder/listę, trwające porównanie, brak dostępu, anulowanie, częściowe niepowodzenie, zero uruchomionych zadań i potwierdzone zakończenie sesji. Wynik jest zapisany w `VERIFICATION.md` i lokalnym raporcie UI.

Dwie początkowe asercje oczekiwały komunikatu operacji w miejscu stałego baneru podglądu. Skorygowano oczekiwania testu: sprawdza stan anulowania i zachowanie baneru odczytu. Nie wyłączano ochrony przed zapisem.

## Powtarzalny lint

```sh
# Jednorazowo pobiera narzędzia deweloperskie z rejestru npm:
./scripts/setup-lint.sh

# Bez sieci i bez działań NI:
./scripts/lint.sh

# Testy na plikach tymczasowych i atrapach API:
vendor/node-arm64/bin/node --test tests/*.test.mjs
```

Lint obejmuje ESLint z zalecanymi regułami i limitem 0 ostrzeżeń, Prettier, `swift-format lint --strict`, składnię zsh i parsowanie AST Pythona. Python/zsh mają tu kontrolę składni, nie osobne lintery Ruff/ShellCheck. Pierwszy ESLint wskazał 10 uwag; poprawiono je, uporządkowano formatowanie Swift/JavaScript i zastąpiono dwa `forEach` pętlami. Końcowy lint przechodzi bez uwag.

Wersje narzędzi npm są przypięte w `package.json` i `package-lock.json`. Instalacja ma wyłączone skrypty instalacyjne i audyt sieciowy. Nie wysyła kodu projektu, bibliotek ani danych NI do rejestru. `node_modules` nie jest dołączane do aplikacji ani ZIP-a źródeł. Działająca aplikacja nadal nie wymaga npm.

## Dowody i ograniczenia

Dowody lokalne: `.build/qa-live-2026-10-20/` — wyniki przed/po, sesja NI wskazana ścieżką, podsumowanie logu, SHA-256 po aktualizacji, odmowa starego planu, testy arm64/x64, UI i lint. Są wyłączone z udostępnianego ZIP-a.

Rosetta nie zastępuje fizycznego Intela. Nie sprawdzono fizycznej migracji na drugi Mac, innej wersji NI, pełnego VoiceOver ani całej ręcznej nawigacji klawiaturą. Wydanie po poprawkach lintowania ma numer **0.3.3**; test rzeczywistego zlecenia dotyczy opisanego wyżej 0.3.2. Nowe zabezpieczenia blokady i raportowania rollbacku sprawdzono w testach symulowanych.
