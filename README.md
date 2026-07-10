# FileNameChange

A small native Mac app that renames PDFs to **what they're actually about**.

Drop in files like `scan_20240311_0042.pdf` or `document (7).pdf` — the app reads
each PDF's content and suggests a real name like:

```
2024-03-03 Acme Invoice.pdf
Employment Agreement 2025.pdf
Jane Doe Resume.pdf
2026-01-15 Chase Bank Statement.pdf
```

You review the suggestions (or let it rename automatically), press **Rename All**,
and you're done. Files are renamed in place, and every rename can be reverted
from the list.

## Features

- **Drag & drop** PDFs (or whole folders) onto the window or the Dock icon —
  or pick them with ⌘O.
- **Reads the content**, not just the metadata: page-one typography, document
  type keywords, company names, people, and dates.
- **Scanned PDFs work too** — when there's no text layer, it OCRs the first
  pages automatically (Apple's Vision framework, fully on-device).
- **Three naming engines** (pick in Settings, ⌘,):

  | Engine | Quality | Needs | Privacy |
  |---|---|---|---|
  | **Built-in analysis** (default) | Good for invoices, statements, papers, letters… | Nothing | 100% offline |
  | **Apple Intelligence** | Great | macOS 26+, Apple silicon, Apple Intelligence on | 100% on-device |
  | **Claude API** | Best | An [Anthropic API key](https://console.anthropic.com/) | Sends the first pages of each PDF to the API |

  If an AI engine can't run (no key, offline, model unavailable), the app
  automatically falls back to the built-in analyzer — a drop always produces a name.
- **Name formatting options**: date prefixes for transactional documents
  (`2026-05-12 Acme Invoice`), Title Case / lowercase, spaces / hyphens / underscores.
- **Safe by design**: collision-proof naming (`Report 2.pdf`), per-file Revert,
  nothing is ever deleted or moved to another folder.

## Building it (2 minutes)

Requirements: a Mac running **macOS 13 Ventura or newer**, with the Xcode
Command Line Tools (free — run `xcode-select --install` once if you don't have them).

```bash
git clone https://github.com/Tech-Pilot/FileNameChange.git
cd FileNameChange
./build.sh --install     # builds and copies FileNameChange.app to /Applications
```

That's it — launch **FileNameChange** from Applications and drop PDFs in.

Other options:

```bash
./build.sh               # just build into ./build/FileNameChange.app
./build.sh --run         # build and open it
./build.sh --universal   # fat binary for Intel + Apple silicon Macs
swift run                # developer quick-start, no app bundle
swift test               # run the unit tests
```

You can also open the folder in Xcode (`File ▸ Open…` on `Package.swift`) and
press Run.

> **Grabbing the app from CI instead:** every push builds the app on GitHub
> Actions and uploads `FileNameChange.app.zip` as an artifact. Because a
> downloaded app is unsigned, macOS will quarantine it — right-click ▸ Open the
> first time, or run `xattr -dr com.apple.quarantine FileNameChange.app`.
> Building locally with `./build.sh` avoids all of that.

## Using the Claude engine

1. Open **Settings (⌘,) ▸ How names are chosen ▸ Claude API (cloud)**.
2. Paste an API key from [console.anthropic.com](https://console.anthropic.com/)
   — it's stored in your macOS Keychain, never in a plain file.
3. Optionally change the model. The default is `claude-sonnet-5`;
   `claude-haiku-4-5-20251001` is the fastest and cheapest and still names files well.
4. Click **Verify Key** to confirm it works.

Only the first ~3,500 characters of each PDF are sent, nothing else.

## How the built-in analyzer decides on a name

1. Cleans the PDF's metadata title if it has a real one (and salvages junk like
   `Microsoft Word - Q3_Sales_Report.docx` → `Q3 Sales Report`).
2. Otherwise finds the title typographically — the biggest text on page one.
3. Detects the document type (invoice, receipt, bank statement, contract, resume,
   boarding pass, lab results, …), the main company or person, and the primary
   date (e.g. the one next to "Invoice date:").
4. Composes the name: transactional documents become `2024-03-03 Acme Invoice`,
   titled documents keep their title.
5. If the PDF is a scan with no text layer, it OCRs the first two pages first.

## Troubleshooting

- **"No permission to change this file"** — macOS gates the Desktop, Documents,
  and Downloads folders. Approve the prompt, or grant access under
  System Settings ▸ Privacy & Security ▸ Files and Folders.
- **Password-protected PDFs** are skipped with a clear message; the app can't
  read inside them.
- **A scan produced a weak name** — the OCR only reads the first two pages;
  names from low-quality scans are marked *low confidence* so you can edit
  before renaming.

## Project layout

```
Sources/FileNameCore/        the app: models, services, SwiftUI views
Sources/FileNameChange/      thin @main entry point
Tests/FileNameCoreTests/     unit tests for naming heuristics & sanitizing
Scripts/make-icon.swift      renders the app icon at build time
build.sh                     builds ./build/FileNameChange.app
```

No third-party dependencies — just Apple's PDFKit, Vision, NaturalLanguage,
SwiftUI, and (optionally) the FoundationModels framework on macOS 26.
