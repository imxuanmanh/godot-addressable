# Changelog

## Unreleased

- Use Godot .NET 4.6.3 and .NET SDK 8 for the development host; compile the
  existing C# facade from the root project without adding another demo.

- Add a root Godot development project and one log-only Resource-data API example
  using the repository's addon source directly.

- Accept same-major content built with an older minor on newer engine readers.
- Keep validation for newer producers, different majors/platforms and malformed versions.
- Select the test C# SDK from the engine version; add version-admission and
  real older-PCK/newer-reader probes.
- Validate full native/C# suites on 4.6.3 and 4.7.2.

## 0.1.0 — experimental

Initial standalone snapshot. The API and catalog format are not stable yet.

- Lightweight Inspector references and native single/multi-target editors.
- UID-aware catalog generation, dependency/shared-pack builds and export filtering.
- Local/HTTPS PCK delivery, integrity checks and persistent disk cache.
- Typed resource handles, ownership scopes, cancellation and shutdown.
- Optional C# facade, isolated native integration suite and English documentation.
- MIT license and repository-hygiene CI checks.

This entry describes the snapshot; it does not assert that a GitHub release or
version tag has been published.
