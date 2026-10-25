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

  test('slip format matches the compact order slip style', () {
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

    final slip = PrinterService.formatslip(order);
    final normalized = slip.replaceAll(RegExp(r'\s+'), ' ');

    final compact = normalized.toUpperCase();
    expect(compact, contains('CUSTOMER COPY (FOR INTERNAL USE ONLY)'));
    expect(compact, contains('ORDER # A-010'));
    expect(slip, isNot(contains('have a seat')));
    expect(slip, isNot(contains('Thank you')));
    expect(slip, isNot(contains('Please come again')));
    expect(slip, contains('Vanilla Latte'));
    expect(compact, contains('ADD-ONS + OAT MILK P30.00'));
    expect(slip, contains('TOTAL'));
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
    expect(lines, isNot(contains('SYNORRA')));
    expect(lines.any((line) => line.startsWith('ORDER #A-011')), isTrue);
    expect(lines, contains('(ICED) 1X HAZELNUT BLANC'));
    expect(lines, contains('+1 Oat, +1 Coffee Beans'));
    expect(lines, isNot(contains('2X HAZELNUT BLANC')));
    expect(label, isNot(contains('ADD-ONS')));
  });

  test('Order receipt is an INTERNAL COPY without tax fields', () {
    final order = Order(
      id: 'ord-4',
      createdAt: '2026-09-30T10:30:00Z',
      baristaName: 'Ari',
      items: [
        OrderItem(productId: 'tea', name: 'Iced Tea', qty: 1, price: 80),
      ],
      subtotal: 80,
      total: 80,
      paymentMethod: 'cash',
      ticketNo: 'A-014',
      paid: 80,
    );

    final slip = PrinterService.formatslip(order);
    final normalized = slip.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

    expect(normalized, contains('CUSTOMER COPY (FOR INTERNAL USE ONLY)'));
    expect(normalized, contains('ORDER #'));
    expect(
        normalized,
        contains(
            'THIS DOCUMENT IS NOT VALID FOR CLAIM OF INPUT TAX / FOR INTERNAL STORE USE ONLY'));
    expect(normalized, isNot(contains('VATABLE SALES')));
    expect(normalized, isNot(contains('12% VAT')));
    expect(normalized, isNot(contains('VAT-EXEMPT')));
    expect(normalized, isNot(contains('TIN')));
    expect(normalized, isNot(contains('PTU')));
    expect(normalized, isNot(contains('SALES INVOICE')));
    expect(normalized, isNot(contains('OFFICIAL slip')));
  });
}
