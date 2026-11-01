import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/models/login_activity.dart';
import 'package:synorra_pos/models/staff_user.dart';
import 'package:synorra_pos/services/local_storage_service.dart';
import 'package:synorra_pos/services/offline_image_cache.dart';
import 'package:synorra_pos/services/offline_credential_store.dart';
import 'package:synorra_pos/services/supabase_service.dart';
import 'package:synorra_pos/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.init();
  });

  test('persists the POS sync cursor between service instances', () async {
    await storage.savePosSyncCursor('184467');

    expect(storage.getPosSyncCursor(), '184467');
  });

  test('clears the cursor when switching store owners', () async {
    StaffUser owner(String id) => StaffUser(
          id: id,
          username: id,
          password: '',
          name: id,
          role: 'cashier',
        );

    await storage.saveActiveStaffSession(owner('owner-1'));
    await storage.savePosSyncCursor('12');
    await storage.saveActiveStaffSession(owner('owner-2'));

    expect(storage.getPosSyncCursor(), isNull);
  });

  test('clears the owner cursor when switching to a non-owner profile',
      () async {
    const owner = StaffUser(
      id: 'owner-1',
      username: 'owner-1',
      password: '',
      name: 'Owner',
      role: 'cashier',
    );
    const manager = StaffUser(
      id: 'manager-1',
      username: 'manager-1',
      password: '',
      name: 'Manager',
      role: 'admin',
    );
    await storage.saveActiveStaffSession(owner);
    await storage.savePosSyncCursor('12');

    await storage.saveActiveStaffSession(manager);

    expect(storage.getPosSyncCursor(), isNull);
  });

  test('clears the cursor when changing the POS API endpoint', () async {
    await storage.savePosSyncCursor('12');

    await storage.setAdminApiUrl('https://pos.example.test/api/sync');

    expect(storage.getPosSyncCursor(), isNull);
  });

  test('preserves avatar paths in locally cached staff records', () async {
    final staff = StaffUser.fromJson({
      'id': 'staff-1',
      'username': 'staff',
      'name': 'Staff',
      'role': 'barista',
      'avatarPath': 'owner-1/staff-1.webp',
    });

    await storage.saveStaff([staff]);

    expect(storage.getStaff().single.avatarPath, 'owner-1/staff-1.webp');
    expect(staff.toJson()['avatarPath'], 'owner-1/staff-1.webp');
  });

  test('keys cached staff avatars by storage path rather than signed URL', () {
    expect(
      OfflineImageCache.staffAvatarCacheKey('owner-1/staff-1.webp'),
      'staff-avatar:owner-1/staff-1.webp',
    );
  });

  test('syncs staff shift punches with staff identity and credentials',
      () async {
    final credentials = _MemoryOfflineCredentialStore();
    storage = LocalStorageService(offlineCredentialStore: credentials);
    await storage.init();
    final punch = LoginActivity(
      id: 'shift-staff-1-login',
      userId: 'staff-1',
      username: 'staff',
      name: 'Staff',
      role: 'barista',
      type: 'login',
      at: '2026-11-01T03:00:00.000Z',
    );
    await storage.addLoginActivity(punch);
    await storage.saveOfflineStaffCredential('staff-1', 'staff-password');

    final api = _RecordingSupabaseService();
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    api.setPosApiToken(
      '${base64Url.encode(utf8.encode('{"exp":$expiry}'))}.signature',
    );
    await storage.savePosSyncCursor('1');
    final sync = SyncService(localStorage: storage, supabaseService: api)
      ..isOnline = true;

    await sync.syncNow();

    expect(api.syncedOperations, hasLength(1));
    expect(api.syncedOperations.single['action'], 'barista_shift_activity');
    expect(api.syncedOperations.single['activity']['userId'], 'staff-1');
    expect(api.syncedOperations.single['credentials'], {
      'username': 'staff',
      'password': 'staff-password',
    });
    expect(storage.getPendingLoginActivity(), isEmpty);

    sync.dispose();
  });

  test(
      'retries staff attendance outside a batch when server rejects the batch action',
      () async {
    final credentials = _MemoryOfflineCredentialStore();
    storage = LocalStorageService(offlineCredentialStore: credentials);
    await storage.init();
    final punch = LoginActivity(
      id: 'shift-staff-2-login',
      userId: 'staff-2',
      username: 'staff-two',
      name: 'Staff Two',
      role: 'barista',
      type: 'login',
      at: '2026-11-01T03:00:00.000Z',
    );
    await storage.addLoginActivity(punch);
    await storage.saveOfflineStaffCredential('staff-2', 'staff-password');

    final api = _RecordingSupabaseService()..rejectStaffShiftBatch = true;
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    api.setPosApiToken(
      '${base64Url.encode(utf8.encode('{"exp":$expiry}'))}.signature',
    );
    await storage.savePosSyncCursor('1');
    final sync = SyncService(localStorage: storage, supabaseService: api)
      ..isOnline = true;

    await sync.syncNow();

    expect(api.directOperations, hasLength(1));
    expect(api.directOperations.single['action'], 'barista_shift_activity');
    expect(api.directOperations.single['activity']['userId'], 'staff-2');
    expect(storage.getPendingLoginActivity(), isEmpty);
    expect(sync.lastError, isNull);

    sync.dispose();
  });

  test('deletes tombstoned rows without replacing pending local rows', () {
    final merged = SyncService.mergeById<Map<String, String>>(
      current: [
        {'id': 'keep', 'value': 'local pending'},
        {'id': 'delete', 'value': 'stale'},
      ],
      updates: [
        {'id': 'keep', 'value': 'remote'},
        {'id': 'add', 'value': 'remote'},
      ],
      idOf: (row) => row['id']!,
      deletedIds: {'delete'},
      preserveIds: {'keep'},
    );

    expect(merged, [
      {'id': 'keep', 'value': 'local pending'},
      {'id': 'add', 'value': 'remote'},
    ]);
  });
}

class _MemoryOfflineCredentialStore implements OfflineCredentialStore {
  final Map<String, String> _credentials = {};

  @override
  Future<void> save({required String staffId, required String password}) async {
    _credentials[staffId] = password;
  }

  @override
  Future<String?> read({required String staffId}) async =>
      _credentials[staffId];

  @override
  Future<void> remove({required String staffId}) async {
    _credentials.remove(staffId);
  }
}

class _RecordingSupabaseService extends SupabaseService {
  final List<Map<String, dynamic>> syncedOperations = [];
  final List<Map<String, dynamic>> directOperations = [];
  bool rejectStaffShiftBatch = false;

  @override
  Future<Map<String, dynamic>> pushSyncBatch(
    List<Map<String, dynamic>> operations,
  ) async {
    syncedOperations.addAll(operations);
    return {
      'ok': true,
      'results': operations.map((operation) {
        if (rejectStaffShiftBatch &&
            operation['action'] == 'barista_shift_activity') {
          return {
            'ok': false,
            'error': 'Unsupported batch operation: barista_shift_activity.',
          };
        }
        return {'ok': true};
      }).toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> pushSyncOperation(
    Map<String, dynamic> operation,
  ) async {
    directOperations.add(operation);
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>?> fetchPosSyncDelta(String cursor) async => {
        'mode': 'delta',
        'cursor': cursor,
        'hasMore': false,
      };
}
