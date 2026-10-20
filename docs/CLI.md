# Interfejs poleceń backendu

Uruchomienie: `<node> backend/cli.mjs <polecenie> [opcje]`. Wynik to NDJSON na stdout; każda linia jest osobnym JSON-em. `progress` opisuje etap, `result` wynik, `error` błąd. Diagnostyka zależności może trafić na stderr. Kody zakończenia: 0 — wynik, 1 — błąd, 130 — przerwanie obsłużone jako błąd CANCELLED. Częściowe wyniki poleceń mogą mieć `cancelled: true` i kod 0; zawsze czytaj wynik, a nie sam kod procesu.

| Polecenie | Wymagane opcje | Skutek |
| --- | --- | --- |
| `discover` | brak | Odczyt Content location z NI. |
| `scan` | `--library` | Inwentaryzacja i lokalny plan naprawy. |
| `repair` | `--library`, `--plan`, `--selected` | Zatwierdzona naprawa według świeżego planu. |
| `snapshot` | `--library` | Kopie i receipts do przeniesienia na dysku. |
| `verify` | `--library`, `--manifest` | Lokalna weryfikacja SHA-256, bez połączenia z NI. |
| `updates` | `--library` | Odczyt katalogu aktualizacji i lokalny plan. |
| `update-audit` | `--library`, `--plan`, `--selected` | Pobranie metadanych manifestów i porównanie SSD. |
| `update-start` | `--library`, `--plan`, `--selected` | Oficjalne zlecenia UPDATE do NI i zapis sesji. |
| `update-status` | `--library`, `--session` | Odczyt postępu i potwierdzenia wersji. |
| `update-pause` | `--library`, `--session` | Wstrzymanie pobieranych zadań tej sesji. |
| `update-resume` | `--library`, `--session` | Wznowienie wstrzymanych zadań tej sesji. |

`--selected` to JSON tablicy identyfikatorów z odpowiedniego planu, np. `'["id-z-planu"]'`. Nie używaj tytułu produktu zamiast ID. `--plan` i `--session` są ścieżkami do autentycznych plików wygenerowanych przez aplikację. Nie edytuj ich, aby wymusić operację.

Naprawa ma opcje `--set-content true` i `--cancel-redundant true`, odpowiadające polom podsumowania GUI. Bez literalnej wartości `true` nie wykonuje tych dodatkowych działań.

Plany i sesje mają `schema: 1`, wersję adaptera i tożsamość katalogu `{path, device, inode}`. Plan naprawy zawiera ID, folder, UPID, stan i hash deskryptora. Plan aktualizacji zawiera wersje i ID artefaktu. Sesja zapisuje przyjęte przez NI deployment IDs. Zerowa liczba przyjętych zleceń nie jest zwracana do GUI jako aktywna sesja.

Nie jest to publiczne API Native Instruments. Polecenia zapisujące powinny być wykonywane przez normalny przepływ GUI z czytelnym podsumowaniem. Przykłady diagnostyczne bez zmian są w [ROZWOJ.md](ROZWOJ.md).
