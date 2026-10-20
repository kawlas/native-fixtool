# Native FixTool — instrukcja

Wersja 0.3.5. Aplikacja na macOS 14 lub nowszy, dla Maców Apple Silicon i Intel.

**Wersja nieoficjalna i niezależna od Native Instruments. Bezpłatna wyłącznie do użytku prywatnego.** Użytek firmowy, organizacyjny, zawodowy i komercyjny jest zabroniony, także w jednoosobowej działalności i freelancingu. Samo zgłoszenie autorowi nie udziela zgody. Obowiązuje [Native FixTool Private Use License 1.0](LICENSE), nie MIT. Pełny tekst jest też dostępny w menu **O Native FixTool**. Native Instruments nie jest autorem narzędzia i go nie zatwierdza. Nadal potrzebujesz własnych licencji NI na instrumenty i biblioteki.

## Instalacja na Macu

1. Pobierz DMG z wydania projektu i sprawdź jego sumę SHA-256 z dołączonym plikiem `.sha256`.
2. Otwórz DMG i przeciągnij **Native FixTool.app** do **Applications / Aplikacje**.
3. Uruchom aplikację z Aplikacji.

Obecne wydanie ma podpis lokalny (ad-hoc), bez Developer ID i notaryzacji Apple.
Jeśli macOS zgłasza nieznanego dewelopera, a masz pewność co do źródła pobrania,
po próbie otwarcia sprawdź **Ustawienia systemowe → Prywatność i ochrona → Otwórz mimo to**.
Ta opcja może nie być dostępna przy zasadach narzuconych przez administratora.
Jeśli system zgłasza uszkodzenie lub złośliwe oprogramowanie, nie traktuj tego jak zwykłego komunikatu o nieznanym autorze.
[Instrukcja Apple](https://support.apple.com/en-us/102445) opisuje te przypadki osobno.

## Zacznij tutaj

1. Otwórz Native Access. Zaloguj się na konto, na którym masz kupione produkty.
2. Otwórz **Native FixTool.app**. Wybierz **Naprawa**, **Aktualizacje** albo **Przeniesienie**.
3. Wskaż wspólny folder bibliotek. W Twoim przypadku jest to `/Volumes/MUZA/NI`.
4. Poczekaj na listę. Samo wskazanie folderu i odczyt listy nie pobierają dźwięków.

Wybierz folder **NI**, w którym są foldery instrumentów. Nie wybieraj pojedynczego instrumentu ani pliku WAV.

```text
MUZA
└── NI                    ← wybierz ten folder
    ├── Fables Library
    ├── Kontakt Factory Library
    └── inne biblioteki
```

Jeżeli macOS pyta o dostęp do dysku, zezwól na niego. Przy braku dostępu kliknij **Zmień folder…** i wybierz folder ponownie.

## Naprawa

Użyj jej, gdy biblioteka jest na SSD, ale Native Access proponuje jej instalację lub naprawę.

| Zakładka | Co pokazuje |
| --- | --- |
| Wszystkie | Wszystkie foldery bibliotek znalezione w wybranym miejscu. |
| Zainstalowane | Native Access już rozpoznaje bibliotekę w tym dokładnym folderze. |
| Dostępne | Pliki są na dysku i można spróbować przywrócić ich rozpoznawanie. |
| Problemy | Nie da się wykonać automatycznej naprawy. Przy bibliotece jest powód. |

1. Otwórz **Dostępne**.
2. Zaznacz kwadrat przy nazwie biblioteki. **Zaznacz do naprawy** zaznacza wszystkie dostępne pozycje z aktualnie widocznej listy.
3. Kliknij **Sprawdź plan naprawy**. Przeczytaj podsumowanie.
4. Kliknij **Rozpocznij naprawę**. Dopiero teraz aplikacja zapisuje zmiany.
5. Poczekaj na odpowiedź Native Access. Wynik powinien zmienić się na **Zainstalowana**. Jeśli NI nie potwierdzi instalacji, nie oznaczamy jej jako zakończonej.

W podsumowaniu są dwie opcje:

- **Używaj tego folderu dla bibliotek w Native Access** — zmienia ustawienie Content location w NI na wybrany folder. Nie przenosi dźwięków.
- **Anuluj ponowne pobieranie tylko potwierdzonych, aktualnych bibliotek** — usuwa zbędne zadanie tylko po potwierdzeniu dokładnego folderu i aktualnej wersji przez NI. Nie anuluje prawdziwych aktualizacji.

Naprawa tworzy kopię danych instalacji przed zmianami. Może na czas pracy wstrzymać aktywne pobieranie NI. Potem próbuje wznowić dokładnie to zadanie, które sama wstrzymała, jeżeli nadal istnieje i jest wstrzymane. Nie wznawia zadań wcześniej wstrzymanych przez użytkownika. Przy błędzie wznowienia użyj przycisku wznowienia w Native Access i zachowaj raport.

**Zainstalowana** oznacza potwierdzone rozpoznawanie przez NI. Zwykły odczyt listy nie sprawdza każdego WAV-a.

## Aktualizacje

1. Wybierz **Aktualizacje**, a następnie folder bibliotek. Lista wczyta się automatycznie.
2. Zaznacz produkty, które chcesz zaktualizować.
3. Opcjonalnie kliknij **Sprawdź rozmiar pobierania**. Aplikacja porówna Twoje pliki z opisem nowej wersji udostępnionym przez NI. Nie porównuje instrumentów między sobą i nie pobiera dźwięków. Odczyt dużego SSD może potrwać.
4. Kliknij **Sprawdź plan aktualizacji**, przeczytaj listę i zatwierdź **Rozpocznij aktualizacje**.
5. Native Access sprawdza pliki, pobiera potrzebne dane i instaluje aktualizacje. Native FixTool pokazuje wynik odczytany z NI.

| Przycisk / opis | Znaczenie |
| --- | --- |
| Zaznacz wszystkie / Odznacz wszystkie | Zmienia wybór produktów; niczego nie instaluje. |
| Odśwież listę | Ponownie odczytuje dostępne wersje. |
| Jeszcze niesprawdzone | Nie wykonano opcjonalnego porównania plików. |
| Pliki już są na dysku | W chwili porównania dane pasowały do opisu nowej wersji. NI musi jeszcze potwierdzić aktualizację. |
| Do pobrania — szacunek | Szacowana ilość niepasujących fragmentów, bez narzutu sieci, ponowień i dodatkowych decyzji instalatora NI. |
| Odśwież postęp | Ponownie odczytuje stan bieżącej sesji NI. |
| Wstrzymaj aktualizacje / Wznów aktualizacje | Dotyczy tylko zadań uruchomionych w tej sesji przez Native FixTool. |
| Sprawdź pozostałe aktualizacje | Po zakończeniu sesji pozwala wybrać następne produkty. |

Nie każda aktualizacja będzie mała. Jeśli NI zmieni całe duże archiwum, jego ponowne pobranie może być konieczne. Narzędzie nie tworzy poprawek różnicowych, których producent nie dostarcza. Pasek pobierania w NI może obejmować sprawdzanie istniejących danych.

Porównanie jest opcjonalne. Jeśli je wykonasz, a następnie uruchomisz aktualizację, NI może odczytać te same pliki jeszcze raz. Zamknięcie Native FixTool nie zatrzymuje zadań już przyjętych przez NI.

## Przeniesienie

Na starym Macu, przed zmianą systemu:

1. Podłącz dysk i sprawdź, czy biblioteki działają w NI.
2. Wybierz **Przeniesienie** i folder bibliotek.
3. Kliknij **Zapisz dane bibliotek na dysku**. Poczekaj do zakończenia.

Zapisujemy informacje o instalacji w ukrytym folderze `.library-bridge` obok bibliotek. Dla bibliotek bez opisu `.nicnt` zapis obejmuje również listę plików i ich sumy kontrolne, więc może potrwać. To nie jest dodatkowa kopia dźwięków ani pełna kopia zapasowa SSD.

Na nowym Macu lub po ponownej instalacji macOS:

1. Podłącz ten sam dysk, razem z ukrytym folderem `.library-bridge`.
2. Zainstaluj Native Access i zaloguj się na swoje konto z licencjami.
3. Otwórz Native FixTool, wybierz **Naprawa** i ten sam folder bibliotek.
4. Sprawdź dostępne pozycje i zatwierdź naprawę.

**Jestem już na nowym Macu** otwiera Naprawę. **Zobacz zapisane dane** pokazuje zapisane informacje w Finderze. Nowy użytkownik macOS jest dozwolony; licencje nie przechodzą na inne konto NI. Aplikacje i wtyczki mogą wymagać osobnej instalacji w Native Access.

## Pozostałe przyciski

| Przycisk | Działanie |
| --- | --- |
| Wybierz folder… / Zmień folder… | Wskazuje miejsce bibliotek. Nie przenosi plików. |
| Odśwież listę bibliotek | Ponownie sprawdza rozpoznawanie bibliotek przez NI. |
| Przerwij tę operację | Prosi o bezpieczne zakończenie bieżącej pracy aplikacji. Wykonane zmiany są opisane w raporcie. |
| Otwórz Native Access | Otwiera NI, aby zalogować się lub zobaczyć jego kolejkę. |
| Jak to działa? | Instrukcja wewnątrz aplikacji. |
| Historia | Błędy i szczegóły bieżącej pracy. |
| Zapisz ostatni raport… | Eksportuje raport. Może zawierać nazwy produktów i lokalne ścieżki. |

Menu pod prawym przyciskiem na bibliotece pozwala pokazać jej folder i wykonać zaawansowane porównanie z lokalnym plikiem Metalink. Używaj opisu pochodzącego z NI; aplikacja nie potwierdza autentyczności dowolnego pliku XML.

## Typowe problemy

- **Brak dostępu:** wybierz folder ponownie i zezwól macOS na dostęp do woluminu.
- **Brak biblioteki na koncie:** sprawdź konto NI i licencję. Sam folder od kolegi nie dodaje licencji.
- **Kilka kopii:** aplikacja nie wybiera automatycznie między folderami tego samego produktu.
- **Brak `.nicnt`:** część bibliotek legalnie go nie ma. Potrzebny jest autentyczny wcześniejszy zapis instalacji lub instalacja/weryfikacja przez NI.
- **Inna wersja NI:** adapter obsługuje Native Access 3.26.0 i NTKDaemon 1.32 (R0). Inne wersje wymagają sprawdzonego adaptera.
- **Przerwana sesja aktualizacji:** sprawdź kolejkę w Native Access. Nie uruchamiaj od razu ponownej instalacji produktu.
- **Folder Native Instruments w Dokumentach:** zwykle zawiera presety i ustawienia użytkownika. To odrębne miejsce od dużych bibliotek na SSD. Narzędzie go nie przenosi.

Więcej: [dokumentacja techniczna](docs/ARCHITEKTURA.md), [odzyskiwanie i bezpieczeństwo](docs/BEZPIECZENSTWO-I-ODZYSKIWANIE.md), [wyniki przeglądu](docs/AUDYT-KODU.md).
