# Project workflow (permanent)

These instructions come from the project owner and apply to every session.

- **Never build or test on the phone.** All Flutter, Dart, Gradle, Rust and APK
  verification runs on GitHub Actions, never on the user's device.
- **Use GitHub Actions in small batches.** Push focused changes so a failure
  identifies one batch, not an entire session.
- **Do not wait for CI to finish before continuing.** Keep implementing the
  next approved change while the build runs. If the run fails, inspect the
  failure, fix it, and continue.
- Local work is limited to editing, formatting and static inspection. Do not
  run long local Flutter test or build commands when CI can answer the same
  question.
