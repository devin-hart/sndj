---
title: LLM Wiki Schema & Maintenance Protocol
category: meta
updated: 2026-11-01
---

# LLM Wiki Schema (`sndj`)

This directory implements Andrej Karpathy's **LLM Wiki** pattern for the **sndj** codebase (an LSDJ-inspired music tracker for the Super Nintendo / Super Famicom written in 65816 + SPC700 assembly, Python build/test tools, Lua emulator checks, and a zero-dependency browser ecosystem).

Instead of re-deriving architectural constraints, register clobber rules, memory boundaries, and cross-file dependencies from raw assembly on every prompt, **this wiki is a persistent, compounding artifact maintained by LLM agents.**

---

## 1. Three-Layer Architecture

1. **Raw Sources (Immutable Source of Truth during queries)**
   - Assembly sources (`src/*.asm`, `src/*.inc`, `src/apu/driver.asm`)
   - Build & test toolchain (`Makefile`, `tools/*.py`, `tools/*.js`, `tools/*.lua`, `tools/checks/*.lua`, `tools/commands.csv`)
   - Browser ecosystem (`user-tools/sndj.js`, `user-tools/*.html`, `factory/factory.sndjfact`)
   - Root contracts (`CLAUDE.md`, `SAVEFORMAT.md`, `HARDWARE.md`, `MANUAL.md`, `PALETTE.md`, `ALS.md`, `LINK-SYNC-WIRING.md`, `HARDWARE-TEST-CHECKLIST.md`, `RELEASING.md`, `THIRD_PARTY.md`)
2. **The Wiki (`wiki/*.md`)**
   - Owned and maintained by the LLM agent. Contains synthesized architectural maps, file-by-file functional catalogs, register/scratch ownership tables, cross-file synchronization matrices, modification playbooks, and known codebase contradictions/drift.
3. **The Schema (`wiki/SCHEMA.md`)**
   - This file. Defines the conventions and workflows (`Ingest`, `Query`, `Lint`) that every LLM agent must follow when reading or modifying `sndj` and this wiki.

---

## 2. Navigation & Conventions

- **Start at [`index.md`](index.md)**: Always read `wiki/index.md` first to locate the relevant concept, subsystem, or file reference page before grepping or reading raw assembly files.
- **Check [`log.md`](log.md)**: Check the tail of `wiki/log.md` (`grep "^## \[" wiki/log.md | tail -5`) to see recent code changes, ingests, and lint passes.
- **YAML Frontmatter**: Every wiki page begins with YAML frontmatter (`title`, `category`, `updated`, `sources`) so tools and Obsidian Dataview can query it.
- **Cross-References**: Use standard Markdown links (`[page.md](page.md)`) and Obsidian-compatible links so the knowledge graph stays connected.
- **Explicit Hex & Bank Notation**: Always write 65816 addresses with explicit bank prefixes where relevant (`$80:8000` FastROM, `$7E:2000` WRAM Song Block, `$70:0000` SRAM, `$0000–$03FF` low WRAM) and distinguish S-CPU addresses from 16-bit ARAM (`$0000–$FFFF`) and S-DSP register addresses (`$00–$7F`).

---

## 3. Core Operations

### Operation A: Query (Answering Questions or Planning Code Changes)
1. Read [`index.md`](index.md) to identify the relevant wiki pages.
2. Read [`memory-and-hardware.md`](memory-and-hardware.md) and [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md) before planning any edit to `src/`, `tools/`, or `user-tools/`.
3. Drill into the specific file reference pages ([`files-scpu-core.md`](files-scpu-core.md), [`files-scpu-engine.md`](files-scpu-engine.md), [`files-scpu-screens.md`](files-scpu-screens.md), [`files-toolchain-and-tests.md`](files-toolchain-and-tests.md), [`files-browser-ecosystem.md`](files-browser-ecosystem.md)).
4. Verify exact line numbers against raw source files as needed. If your exploration uncovers a non-obvious interaction, file it back into the wiki.

### Operation B: Ingest (Updating the Wiki After Code Changes or New Sources)
Whenever you make a code change to `sndj` or ingest new hardware/design notes:
1. Update the affected file reference page(s) (`files-*.md`) if routines, WRAM variables, or behaviors changed.
2. Update [`memory-and-hardware.md`](memory-and-hardware.md) if any WRAM variables (`.ENUM $0C00`), Song Block offsets (`song.inc`), ROM bank allocations, or scratch conventions changed.
3. Update [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md) if cross-file synchronization points or drift items were added or resolved.
4. Update [`index.md`](index.md) if pages were added or summaries changed.
5. Append a timestamped entry to [`log.md`](log.md) using the strict prefix format:
   `## [YYYY-MM-DD] ingest | <Short Summary of Change>`

### Operation C: Lint (Periodic Health & Parity Check)
When asked to lint the wiki (or after a milestone):
1. Compare [`memory-and-hardware.md`](memory-and-hardware.md) against `src/ram.inc`, `src/song.inc`, and `src/main.asm`.
2. Check the **Active Drift & Contradictions** section of [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md) to verify whether any console-vs-JS or doc-vs-code discrepancies have been fixed or introduced.
3. Verify that every file in `src/`, `tools/`, and `user-tools/` is documented in the `files-*.md` pages and linked from [`index.md`](index.md).
4. Append a `## [YYYY-MM-DD] lint | <Summary>` entry to [`log.md`](log.md).
