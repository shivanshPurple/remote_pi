# Changelog

## 0.2.1

- `SecureStorageOwnerIdentityStore` — desktop persistence via the OS
  keyring (`flutter_secure_storage`). Local-only; does not replace the
  iOS / Android method-channel implementations.

## 0.2.0

### BREAKING

- `OwnerIdentity` no longer carries a `peers` list — the plugin's scope
  is reduced to **Owner-key sync only**. Paired peers, mesh versioning,
  and revocation propagation live in the app/relay layers.
- `PeerEntry` removed from the public API.
- Blob format changed: now a fixed 64-byte buffer (`ownerPk || ownerSk`)
  instead of versioned JSON. Old blobs from 0.1.0 are not migrated —
  this is a pre-release plugin with no production data.

### Notes

- iOS impl (`KeychainSyncStore`) is unchanged — it stores opaque bytes
  and is agnostic to whether the blob is 64 bytes or a longer JSON.
- Android impl (`BlockStoreStore`) is unchanged for the same reason.
- `OwnerIdentityStore` interface (`load` / `save` / `watch` / `delete`
  / `isSyncAvailable`) is unchanged.

## 0.1.0

Initial release — Wave 1 of `plan/23-owner-key-sync.md`.

- `OwnerIdentity` + `PeerEntry` data classes with canonical
  JSON-over-UTF-8 serialization (`toBlob` / `fromBlob`).
- `OwnerIdentityStore` abstract interface with sealed
  `IdentityStoreError` (`SyncUnavailable`, `PlatformFailure`).
- `MethodChannelOwnerIdentityStore` — production impl over
  `remote_pi_identity` method channel + `remote_pi_identity/events`
  event channel.
- `InMemoryOwnerIdentityStore` — fake for tests.
- iOS impl: `kSecClassGenericPassword` with
  `kSecAttrSynchronizable=true` (iCloud Keychain). No Secure Enclave,
  blob-only. Watch combines foreground polling +
  `NSUbiquitousKeyValueStore` change notifications.
- Android impl: Block Store with `setShouldBackupToCloud(true)`. Watch
  polls in foreground (Block Store has no change callback). Requires
  GMS + screen lock + Google account.
- Example app demonstrating load / save / watch / delete /
  `isSyncAvailable` (iOS 26 / Android 14 minimums).
- Unit tests cover `OwnerIdentity`/`PeerEntry` serialization round-trips
  and `InMemoryOwnerIdentityStore` behavior.

### Known limitations

- Android has no live sync between active devices — only
  restore-to-new-device. See `plan/26-android-live-sync.md` (future).
- No cross-ecosystem sync (iOS ↔ Android). See
  `plan/24-key-recovery-export.md` (future).
- No revoke per device. See `plan/25-per-device-identity.md` (future).
