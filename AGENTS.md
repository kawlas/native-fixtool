# Native FixTool — instrukcja dla kolejnego agenta

Ten plik dotyczy całego repozytorium. Przed zmianami przeczytaj
[przekazanie projektu](docs/PRZEJECIE-PROJEKTU.md), a następnie dokumentację
modułu, który zmieniasz. Nie zakładaj znajomości wcześniejszej rozmowy.
Na oryginalnym komputerze sprawdź też `.build/LOCAL-HANDOFF.md`, jeżeli istnieje:
zawiera prywatne lokalizacje dowodów i kontekst narzędzi. Nie publikuj tego pliku.

## Cel i granice

- Pomagamy muzykom ponownie rozpoznać posiadane biblioteki NI na istniejącym
  dysku oraz wykorzystać zgodne dane przy oficjalnej aktualizacji. Stan musi
  odpowiadać plikom i odpowiedziom NI, a nie tylko wyglądać poprawnie w GUI.
- Konto NI pozostaje źródłem uprawnień. Nie dodawaj produktów do konta, nie
  obchodź aktywacji, nie fabrykuj receiptów, wersji ani zakończenia instalacji.
- Biblioteka sampli, aplikacja/wtyczka oraz presety w Documents to różne dane.
  Nie przenoś ich ani nie usuwaj w ramach „porządkowania”.
- Nie obiecuj samych aktualizacji różnicowych dla każdego produktu. NI może
  dostarczyć zmieniony instalator wymagający pełnego pobrania. Porównanie
  plików nie jest instalacją; szacunek transferu nie jest pomiarem sieci.
- Własny kod i dokumentacja: prywatny użytek osobisty, bez firm i zastosowań
  zawodowych/komercyjnych. Obowiązuje `LICENSE`, nie MIT ani open source.

## Zasady implementacji

- AppKit + Swift, uruchamiany jako osobny proces dołączony Node; bez Electron,
  serwera WWW i zależności npm w działającej aplikacji. Komunikacja to NDJSON.
- Zachowaj `app.librarybridge.mac`, `LibraryBridge`, katalog wsparcia
  `Library Bridge` oraz `.library-bridge`, dopóki nie powstanie jawna migracja.
  Nazwa widoczna dla użytkownika: **Native FixTool**.
- Adapter obsługuje wyłącznie Native Access 3.26.0 / NTKDaemon 1.32 (R0),
  protokół 8.1.4. Nie usuwaj kontroli zgodności, aby uruchomić nową wersję NI.
  Nowy adapter wymaga analizy i testów, najpierw bez zapisu.
- Zachowaj kontrolę własności, dokładnej lokalizacji, tożsamości dysku,
  artefaktu, świeżości planu, konfliktów i duplikatów. Aktualizacje wyłącznie
  `DEPLOYMENT_TYPE_UPDATE`. Nie zastępuj błędu operacją reinstall/full.
- Odtwarzanie bez `.nicnt` wymaga autentycznego wcześniejszego wpisu i zgodności
  wszystkich zapisanych SHA-256; zachowuje pierwotną wersję. Nie nadpisuj
  istniejących wpisów. Rollback nie może usuwać późniejszych zmian NI.
- Zaznaczenie i podgląd planu nie rozpoczynają zapisów. Przycisk Start potwierdza
  konkretny plan. Nie wykonuj nowych instalacji na dysku użytkownika wyłącznie
  w celu rutynowego testowania dokumentacji albo wyglądu.
- Konta/tokeny tylko w pamięci; nagłówki curl przez stdin. Nie zapisuj haseł,
  tokenów, podpisanych URL-i ani kodu wydobytego z NI w repo lub wydaniu.

## UI i język

- Polski i angielski; proste komunikaty dla muzyków. Zadania: **Naprawa /
  Aktualizacje / Przeniesienie**. Filtry: **Wszystkie / Zainstalowane /
  Dostępne / Problemy**. Wyjaśnij czynność obok przycisku.
- Jasny styl inspirowany Native Access, Roboto z dołączoną SIL OFL; bez logotypów
  i grafiki NI. Zachowaj natywne role dostępności i obsługę klawiatury.
- Zamknij okna podglądu i Findera, które sam otworzyłeś. Nie zamykaj cudzych
  okien i nie pozostawiaj użytkownika w trybie QA z wyłączonym zapisem.

## Weryfikacja i przekazanie zmian

- Najpierw `git status`, przeczytaj odpowiednie dokumenty i testy. Nie resetuj
  cudzych zmian. Przedstaw wynik, wykonane sprawdzenia i istotne ograniczenia.
- Testy: `<node> --test tests/*.test.mjs`; lint: `./scripts/lint.sh`.
  Wybierz Node arm64/x64 zgodnie z hostem. Czysty checkout wymaga wcześniej
  `chmod +x build.sh scripts/*.sh`, `scripts/fetch-node.sh` i dla lintowania
  `scripts/setup-lint.sh`. Szczegóły: `docs/ROZWOJ.md`.
- Dla zmian silnika dodaj potrzebne testy błędów/niezmienników; dla kosmetyki
  nie pisz testów kopiujących implementację. Dla zmian UI wykonaj podgląd
  tylko do odczytu. Nie przedstawiaj symulacji jako testu na prawdziwym SSD.
- Nie publikuj przez `git add .` bez przeglądu. Sprawdź diff, pliki śledzone,
  ignorowanie `.env`/kluczy i zawartość archiwum. `.gitignore` nie chroni
  pliku, który był już śledzony.
- Publiczne źródła generuje `scripts/source-archive.py`; ten plik i przewodnik
  przejęcia muszą pozostać w archiwum. `.build`, runtime NI, skany i receipts
  są prywatne i nie są potrzebne osobie klonującej repozytorium.
- Opublikowane wydania są historycznymi artefaktami: nie podmieniaj ich pod
  tą samą nazwą po zmianach. Dokumentacja na `main` może być nowsza niż DMG.
- Uzupełniaj przewodnik przejęcia, `VERIFICATION.md` i historię zmian stosownie
  do zakresu. Nie zapisuj wyniku testu, którego nie wykonano.

## Punkt odniesienia

Stan na 20.10.2026: 0.3.5, build 8; publiczne repo
<https://github.com/kawlas/native-fixtool> i prerelease `v0.3.5`.
Wydanie ma podpis ad hoc, bez Developer ID/notaryzacji. Historyczny wynik:
36/36 testów backendu, 33/33 kontroli UI i lint; nie oznacza to, że przyszła
zmiana jest sprawdzona. Pozostałe ograniczenia i kolejność dalszych prac:
[PRZEJECIE-PROJEKTU.md](docs/PRZEJECIE-PROJEKTU.md).
