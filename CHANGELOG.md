# Zmiany

## 0.3.5 — Native FixTool

- Nowa nazwa aplikacji, okna, menu, dokumentacji i pakietów: Native FixTool.
- Zachowane istniejące ustawienia, dane i warunki licencji wyłącznie prywatnej.
- Przygotowanie publicznego repozytorium `kawlas/native-fixtool` z kodem i dokumentacją, bez prywatnych danych NI.

## 0.3.4 — wygląd w stylu Native Access

- Roboto z Google Fonts (SIL OFL 1.1), jasne tło, neutralne szarości i oszczędny niebieski akcent.
- Płaskie prostokątne przyciski, tekstowe zakładki i listy z cienkimi liniami zamiast pasów.
- Zachowane zadania Naprawa / Aktualizacje / Przeniesienie oraz osobne zatwierdzanie zmian.
- Czcionka dołączona do aplikacji i źródeł, z własną licencją; nie wymaga instalowania w systemie.
- Rzeczywisty test przez GUI: George Duke Soul Treasures 1.0.0 → 1.3.1, 48 brakujących plików / 1,79 MB pobranych zamiast całej biblioteki 3,86 GB. Sesja zachowana po zamknięciu i ponownym otwarciu aplikacji.

## 0.3.3 — test aktualizacji, symulacje i lint

- Oficjalny UPDATE Scene – Lotus 1.1.1 → 1.1.2 przez zainstalowany pakiet 0.3.2: 387 plików wykorzystanych z SSD, potwierdzenie NI i ponowne haszowanie.
- 36 testów backendu, nowe przypadki błędów blokady, PID, rollbacku, zmienionych wpisów i granic odczytu fragmentów.
- Błąd sprawdzenia PID pozostawia blokadę; błąd rollbacku trafia do raportu.
- Rozszerzone symulacje interfejsu i jasny komunikat anulowania startu aktualizacji.
- Powtarzalny lint ESLint/Prettier/swift-format oraz kontrola składni zsh/Python. Narzędzia npm wyłącznie do rozwoju, poza aplikacją.
- Uporządkowane formatowanie kodu Swift i JavaScript.

## 0.3.2 — licencja wyłącznie prywatna

- Własna NI Fix Tool Private Use License 1.0 zamiast MIT dla bieżącego wydania.
- Bezpłatny użytek prywatny przez osoby fizyczne; zakaz użycia firmowego, organizacyjnego, zawodowego i komercyjnego, także JDG i freelancingu.
- Wyraźne oznaczenie nieoficjalnego charakteru w dokumentacji i aplikacji.
- Informacja na ekranie Start, w Pomocy i oknie O NI Fix Tool, z odnośnikiem do pełnego tekstu licencji.
- Licencje składników osób trzecich i warunki wcześniej otrzymanych starszych kopii pozostają odrębne.
- Brak zmian w mechanizmie naprawy lub aktualizacji bibliotek.

## 0.3.1 — przegląd kodu i pełna dokumentacja

- Cały projekt roboczy przeniesiony do folderu na pulpicie.
- Polska instrukcja użytkownika, dokumentacja architektury, CLI, budowania, danych, odzyskiwania i wyników audytu.
- Naprawa wznawia dokładnie zadanie NI, które sama wstrzymała, jeżeli nadal jest wstrzymane. Próba wznowienia także przy błędzie naprawy.
- Preferencje, własność, wersja, ścieżka i kolejka są sprawdzane ponownie tuż przed każdym zleceniem aktualizacji; sprawdzane jest też przerwanie przez użytkownika.
- Sesja z zerem przyjętych aktualizacji nie blokuje GUI jako aktywna sesja.
- Osobna kontrola sprawdzonej odpowiedzi wersji NTKDaemon.
- Świeży pakiet przy każdej kompilacji; numer wydania w GUI i skryptach pochodzi z Info.plist.
- Powtarzalne archiwum źródeł bez prywatnych danych i materiałów NI.
- Dodatkowe testy sytuacji zmieniających się między planem a zleceniem.

## 0.3.0 — czytelny interfejs

- Start: Naprawa / Aktualizacje / Przeniesienie.
- Filtry: Wszystkie / Zainstalowane / Dostępne / Problemy.
- Objaśnienia przycisków i osobne zatwierdzanie zmian.
- Instrukcje wewnątrz aplikacji, wybór folderu z podpowiedzią NI.

## 0.2.0 — aktualizacje

- Oficjalny katalog, porównanie SHA-256 i fragmentów, szacowanie transferu.
- Wyłącznie UPDATE, kontrola duplikatów, potwierdzenie wersji i folderu przez NI.

## 0.1.0 — naprawa i przeniesienie

- Rozpoznawanie istniejących bibliotek i autentyczne kopie danych instalacji.
- Przenośne receipts; pełne hasze dla bibliotek bez deskryptora.
- Uniwersalna aplikacja macOS z własnym runtime Node.
