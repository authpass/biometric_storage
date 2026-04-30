# biometric_storage

Federated Flutter plugin repository for `biometric_storage`.

## Layout

- `biometric_storage/` — app-facing package, including the example app
- `biometric_storage_platform_interface/` — shared platform contract and types
- `biometric_storage_android/` — Android implementation
- `biometric_storage_darwin/` — iOS/macOS implementation
- `biometric_storage_linux/` — Linux implementation
- `biometric_storage_web/` — Web implementation
- `biometric_storage_windows/` — Windows implementation

The package you would publish/use directly is in `biometric_storage/`.

For package-specific usage and platform notes, see `biometric_storage/README.md`.
