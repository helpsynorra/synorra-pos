import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.init();
  });

  test('keeps each pending restock delete once until removed', () async {
    await storage.addPendingRestockDelete('restock-1');
    await storage.addPendingRestockDelete('restock-1');
    await storage.addPendingRestockDelete('restock-2');

    expect(storage.getPendingRestockDeletes(), ['restock-1', 'restock-2']);
    expect(storage.getPendingSyncCount(), 2);

    await storage.removePendingRestockDelete('restock-1');

    expect(storage.getPendingRestockDeletes(), ['restock-2']);
    expect(storage.getPendingSyncCount(), 1);
  });
}