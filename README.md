# .NET UI package-size measurements (temporary)

Builds the same tiny app (a stack panel with a button and a text block) with **Uno Platform 7.1.0-dev.36**, **.NET MAUI 10.0.130 / 11.0.10** and **Avalonia 12.1.6**, on **.NET 10.0.404** and **.NET 11.0.100**, and measures the size of what each build ships.

This repository only hosts the targets that need macOS or Linux (iOS, Mac Catalyst, macOS desktop, Linux NativeAOT) on free GitHub-hosted runners. Android, Windows, Linux (non-NativeAOT) and WebAssembly are built elsewhere with the same sources and flags.

- `src/net10`, `src/net11`: the generated apps (unchanged template output plus the shared main page)
- `scripts/mac-run.sh`: iOS / Mac Catalyst / macOS matrix; iOS size is an App Store download estimate (Mach-O raw, everything else deflated)
- `scripts/linux-run.sh`: Linux NativeAOT
- results and logs are uploaded as workflow artifacts

Temporary repository; it will be deleted once the measurements are done.
