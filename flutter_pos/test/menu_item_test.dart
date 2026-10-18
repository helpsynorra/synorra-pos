import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/models/menu_item.dart';

void main() {
  test('does not add styles when none are configured', () {
    final item = MenuItem.fromJson({
      'id': 'plain-drink',
      'name': 'Plain Drink',
      'category': 'Coffee',
      'image': '/images/drink.jpg',
    });

    expect(item.styles, isEmpty);
  });

  test('an explicit empty style list overrides legacy image options', () {
    final item = MenuItem.fromJson({
      'id': 'plain-drink',
      'name': 'Plain Drink',
      'category': 'Coffee',
      'image': '/images/drink.jpg#styles=hot,iced',
      'styles': <String>[],
    });

    expect(item.styles, isEmpty);
  });

  test('keeps explicitly configured styles', () {
    final item = MenuItem.fromJson({
      'id': 'iced-drink',
      'name': 'Iced Drink',
      'category': 'Coffee',
      'image': '/images/drink.jpg',
      'styles': ['iced'],
    });

    expect(item.styles, ['iced']);
  });
}