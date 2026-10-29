import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists category types for POS-created menu categories', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();

    await storage.saveCategoryTypes({
      'Coffee': 'Drinks',
      '  Dessert  ': '  Desserts ',
      'Seasonal': '  Limited Edition ',
      'Unclassified': '',
    });

    expect(storage.getCategoryTypes(), {
      'Coffee': 'Drinks',
      'Dessert': 'Desserts',
      'Seasonal': 'Limited Edition',
    });
  });
}
