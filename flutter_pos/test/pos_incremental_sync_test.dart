import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/models/staff_user.dart';
import 'package:synorra_pos/services/local_storage_service.dart';
import 'package:synorra_pos/services/offline_image_cache.dart';
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
