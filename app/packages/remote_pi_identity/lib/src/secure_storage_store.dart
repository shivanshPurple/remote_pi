import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'owner_identity.dart';
import 'owner_identity_store.dart';

/// Desktop [OwnerIdentityStore] backed by the OS keyring via
/// `flutter_secure_storage` (libsecret on Linux, Credential Manager on
/// Windows, Keychain on macOS).
///
/// Unlike the iOS / Android implementations this store is **local-only**:
/// there is no iCloud / Google Backup equivalent that we own, so
/// [isSyncAvailable] is always `true` (the keyring is the persistence
/// surface) and [watch] never emits. A new Owner-key on a new desktop
/// install is expected — the user re-pairs via the paste URI.
///
/// The 64-byte blob is stored as standard Base64 so the value stays a
/// plain string on every backend. Mobile still uses
/// [MethodChannelOwnerIdentityStore]; this class must not be wired there
/// or it would silently diverge from iCloud Keychain / Block Store.
class SecureStorageOwnerIdentityStore implements OwnerIdentityStore {
  static const _kKey = 'dev.remotepi.owner_identity';

  final FlutterSecureStorage _storage;

  SecureStorageOwnerIdentityStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<OwnerIdentity?> load() async {
    try {
      final raw = await _storage.read(key: _kKey);
      if (raw == null || raw.isEmpty) return null;
      return OwnerIdentity.fromBlob(Uint8List.fromList(base64Decode(raw)));
    } on FormatException catch (e) {
      throw IdentityStoreError.platform(
        'corrupt_blob',
        'Owner identity blob could not be decoded: $e',
      );
    } catch (e) {
      throw IdentityStoreError.platform('read_failed', e.toString());
    }
  }

  @override
  Future<void> save(OwnerIdentity identity) async {
    try {
      await _storage.write(key: _kKey, value: base64Encode(identity.toBlob()));
    } catch (e) {
      throw IdentityStoreError.platform('write_failed', e.toString());
    }
  }

  @override
  Stream<OwnerIdentity> watch() => const Stream<OwnerIdentity>.empty();

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _kKey);
    } catch (e) {
      throw IdentityStoreError.platform('delete_failed', e.toString());
    }
  }

  /// Desktop has no cloud-sync surface we control. The OS keyring is
  /// always the persistence path, so first-run never gates on
  /// `/sync-required`.
  @override
  Future<bool> isSyncAvailable() async => true;
}
