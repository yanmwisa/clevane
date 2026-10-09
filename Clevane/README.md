# Clevane app (V1)

A small, local, encrypted vault for macOS, organised in tables with your own columns (Text, Secret, Note).
Interface in English, design direction D (shape of macOS 26, editorial voice). Built on October 8, 2026.

## Layout

| Folder | Role |
| --- | --- |
| `../VaultCore/` | All vault logic and cryptography: file format, keys, session, model, clipboard, auto lock, backup, Touch ID keychain. No SwiftUI, no AppKit. |
| `Sources/ClevaneUI/` | SwiftUI screens (Welcome, Create Vault, Unlock, Vault with its sheets, Backup & Restore, Settings) and the system glue (pasteboard, sleep and screen lock). |
| `Sources/Clevane/` | The app entry point. |
| `Tests/ClevaneUITests/` | App flows on a temporary vault (Swift Testing). |
| `Resources/AppIcon.icns` | App icon, drawn in code (`AppIconArtwork`) and converted by `scripts/make-icon.sh`. |
| `screenshots/` | Renders of every screen, light and dark, produced by the app itself on fictional data. |

## Build, test, run (Command Line Tools are enough)

```bash
scripts/test.sh
```

```bash
scripts/build-app.sh release
```

```bash
open Clevane/build/release/Clevane.app
```

The app is signed ad hoc. Its vault lives in `~/Library/Application Support/Clevane/Vault.clevane`; backups go to
`~/Documents/Clevane Backups` unless you choose another folder.

Screens again (debug build only, temporary vault, fictional data, writes PNGs then quits):

```bash
scripts/build-app.sh debug && CFFIXED_USER_HOME="$(mktemp -d)" CLEVANE_SNAPSHOT_DIR="$PWD/Clevane/screenshots" Clevane/build/debug/Clevane.app/Contents/MacOS/Clevane
```

## Security model in short

- One file per vault, format v1: clear header (vault ID, Argon2id parameters, wrapped vault key) then the content,
  sealed with AES-GCM (CryptoKit). The header is authenticated with the content. Table names, column names, values,
  settings and the vault name are all inside the encrypted part.
- The vault key is random and wrapped by a key derived from the master password with Argon2id (libsodium 1.0.22 via
  swift-sodium 0.11.0, 256 MiB, 3 passes). Changing the password re-wraps the same key.
- Every validated edit is written atomically (temporary file in the same folder, flushed, then replaced); a failed write
  leaves the previous file intact. An exclusive lock file refuses a second window on the same vault.
- The session is the only authority. Locking (manual, inactivity, system sleep, screen lock, quit) forgets the key,
  hides the content, clears a copied secret if the clipboard still holds it, and closes the session generation, so a
  late result from before the lock is rejected.
- Copy marks the value as concealed (nspasteboard.org convention) and clears it after 30 or 60 seconds, only if
  unchanged.
- Nothing is logged. Error messages never repeat a value.

Limits, stated plainly: decrypted values live in memory while the vault is open (no guaranteed wiping on macOS);
another app can read the clipboard before it is cleared.

## Touch ID

Quick unlock goes through the Secure Enclave (`SecureEnclaveKeyStore` in VaultCore): a P-256 key that never leaves this
Mac and only works after Touch ID with the fingers enrolled today, or the Mac password. The vault key is sealed to it with
HPKE (CryptoKit) and stored in `~/Library/Application Support/Clevane/QuickUnlock/<vault id>.quickunlock` (0600), useless
on any other Mac. It needs no Xcode or provisioning profile. The master password always works, on every Mac.

## Files, import and search

- File columns keep photos and files up to 50 MB, each sealed with the vault key (AES-GCM, bound to the vault and to the
  file) in `<vault>.files/`. Photos are previewed in memory; a file leaves the vault in clear only through Export.
  Files no row uses are removed when the vault is saved or opened. Backups are packages holding the vault and its files.
- Import reads the CSV exports of Chrome, Google Password Manager, Safari and Firefox into an Imported Logins table,
  then offers to move the export (plain text) to the Trash.
- Search (⌘K) looks through Text and Note values and file names of every table, never through Secret values.

## Demo vault (debug build)

`CLEVANE_DEMO_VAULT=<path>` opens a separate vault, created on first launch and filled with fictional logins, bank
accounts, API keys, Wi-Fi, notes and documents (drawn photos and PDFs). Password: `sample demo passphrase`.
Preferences stay in memory; the real vault and settings are untouched.

```bash
open -n --env "CLEVANE_DEMO_VAULT=$HOME/Documents/Clevane Demo/Demo.clevane" build/debug/Clevane.app
```

## About and updates

Clevane menu → **About Clevane** shows what the app is, its version, its author and its licence; Settings → About has the
same, plus **Check Now** and **Check at launch** (off by default, so the app stays offline). A check reads the latest
release of `yanmwisa/clevane` on GitHub, compares versions, and offers to open the download page. It sends an ordinary web
request only, nothing from the vault. Releases must be tagged `vX.Y.Z` and match `CFBundleShortVersionString` in
`scripts/build-app.sh`. While the repository is private, a check finds no published version.

## Licence

Copyright 2026 Yannick Kibale. Licensed under the Apache License, Version 2.0: see `LICENSE` and `NOTICE` at the
repository root.

## Credits

Passphrase words: the EFF large wordlist by the Electronic Frontier Foundation (https://www.eff.org/dice), CC BY 3.0,
without its four hyphenated words (`scripts/make-wordlist.sh` regenerates `VaultCore/Sources/VaultCore/PassphraseWords.swift`).
Cryptography: libsodium and swift-sodium by Frank Denis, ISC License.
