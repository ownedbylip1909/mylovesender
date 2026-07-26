# MyLove Sender

Native SwiftUI-iPhone-App zum Schreiben lokaler Entwuerfe und zum spaeteren Senden von Briefen an Bellas Android-App ueber Supabase.

## Einrichtung

1. Oeffne das Projekt in Xcode 27.
2. Fuege das offizielle Supabase-Swift-Paket hinzu: `https://github.com/supabase-community/supabase-swift.git`. Das Produkt `Supabase` muss mit dem App-Target verknuepft sein. Die offizielle Supabase-Doku nennt dieses Paket fuer Swift Package Manager.
3. Kopiere `Secrets.example.xcconfig` nach `Secrets.xcconfig`.
4. Trage `SUPABASE_PUBLISHABLE_KEY` ein. Verwende nur den Publishable Key, niemals Secret- oder Service-Role-Keys.
5. Stelle sicher, dass `Secrets.xcconfig` als lokale Base Configuration fuer Debug/Release eingebunden ist oder die beiden Build Settings `SUPABASE_URL` und `SUPABASE_PUBLISHABLE_KEY` aus dieser Datei kommen.
6. In der generierten Info.plist werden `SUPABASE_URL` und `SUPABASE_PUBLISHABLE_KEY` aus Build Settings gelesen.

## Supabase-Backend

Die App simuliert keine erfolgreiche Verbindung. Ohne RPC `claim_mailbox_pairing_code` bleibt der Status ehrlich bei `Nicht verbunden` beziehungsweise `Verbindung fehlgeschlagen`. Der sichere Backend-Vorschlag liegt in `Supabase/required_pairing_backend.sql`.

Damit bearbeitete Briefe in Supabase aktualisiert werden, muss `create_mailbox_letter` den vorhandenen Datensatz anhand von `(mailbox_id, client_request_id)` per `on conflict ... do update` aktualisieren. Die aktuelle SQL-Datei enthaelt diese Aenderung.

## App Icon

`Resources/AppIconPlaceholder.svg` ist ein vektorbasiertes Platzhalter-Icon. Wenn Xcode Rasterbilder verlangt, ersetze die AppIcon-Slots im Asset Catalog mit finalen PNGs fuer alle iOS-App-Icon-Groessen, besonders 1024x1024 fuer App Store/Organizer und die iPhone-Home-Screen-Groessen.

## UI-Testmodus

Launch-Argument: `--ui-testing`. Dieser Modus ersetzt Biometrie und Netzwerk durch Mocks nur fuer Tests. Normale Builds umgehen die App-Sperre nicht.

## Installation auf eigenem iPhone

1. In Xcode mit deiner Apple-ID anmelden: Settings > Accounts.
2. Target `MyApp` waehlen, Signing & Capabilities auf `Automatically manage signing` lassen und dein Personal Team auswaehlen.
3. Dein iPhone per Kabel oder Developer Mode/WLAN verbinden und als Run Destination auswaehlen.
4. `Secrets.xcconfig` lokal fuellen.
5. Run druecken. Bei kostenlosem Apple-Developer-Konto muss die App eventuell auf dem iPhone unter Einstellungen > Allgemein > VPN & Geraeteverwaltung vertraut werden.
