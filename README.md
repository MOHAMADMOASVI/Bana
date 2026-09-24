# Bana

A lightweight native macOS app (SwiftUI, macOS 13+) that finds local projects in a folder, runs their dev servers with live logs, LAN links and QR codes, and **prepares upload-ready packages for shared hosting**.

## Run

| Detected by | Type | Default command |
|---|---|---|
| `artisan` | Laravel | `php artisan serve --host=0.0.0.0 --port={port} --no-reload --tries=1` |
| `composer.json` / `index.php` / `public/index.php` | PHP | `php -S 0.0.0.0:{port}` (+ `-t public` when `public/index.php` exists) |
| `requirements.txt` / `main.py` | Python | FastAPI → `uvicorn`, Flask → `flask run`, otherwise `python3 -u main.py` (`.venv/bin` first) |
| `package.json` | Node.js | `npm run dev` (+ host/port flags for Vite, Astro, Nuxt, Next) |
| `docker-compose.yml` / `compose.yaml` | Docker | `docker compose up` (URL from the first published port) |

Scanning goes 5 levels deep, skips `node_modules`, `vendor` and similar, and stops at the first folder that is a project. You can override the port, command (`{port}` placeholder, no shell) and type per project. Settings are stored in `~/Library/Application Support/Bana/settings.json`. Quitting stops every server's whole process tree.

## Prepare for Hosting

The **Hosting** button builds `<name>-hosting-<date>.zip` (on the Desktop by default) for cPanel/DirectAdmin hosts with no SSH:

* **Laravel / PHP with `public/`**: `<app>/` sits outside the web root with `composer install --no-dev -o`, and `public_html/` gets `public/` with `index.php` repointed to `../<app>/` and `usePublicPath`. Laravel also gets a generated `.env` (production, debug off, fresh `APP_KEY`, `APP_URL` from “Site address”). `storage/app`, logs, caches, tests and the local `.env` are left out.
* **Plain PHP**: the project goes into `public_html/`.
* **Node**: the static build output (`dist/`, `build/` or `out/`) goes into `public_html/`, or the whole project if there is none.
* **Python / Docker**: the project without venvs, caches or `.git`.
* **Review files**: backups, archives, `.sql`/`.bak` dumps and `backups/` folders are left out by default, because in a web root they are plain downloads. Secret-looking files are flagged for you to decide.
* **Project script**: if the project has `deploy/build.sh` or `deploy/<target>/build.sh`, it can run that instead, and Bana finds the zip it produces.

## Build

```bash
xcodegen generate                 # after editing project.yml
open Bana.xcodeproj
Scripts/make-dmg.sh               # Release build → dist/Bana-<version>.dmg
```

Tests: `xcodebuild -scheme Bana -derivedDataPath build test`. Opt-in run against real projects (starts every server and builds every hosting package): `TEST_RUNNER_LAUNCHER_REAL_ROOT=~/Projects xcodebuild … test -only-testing:BanaTests/RealProjectsTests`.

Icon: `swift Scripts/make-icon.swift Bana/Resources/Assets.xcassets/AppIcon.appiconset Scripts/logo_bana.png`.

The UI is Persian or English, chosen in Settings (⌘,) together with appearance, projects folder and hosting output folder. Strings are `tr("فارسی", "English")` in `Views/Localization.swift`; switching rebuilds the UI and flips its direction. Rendered previews: `TEST_RUNNER_BANA_SNAPSHOT_DIR=/tmp/snap xcodebuild … -only-testing:BanaTests/SnapshotTests`.

App Sandbox is off (`Bana.entitlements`): servers need the whole home folder (`~/.nvm`, `~/.pyenv`, `~/.composer`, `/tmp`).
