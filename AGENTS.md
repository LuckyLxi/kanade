# Repository Guidelines

## Project Structure & Module Organization

Kanade is a Flutter + Rust QQ Music client for Windows and Android. Flutter handles UI and playback; Rust handles networking, authentication, and caching.

- `lib/`: Dart code grouped into `ui/`, `player/`, `auth/`, `library/`, `settings/`, and `data/`; localization lives in `l10n/`.
- `rust/src/api/`: interfaces exposed through flutter_rust_bridge; `rust/src/qq/`: implementation.
- `lib/src/rust/` and `rust/src/frb_generated.rs`: generated bindings; `rust_builder/`: native build integration.
- `test/`, `integration_test/`, and `rust/tests/`: Flutter unit/widget tests, device tests, and Rust live API tests.
- `shaders/`: player shader assets; `docs/`: API references and capture notes; `scripts/`: capture utilities.
- `third_party/`: patched local dependencies; preserve their patches.

## Build, Test, and Development Commands

Run from the root unless specified:

- `flutter pub get`: install Dart dependencies.
- `flutter run -d windows`: launch locally; Rust builds automatically through cargokit.
- `flutter build windows` / `flutter build apk`: build desktop or Android releases.
- `flutter analyze`: analyze using `analysis_options.yaml` and `flutter_lints`.
- `flutter test test/audio_source_test.dart`: run a focused test.
- `flutter test integration_test/simple_test.dart -d windows`: run an integration test.
- `cargo test --manifest-path rust/Cargo.toml --lib`: run Rust unit tests.
- `flutter_rust_bridge_codegen generate`: regenerate bindings after API changes; use codegen version **2.12.0**.
- `flutter gen-l10n`: regenerate localization after editing ARB files.

## Capture Scripts

- `node scripts/capture-qqmusic-fiddler.mjs --capture --recommendations`: temporarily route official QQ Music traffic through Fiddler; use `--player` or `--search` for those workflows. Requires Node.js, FlClash's controller on port 9090, and Fiddler on port 8888. Use `--check` for preparation checks; `--restore` restores routing from FlClash's configuration.
- `node scripts/capture-qqmusic-android.mjs --prepare`: route official Android QQ Music in MuMu 15 (device 0, root enabled, adb `127.0.0.1:16384`) through Fiddler on port 8888, for features missing from the PC client. Injects Fiddler's CA into the conscrypt store until the emulator restarts and blocks UDP 443. `--check` is read-only; `--restore` clears the proxy and the block.
- `scripts/capture-qqmusic.ps1`: run in administrator PowerShell with QQ Music open. Records 30 seconds of local network traffic using PktMon, producing ETL, PCAPNG, and socket logs. Keep captures local.

## Coding Style & Naming Conventions

Use two-space Dart indentation and standard Rust formatting (`cargo fmt --manifest-path rust/Cargo.toml`). Use `snake_case` filenames, `UpperCamelCase` types, Dart `lowerCamelCase` members, and Rust `snake_case` functions. Format changed Dart code with `dart format`. Edit binding sources rather than generated output.

## Testing Guidelines

Use `flutter_test`, `integration_test`, and Rust's built-in tests. Name Dart tests `*_test.dart`. No coverage threshold is configured. Always run static checks; select tests by risk, skipping tests for simple, low-risk edits. Avoid unnecessary full-suite runs. Report verification limits honestly.

Live tests are opt-in: from `rust/`, run `cargo test --test live -- --ignored --nocapture --test-threads=1`. Desktop cases require `QQMUSIC_TEST_HAR` pointing to a local authenticated HAR. Never commit credentials or captures.

## Commit & Pull Request Guidelines

Follow existing prefixes: `feat:`, `fix:`, `refactor:`, and `docs:` with imperative descriptions. PRs should explain changes, link issues, list validation results, and include screenshots for authorized visual changes.

## Change Scope

Make minimal necessary changes and reuse existing code. Avoid unrelated refactoring, excessive defensive logic, and unnecessary abstractions or fallbacks. Obtain explicit agreement before changing existing UI, interactions, or animations. Fix introduced problems without suppressing errors, weakening checks, or deleting valid tests.
