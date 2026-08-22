import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_pi_identity/remote_pi_identity.dart';

Uint8List _bytes(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff));

OwnerIdentity _ident({int seed = 0}) =>
    OwnerIdentity(ownerPk: _bytes(seed + 1), ownerSk: _bytes(seed + 2));

/// In-memory stand-in for [FlutterSecureStorage] so the desktop store
/// can be exercised without a platform channel.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.remove(key);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('SecureStorageOwnerIdentityStore', () {
    late _FakeSecureStorage backend;
    late SecureStorageOwnerIdentityStore store;

    setUp(() {
      backend = _FakeSecureStorage();
      store = SecureStorageOwnerIdentityStore(storage: backend);
    });

    test('load returns null on a fresh store', () async {
      expect(await store.load(), isNull);
    });

    test('save → load roundtrips the 64-byte blob', () async {
      final id = _ident();
      await store.save(id);
      expect(await store.load(), equals(id));
    });

    test('persists as standard Base64 (not raw bytes)', () async {
      final id = _ident();
      await store.save(id);
      final raw = await backend.read(key: 'dev.remotepi.owner_identity');
      expect(raw, isNotNull);
      expect(base64Decode(raw!), hasLength(64));
    });

    test('save replaces the previous identity', () async {
      await store.save(_ident(seed: 0));
      final second = _ident(seed: 10);
      await store.save(second);
      expect(await store.load(), equals(second));
    });

    test('delete clears the stored identity', () async {
      await store.save(_ident());
      await store.delete();
      expect(await store.load(), isNull);
    });

    test('isSyncAvailable is always true (local keyring)', () async {
      expect(await store.isSyncAvailable(), isTrue);
    });

    test('watch never emits (no cloud sync on desktop)', () async {
      final emitted = <OwnerIdentity>[];
      final sub = store.watch().listen(emitted.add);
      addTearDown(sub.cancel);
      await store.save(_ident());
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);
    });

    test('load throws PlatformFailure on a corrupt blob', () async {
      await backend.write(
        key: 'dev.remotepi.owner_identity',
        value: 'not-valid-base64!!!',
      );
      expect(store.load(), throwsA(isA<PlatformFailure>()));
    });
  });
}
