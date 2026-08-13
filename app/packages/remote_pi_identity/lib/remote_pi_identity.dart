/// Owner-key synchronized identity for Remote Pi via platform-native
/// key sync (iCloud Keychain on iOS, Block Store on Android).
///
/// See `package:remote_pi_identity/remote_pi_identity.dart` for the
/// public surface; see README for platform requirements and known
/// limitations.
library;

export 'src/in_memory_store.dart' show InMemoryOwnerIdentityStore;
export 'src/method_channel_store.dart' show MethodChannelOwnerIdentityStore;
export 'src/owner_identity.dart' show OwnerIdentity;
export 'src/owner_identity_store.dart'
    show
        IdentityStoreError,
        OwnerIdentityStore,
        PlatformFailure,
        SyncUnavailable;
export 'src/secure_storage_store.dart' show SecureStorageOwnerIdentityStore;
