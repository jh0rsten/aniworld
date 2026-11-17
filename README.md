# YouTube Web App (iOS)

WebView-App für m.youtube.com mit Popup-Schutz und Domain-Sperre
(erlaubt: youtube.com, youtu.be, accounts.google.com, google.com).

## IPA unter Windows bauen

1. Auf github.com ein neues privates Repository anlegen und alle Dateien dieses Ordners hochladen
   (inklusive des Ordners `.github`).
2. Im Repository: **Actions → Build IPA → Run workflow**.
3. Nach ca. 3–5 Minuten unter **Artifacts** die Datei `YTApp-ipa` herunterladen und entpacken.

## IPA aufs iPhone installieren

1. Sideloadly (sideloadly.io) unter Windows installieren, iPhone per Kabel verbinden.
2. `YTApp.ipa` in Sideloadly ziehen, Apple-ID eingeben, auf Start klicken.
3. Auf dem iPhone: Einstellungen → Allgemein → VPN & Geräteverwaltung → Entwickler vertrauen.
4. Mit kostenloser Apple-ID läuft die App 7 Tage, danach in Sideloadly neu signieren.

## Hinweis

Werbung innerhalb von YouTube-Videos wird von dieser App nicht entfernt.
Dafür gibt es YouTube Premium.
