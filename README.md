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
  pages automatically (Apple's Vision framework, fully on-device, in the
  document's own language).
- **Three naming engines** (pick in Settings, ⌘,):

  | Engine | Quality | Needs | Privacy |
  |---|---|---|---|
  | **Built-in analysis** (default) | Good for invoices, statements, papers, letters… | Nothing | 100% offline |
  | **Apple Intelligence** | Great | macOS 26+, Apple silicon, Apple Intelligence on | 100% on-device |
  | **Claude API** | Best | An [Anthropic API key](https://console.anthropic.com/) | Sends the file's name and its first pages to the API |

  If an AI engine can't run (no key, offline, model unavailable), the app
  automatically falls back to the built-in analyzer — a drop always produces a name.
- **Name formatting options**: date prefixes for transactional documents
  (`2026-05-12 Acme Invoice`), Title Case / lowercase, spaces / hyphens / underscores —
  and every engine honors them, including the AI ones.
- **Safe by design**: collision-proof naming (`Report 2.pdf`), per-file Revert,
  nothing is ever deleted or moved to another folder. Reverted files stay
  reverted — **Rename All** won't touch them again.

## Installing from the disk image

Every push builds a **universal (Intel + Apple silicon) disk image** on GitHub
Actions: download the `FileNameChange.dmg` artifact from the latest
[Actions run](../../actions), open it, and **drag FileNameChange.app onto the
Applications folder** shown next to it. (There's also a bare
`FileNameChange.app.zip` artifact if you prefer.)

Because downloaded builds are not notarized, macOS quarantines them the first
time:

- **macOS 15 Sequoia and later:** try to open the app once, then go to
  **System Settings ▸ Privacy & Security**, scroll down, and click
  **Open Anyway**. (The old right-click ▸ Open trick no longer works on
  Sequoia.)
- **macOS 13–14:** right-click the app ▸ **Open** the first time.
- Either way, `xattr -dr com.apple.quarantine /Applications/FileNameChange.app`
  in Terminal also clears the quarantine.

Building locally (below) avoids all of that.

## Building it yourself (2 minutes)

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
./build.sh --dmg         # also package build/FileNameChange-<version>.dmg
swift run                # developer quick-start, no app bundle
swift test               # run the unit tests
```

You can also open the folder in Xcode (`File ▸ Open…` on `Package.swift`) and
press Run.

## Using the Claude engine

1. Open **Settings (⌘,) ▸ How names are chosen ▸ Claude API (cloud)**.
2. Paste an API key from [console.anthropic.com](https://console.anthropic.com/)
   — it's stored in your macOS Keychain, never in a plain file.
3. Optionally change the model. The default is `claude-sonnet-5`;
   `claude-haiku-4-5` is the fastest and cheapest and still names files well.
4. Click **Verify Key** to confirm it works.

What gets sent per PDF: the file's current name, its metadata title (if any),
and the first ~3,500 characters of its text. Nothing else — and nothing at all
with the other two engines.

## How the built-in analyzer decides on a name

1. Cleans the PDF's metadata title if it has a real one (and salvages junk like
   `Microsoft Word - Q3_Sales_Report.docx` → `Q3 Sales Report`).
2. Otherwise finds the title typographically — the biggest text on page one.
3. Detects the document type (invoice, receipt, bank statement, contract, resume,
   boarding pass, lab results, …), the main company or person, and the primary
   date (e.g. the one next to "Invoice date:").
4. Composes the name: transactional documents become `2024-03-03 Acme Invoice`,
   titled documents keep their title, and only transactional documents get the
   date prefix.
5. If the PDF is a scan with no text layer, it OCRs the first pages first.

## Troubleshooting

- **"No permission to change this file"** — macOS gates the Desktop, Documents,
  and Downloads folders. Approve the prompt, or grant access under
  System Settings ▸ Privacy & Security ▸ Files and Folders.
- **Password-protected PDFs** are skipped with a clear message; the app can't
  read inside them.
- **A scan produced a weak name** — the OCR only reads the first pages;
  names from low-quality scans are marked *low confidence* so you can edit
  before renaming.

## Project layout

```
Sources/FileNameCore/        the app: models, services, SwiftUI views
Sources/FileNameChange/      thin @main entry point
Tests/FileNameCoreTests/     unit tests for naming heuristics & sanitizing
Scripts/make-icon.swift      renders the app icon at build time
build.sh                     builds ./build/FileNameChange.app (and the .dmg)
```

No third-party dependencies — just Apple's PDFKit, Vision, NaturalLanguage,
SwiftUI, and (optionally) the FoundationModels framework on macOS 26.
