# Przegląd kodu — 20 października 2026

Aktualizacja 0.3.3: kod został sformatowany; dawna uwaga o zwartej formie ma charakter historyczny. Dodatkowe testy, lint i rzeczywista aktualizacja: [TESTY-I-LINT.md](TESTY-I-LINT.md).

Zakres: kod AppKit, wszystkie moduły backendu, testy, skrypty budowania i wydawania, plany, raporty, przenośne wpisy, połączenie NI i sposób przekazywania tokenu. Przegląd lokalny, bez publikowania kodu lub danych w zewnętrznej usłudze.

## Wykryte i poprawione

| Problem | Znaczenie | Zmiana w 0.3.1 | Sprawdzenie |
| --- | --- | --- | --- |
| Naprawa wstrzymywała aktywne pobieranie NI bez późniejszego wznowienia. | Inne zadanie mogło pozostawać wstrzymane po naprawie. | Zapamiętanie własnego pause i wznowienie tylko tego samego zadania, jeśli nadal jest paused. Obsługa zwykłego zakończenia i błędu. | Test właściwego zadania oraz zadań znikniętych, instalowanych i wcześniej wstrzymanych przez użytkownika; przegląd ścieżek wyjścia CLI. |
| Sprawdzenie duplikatów poprzedzało oczekiwanie na manifesty i kopię. | Stan kolejki mógł się zmienić przed zleceniem. | Powtórny odczyt kolejki, preferencji i produktów tuż przed każdą aktualizacją. | Test zadania dodanego po utworzeniu planu, zmiany własności, ścieżki i preferencji. |
| Przerwanie podczas ostatniej kontroli nie było sprawdzane przed samym UPDATE. | Zlecenie mogło zostać przekazane mimo prośby o przerwanie. | Dodatkowa kontrola anulowania przed żądaniem zapisu. | Test anulowania podczas ponownej kontroli, bez żądania start. |
| Sesja z zerem przyjętych aktualizacji była zwracana jako aktywna. | GUI mogło pokazać kontrolki nieistniejącej pracy. | Pusta sesja pozostaje tylko plikiem diagnostycznym, nie aktywną sesją GUI. | Przegląd kodu warunku odpowiedzi; brak testu pełnej awarii prawdziwego NI. |
| Kontrola wersji obejmowała aplikację NI, ale nie odpowiedź NTKDaemon. | Samodzielna aktualizacja demona mogła przejść niezauważona. | Wymaganie sprawdzonej odpowiedzi 1.32 (R0). | Test odmowy dla niepełnych/innych wersji i rzeczywisty odczyt obsługiwanego NI. |
| Budowanie nakładało pliki na wcześniejszy pakiet. | Usunięty moduł mógł pozostać w następnym wydaniu. | Świeży katalog budowania, podpis i weryfikacja przed zastąpieniem własnego wyniku. | Kompilacja z nowego folderu na pulpicie i weryfikacja podpisu. |
| Numer wersji był powielany w GUI i skryptach. | Instalator i aplikacja mogły pokazywać różne wydania. | GUI, pakowanie i notaryzacja odczytują numer z Info.plist. | Kontrola gotowego pakietu i nazw wydania. |

## Wykonane sprawdzenia

- **30/30 testów backendu** na arm64 oraz ponownie przez runtime x64 pod Rosettą: oryginalne 23 i siedem nowych testów ponownej kontroli, kolejki, wznowienia i wersji demona. Rosetta nie zastępuje fizycznego Intela.
- Kontrola składni wszystkich modułów `.mjs` i skryptów `.sh`.
- Świeża uniwersalna kompilacja arm64/x86_64 z folderu projektu na pulpicie.
- Weryfikacja podpisu ad hoc gotowego pakietu.
- Rzeczywisty odczyt przez spakowany backend 0.3.1: **332/332 bibliotek rozpoznanych**, **0 do naprawy**, **0 problemowych**, **14 aktualizacji**. Odczyt Content location wskazał `/Volumes/MUZA/NI`.
- **25/25 sprawdzeń GUI** przeszło w nowym pakiecie 0.3.1. Tryb podglądu wykorzystuje zapisane rzeczywiste dane oraz oznaczone symulacje. Wynik jest zapisany w `VERIFICATION.md` i lokalnym `.build/audit-031-ui.json`. Pierwszy odczyt pliku na pulpicie zatrzymało pytanie macOS o dostęp; test powtórzono z kopią danych w katalogu tymczasowym, bez obchodzenia uprawnień.
- Przejrzano źródła pod kątem starej ścieżki projektu i typowych postaci prywatnych kluczy/tokenów; nie znaleziono takich wpisów. To nie jest pełny skaner sekretów ani dowód braku wszystkich możliwych danych prywatnych.

W tym przeglądzie nie wykonywano prawdziwych napraw, pause/resume kolejki ani instalowania aktualizacji na bibliotekach użytkownika. Nowe przypadki zapisujące sprawdzono z atrapą NI i plikami tymczasowymi. Rzeczywisty wcześniejszy test aktualizacji Soul Sessions jest udokumentowany osobno w `VERIFICATION.md`.

## Pozostające ograniczenia

1. NI nie udostępnia atomowej transakcji „sprawdź i zleć”. Inny klient może zmienić stan po ostatnim odczycie. Nie uruchamiaj tego samego produktu równolegle w obu aplikacjach.
2. Adapter używa prywatnego interfejsu NI i jest celowo ograniczony do sprawdzonej wersji. Przyszłe wersje mogą wymagać zmian.
3. Lokalne receipts nie są podpisane przez NI. Zaufanie do kopii i własność konta nadal są wymagane.
4. Błąd sieci lub timeout po stronie żądania zapisu może być niejednoznaczny: NI mogło przyjąć zadanie, mimo braku odpowiedzi klientowi. Przed ponowieniem sprawdź kolejkę NI. Zlecenie i zapis pliku sesji nie stanowią jednej transakcji; nagła awaria może zostawić zadanie NI bez lokalnego śledzenia.
5. Po usunięciu lub awarii zadania sesja może pozostać „niepotwierdzona”. Sprawdź oryginalne NI; brak potwierdzenia nie jest traktowany jako sukces.
6. Sprawdzenia własności i ścieżek ograniczają błędy, ale nie stanowią izolacji przed administratorem komputera lub celową równoczesną modyfikacją dysku.
7. Brak fizycznego testu migracji na drugi Mac, fizycznego Intela, macOS 14, pełnego VoiceOver, kompletnej ręcznej nawigacji klawiaturą i powiększenia systemowego 200%.
8. Kod backendu ma zwartą formę z długimi liniami. Mapa modułów i nowe wydzielone operacje poprawiają możliwość przeglądu; nie wykonano masowego formatowania całego silnika.
9. Lokalny podpis ad hoc nie jest publiczną notaryzacją. Nie wykonano publikacji ani użycia cudzych poświadczeń Apple.

Ten dokument opisuje przeprowadzony przegląd i dowody, a nie gwarancję braku wszystkich błędów.
