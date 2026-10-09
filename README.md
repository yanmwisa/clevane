<p align="center">
  <img src="Clevane/screenshots/AppIcon-1024.png" width="112" alt="Clevane app icon">
</p>

<h1 align="center">Clevane</h1>

<p align="center">
  A private vault for your passwords, notes and files.<br>
  Everything is encrypted and stays on your Mac: no account, no cloud.
</p>

<p align="center">
  macOS 15 or later · Swift 6 · Apache License 2.0
</p>

<p align="center">
  <img src="Clevane/screenshots/04-vault.png" width="880" alt="The Clevane vault: tables in the sidebar, rows in the middle, the selected row on the right">
</p>

Clevane keeps what you would otherwise scatter across notes, spreadsheets and browsers in one encrypted file. You organise it in tables, each with its own columns, and every column is one of four kinds: **Text**, **Secret**, **Note** or **File**. Secrets stay folded until you ask to see them.

> Every screenshot below was rendered by the app itself, on a temporary vault filled with fictional data.

## Contents

- [Welcome and first vault](#welcome-and-first-vault)
- [Unlock](#unlock)
- [Get started](#get-started)
- [Tables and rows](#tables-and-rows)
- [Search](#search)
- [Documents and photos](#documents-and-photos)
- [Shape your tables](#shape-your-tables)
- [Backup, restore and import](#backup-restore-and-import)
- [Settings and About](#settings-and-about)
- [Dark mode](#dark-mode)
- [Security model](#security-model)
- [Build from source](#build-from-source)
- [Licence](#licence)

## Welcome and first vault

The first launch offers two paths: create a vault, or restore one from a backup. A new vault suggests a generated passphrase (EFF word list) that you can copy, save to a file, and keep inside the vault itself, in a Recovery table. Touch ID can be turned on at creation.

<table>
  <tr>
    <td><img src="Clevane/screenshots/01-welcome.png" alt="Welcome screen with Create a vault and Restore a backup"></td>
    <td><img src="Clevane/screenshots/02-create-vault.png" alt="Create vault screen with a generated passphrase"></td>
  </tr>
  <tr>
    <td align="center"><sub>Welcome</sub></td>
    <td align="center"><sub>Create a vault</sub></td>
  </tr>
  <tr>
    <td><img src="Clevane/screenshots/01b-welcome-quick-unlock.png" alt="Welcome screen offering quick unlock"></td>
    <td><img src="Clevane/screenshots/02b-create-quick-passphrase.png" alt="Create vault with quick unlock and a passphrase"></td>
  </tr>
  <tr>
    <td align="center"><sub>Welcome, with Touch ID available</sub></td>
    <td align="center"><sub>Passphrase plus Touch ID</sub></td>
  </tr>
</table>

## Unlock

The vault opens with the master password, or with Touch ID once quick unlock is on. The screen names the vault it is about to open. Clevane locks itself after a period of inactivity, when the Mac sleeps, when the screen locks, and on ⌘L.

<p align="center">
  <img src="Clevane/screenshots/03-unlock.png" width="760" alt="Unlock screen">
</p>

## Get started

An empty vault shows three steps: create a first table from a ready-made model (Logins, Bank Accounts, API Keys, Wi-Fi, Private Notes, Documents) or design your own, add what you keep or import it from a browser, then turn on quick unlock and make a backup.

<p align="center">
  <img src="Clevane/screenshots/03b-get-started.png" width="760" alt="Get started screen with three steps">
</p>

## Tables and rows

Tables live in the sidebar with their row count. The selected row opens on the right: **Show** reveals a secret, **Copy** puts a value on the clipboard and clears it after 30 or 60 seconds if it has not changed. A short guide walks through the screen the first time, and comes back from the **?** button.

<table>
  <tr>
    <td><img src="Clevane/screenshots/05-vault-row-revealed.png" alt="A row with a revealed secret"></td>
    <td><img src="Clevane/screenshots/05b-guide-tables.png" alt="Guide step pointing at the tables"></td>
  </tr>
  <tr>
    <td align="center"><sub>A secret, revealed on request</sub></td>
    <td align="center"><sub>The guide: tables</sub></td>
  </tr>
  <tr>
    <td colspan="2"><img src="Clevane/screenshots/05c-guide-row-detail.png" alt="Guide step explaining the row details"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><sub>The guide: row details, Show and Copy</sub></td>
  </tr>
</table>

## Search

Search (⌘K) filters the current table and lists matches from every other table underneath. It looks through Text and Note values and file names, never through Secret values.

<p align="center">
  <img src="Clevane/screenshots/05d-search-all-tables.png" width="760" alt="Search results across all tables">
</p>

## Documents and photos

File columns keep photos and documents up to 50 MB each, encrypted with the vault key. Photos are previewed in memory; a file only leaves the vault in clear when you export it.

<p align="center">
  <img src="Clevane/screenshots/05e-documents-photo.png" width="760" alt="Documents table with a photo preview">
</p>

## Shape your tables

Every table has its own columns: add, rename, reorder, and choose their kind. Rows are added and edited in a sheet. Deleting a table always asks first, and says how many rows go with it.

<table>
  <tr>
    <td><img src="Clevane/screenshots/06-sheet-columns.png" alt="Columns sheet"></td>
    <td><img src="Clevane/screenshots/07-sheet-add-row.png" alt="Add Row sheet"></td>
  </tr>
  <tr>
    <td align="center"><sub>Columns</sub></td>
    <td align="center"><sub>Add Row</sub></td>
  </tr>
  <tr>
    <td><img src="Clevane/screenshots/08-sheet-new-table.png" alt="New Table sheet"></td>
    <td><img src="Clevane/screenshots/08b-delete-table-confirmation.png" alt="Delete table confirmation"></td>
  </tr>
  <tr>
    <td align="center"><sub>New Table</sub></td>
    <td align="center"><sub>Delete, with confirmation</sub></td>
  </tr>
</table>

## Backup, restore and import

**Create Backup** writes an encrypted copy (`clevane-YYYY-MM-DD.cvbackup`) to a folder you choose; your master password opens it on another Mac. **Restore** opens a backup as a separate vault and leaves the current one as it is. **Import** reads the CSV exports of Chrome, Google Password Manager, Safari and Firefox, then offers to move the plain-text export to the Trash.

<p align="center">
  <img src="Clevane/screenshots/09-backup-restore.png" width="760" alt="Backup and Restore screen">
</p>

## Settings and About

Settings hold the auto-lock delay, clipboard clearing, quick unlock, the master password, and the About section: version, author, licence, and an update check against this repository's releases. The check at launch is off by default, so the app stays offline unless you ask.

<p align="center">
  <img src="Clevane/screenshots/10-settings.png" width="760" alt="Settings screen with the About section">
</p>

## Dark mode

Clevane follows the system appearance, in black, white and grey.

<table>
  <tr>
    <td><img src="Clevane/screenshots/11-vault-dark.png" alt="Vault in dark mode"></td>
    <td><img src="Clevane/screenshots/12-settings-dark.png" alt="Settings in dark mode"></td>
  </tr>
  <tr>
    <td colspan="2"><img src="Clevane/screenshots/13-unlock-dark.png" alt="Unlock screen in dark mode"></td>
  </tr>
</table>

## Security model

- **One file per vault.** Table names, column names, values, settings and the vault name are all inside the encrypted part, sealed with AES-GCM (CryptoKit). The clear header is authenticated with the content.
- **Your password never encrypts data directly.** A random vault key is wrapped by a key derived from the master password with Argon2id (libsodium, 256 MiB, 3 passes). Changing the password re-wraps the same key.
- **Touch ID through the Secure Enclave.** The vault key is sealed to a P-256 key that never leaves the Mac and only works after Touch ID or the Mac password. The master password always works, on every Mac.
- **Safe writes.** Every edit is written atomically; a failed write leaves the previous file intact. A second window on the same vault is refused.
- **Locking forgets.** Locking drops the key, hides the content and clears a copied secret if the clipboard still holds it.
- **Nothing is logged**, and error messages never repeat a value.

Limits, stated plainly: decrypted values live in memory while the vault is open, and another app can read the clipboard before it is cleared. More detail in [`Clevane/README.md`](Clevane/README.md).

## Build from source

Command Line Tools are enough; Xcode is not required.

```bash
scripts/test.sh
```

```bash
scripts/build-app.sh release
```

```bash
open Clevane/build/release/Clevane.app
```

The app is signed ad hoc. Its vault lives in `~/Library/Application Support/Clevane/`; backups go to `~/Documents/Clevane Backups` unless you choose another folder.

| Folder | Role |
| --- | --- |
| [`VaultCore/`](VaultCore) | Vault logic and cryptography: file format, keys, session, model, clipboard, auto lock, backup, Touch ID. No UI. |
| [`Clevane/`](Clevane) | The SwiftUI app, its tests and the screenshots above. |
| [`scripts/`](scripts) | Test, build, icon and word list scripts. |
| [`docs/palette-clevane.md`](docs/palette-clevane.md) | The colour palette, light and dark (in French). |

## Licence

Copyright 2026 Yannick Kibale. Licensed under the [Apache License, Version 2.0](LICENSE); see also [`NOTICE`](NOTICE).

Cryptography by libsodium and swift-sodium (Frank Denis, ISC License). Passphrase words from the EFF large wordlist (Electronic Frontier Foundation, CC BY 3.0).
