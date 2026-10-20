# Dane, mechanizmy ochronne i odzyskiwanie

## Co wolno aplikacji

Odczytuje lokalizacje, wersje i własność z zalogowanego NI. Może zlecić rozpoznanie istniejącego folderu, odtworzyć autentyczny wpis po weryfikacji plików i przekazać zatwierdzoną aktualizację do NI. Nie dodaje licencji, nie obchodzi aktywacji, nie zmienia starszego numeru wersji na numer serwera i nie uznaje brakujących aplikacji lub wtyczek za zainstalowane.

Naprawa oraz porównanie nie przenoszą ani nie usuwają sampli. Zatwierdzona aktualizacja pozwala instalatorowi NI zmieniać pliki biblioteki. Kopia metadanych nie zastępuje pełnej kopii SSD.

## Dane logowania i prywatność

- Nie ma formularza hasła NI, telemetrii ani zewnętrznej usługi projektu.
- Token istniejącej sesji NI jest pobierany lokalnie i używany w pamięci do zapytań HTTPS GET pod stały adres API NI.
- Token jest przekazywany do curl przez stdin. Nie trafia do argumentów procesu ani raportów.
- Surowe odpowiedzi zawierające podpisane adresy pobierania nie są eksportowane do raportów.
- Raporty i plany zawierają nazwy produktów, lokalne ścieżki, wersje i informacje diagnostyczne. Sprawdź je przed udostępnieniem.
- Runtime przygotowany z własnej instalacji NI zawiera kod NI. Jest lokalny; nie dołączaj go do publicznego archiwum źródeł.

Archiwum tworzone przez `scripts/source-archive.py` nie zawiera `.build`, `.git`, `vendor`, plików live scan, runtime, osobistych raportów ani sesji. Cały folder projektu na Twoim pulpicie zawiera również lokalne materiały robocze i stare wyniki. Do przekazania innej osobie używaj wygenerowanego archiwum źródeł lub instalatora, po własnym przeglądzie.

## Wiarygodność zapisu na dysku

Pliki receipts są lokalną kopią autentycznych danych, nie certyfikatem podpisanym przez NI. Muszą pochodzić z zaufanej instalacji. Nie chronią przed osobą, która świadomie przerobi sam zapis i ma dostęp do konta/pliku systemowego. Własność i aktywacja pozostają po stronie NI.

Biblioteki z `.nicnt` trafiają do weryfikacji lokalizacji przez NI. Zapis samego deskryptora nie uprawnia do odtworzenia pełnej instalacji. Przy odtwarzaniu bez deskryptora każdy zapisany plik musi istnieć i zgadzać się z SHA-256; zachowujemy zapisany numer wersji. Istniejący wpis nie jest nadpisywany. Autentyczne aliasy nazw wpisów są zachowywane w kopii; niejednoznaczne odtworzenie aliasu jest blokowane.

## Gdy przerwiesz pracę

Przycisk **Przerwij tę operację** wysyła prośbę o zakończenie. Operacja zapisu kończy bieżący bezpieczny krok. Wykonanych i potwierdzonych zmian nie cofamy zbiorczo. Raport wymienia ukończone działania. Nowy wpis z receipt, którego NI nie potwierdzi, podlega ostrożnemu cofnięciu tylko wtedy, gdy jego treść nadal jest dokładnie taka jak zapisana przez narzędzie.

Zadania aktualizacji już przyjęte przez NI działają dalej po zamknięciu GUI. Jeśli aplikacja przestała pokazywać sesję, sprawdź kolejkę NI. Nie usuwaj istniejącej instalacji, aby „odblokować” aktualizację.

Nagłe odłączenie dysku, wyłączenie zasilania lub SIGKILL mogą przerwać zapis raportu lub sprzątanie. Żadne narzędzie użytkownika nie gwarantuje wtedy pełnego rollbacku. Po powrocie dysku odczytaj stan NI i raport przed następną operacją.

## Blokada operacji

`<folder>/.library-bridge/operation.lock` zapobiega równoczesnym zapisom tego narzędzia dla wybranego katalogu. Blokada nie zatrzymuje Native Access ani innego użytkownika/klienta.

Nie usuwaj jej podczas pracy. Przy blokadzie z innego Maca najpierw sprawdź zapisany host, PID i datę oraz upewnij się, że na tamtym komputerze nic nie pracuje. Martwy proces na tym samym hoście jest obsługiwany automatycznie. Identyfikacja PID ma zwykłe ograniczenie ponownego użycia PID przez system.

## Odzyskiwanie krok po kroku

1. Przerwij nowe operacje w Native FixTool. Sprawdź kolejkę Native Access.
2. Sprawdź, czy właściwy SSD jest podłączony i czy folder biblioteki nadal istnieje.
3. W Historii zachowaj ostatni raport. Oryginalne kopie są w `.library-bridge/backups/`.
4. Wybierz folder ponownie i odśwież listę. Plan sprzed zmiany dysku lub stanu instalacji nie jest ważny.
5. Wstrzymane przez naprawę pobieranie, którego nie udało się wznowić, wznów w NI.
6. Jeżeli biblioteka jest oznaczona jako problem, przeczytaj powód; nie kopiuj przypadkowego pliku wersji ani wpisu innego produktu.
7. Ręczne przywrócenie systemowych plików JSON/plist zostaw jako osobny, świadomy krok po porównaniu kopii i bieżącego stanu. Nie wykonuj zbiorczego nadpisania katalogu `installed_products`.

## Dystrybucja

Od wydania 0.3.2 własny kod, aplikacja i dokumentacja są na [Native FixTool Private Use License 1.0](../LICENSE): bezpłatne wyłącznie do użytku prywatnego; użytek firmowy, organizacyjny, zawodowy i komercyjny jest zabroniony. To własna licencja, nie MIT ani licencja open source. Źródła są dostępne na jej warunkach. Starsze kopie wcześniej zgodnie z prawem otrzymane na innych licencjach zachowują swoje warunki. Dołączone Node ma własne informacje licencyjne w aplikacji; nie zmieniamy licencji składników osób trzecich. Źródła NI nie są rozpowszechniane. Aplikacja jest niezależna od Native Instruments.

Lokalne wydanie ma podpis ad hoc. Wydanie publiczne wymaga własnego Developer ID oraz notaryzacji. Skrypt notaryzacji wysyła instalator do Apple i jest osobnym, świadomie uruchamianym etapem; zwykła kompilacja nie publikuje niczego.
