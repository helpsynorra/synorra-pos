// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/models/menu_item.dart';
import 'package:synorra_pos/models/order.dart';
import 'package:synorra_pos/models/order_item.dart';
import 'package:synorra_pos/services/printer_service.dart';

void main() {
  test('cup label category filter excludes food and pastries', () {
    expect(PrinterService.isDrinkCategory('Coffee'), isTrue);
    expect(PrinterService.isDrinkCategory('Food'), isFalse);
    expect(PrinterService.isDrinkCategory('Pastries'), isFalse);
    expect(PrinterService.isDrinkCategory(null), isFalse);
  });

  test('cup label indexes include every drink cup and exclude food', () {
    final order = Order(
      id: 'ord-labels',
      createdAt: '2026-09-30T15:00:00Z',
      baristaName: 'Nina',
      items: [
        OrderItem(
          productId: 'latte',
          name: 'Latte',
          qty: 2,
          price: 120,
          category: 'Drinks',
        ),
        OrderItem(
          productId: 'cake',
          name: 'Cake',
          qty: 1,
          price: 90,
          category: 'Pastries',
        ),
        OrderItem(
          productId: 'tea',
          name: 'Iced Tea',
          qty: 1,
          price: 80,
        ),
      ],
      subtotal: 410,
      total: 410,
      paid: 410,
      ticketNo: 'A-012',
    );
    final menu = [
      const MenuItem(
        id: 'tea',
        name: 'Iced Tea',
        price: 80,
        category: 'Beverages',
        image: '/images/drinks.jpg',
      ),
    ];

    expect(PrinterService.cupLabelItemIndexes(order, menu), [0, 0, 2]);
  });

  test('receipt format matches the compact customer receipt style', () {
    final order = Order(
      id: 'ord-1',
      createdAt: '2026-09-30T10:30:00Z',
      baristaName: 'Ari',
      items: [
        OrderItem(
          productId: 'latte',
          name: 'Vanilla Latte',
          qty: 2,
          price: 90,
          style: 'iced',
          addons: [
            OrderAddonSelection(name: 'Oat Milk', qty: 1, price: 15),
          ],
        ),
      ],
      subtotal: 210,
      discount: 0,
      total: 210,
      paymentMethod: 'cash',
      ticketNo: 'A-010',
      paid: 220,
      change: 10,
    );

    final receipt = PrinterService.formatReceipt(order);

    expect(receipt, contains('Order No. A-010'));
    expect(receipt, contains('have a seat, take a sip'));
    expect(receipt, contains('Vanilla Latte'));
    expect(receipt, contains('Add: Oat Milk x1'));
    expect(receipt, contains('incl P30.00'));
    expect(receipt, contains('TOTAL'));
  });

  test('cup label prints one cup per label with style and add-ons', () {
    final order = Order(
      id: 'ord-2',
      createdAt: '2026-09-30T15:00:00Z',
      baristaName: 'Nina',
      items: [
        OrderItem(
          productId: 'mocha',
          name: 'Hazelnut Blanc',
          qty: 2,
          price: 110,
          style: 'iced',
          addons: [
            OrderAddonSelection(name: 'Oat', qty: 1, price: 10),
            OrderAddonSelection(name: 'Coffee Beans', qty: 1, price: 5),
          ],
        ),
      ],
      subtotal: 110,
      total: 110,
      paid: 110,
      ticketNo: 'A-011',
    );

    final label = PrinterService.formatCupLabel(order, 0);

    final lines = label.split('\n').map((line) => line.trim()).toList();
    expect(lines, contains('SYNORRA'));
    expect(lines, contains('ORDER #A-011'));
    expect(lines, contains('(ICED) 1X HAZELNUT BLANC'));
    expect(lines, contains('+1 Oat, +1 Coffee Beans'));
    expect(lines, isNot(contains('2X HAZELNUT BLANC')));
    expect(label, isNot(contains('ADD-ONS')));
  });
}

