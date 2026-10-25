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
    expect(receipt, isNot(contains('have a seat')));
    expect(receipt, isNot(contains('Thank you')));
    expect(receipt, isNot(contains('Please come again')));
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
    expect(lines, isNot(contains('SYNORRA')));
    expect(lines, contains('ORDER #A-011'));
    expect(lines, contains('(ICED) 1X HAZELNUT BLANC'));
    expect(lines, contains('+1 Oat, +1 Coffee Beans'));
    expect(lines, isNot(contains('2X HAZELNUT BLANC')));
    expect(label, isNot(contains('ADD-ONS')));
  });

  test('BIR copy follows the sales invoice template', () {
    final order = Order(
      id: 'ord-3',
      createdAt: '2026-09-30T10:30:00Z',
      baristaName: 'Ari',
      items: [
        OrderItem(
          productId: 'latte',
          name: 'Vanilla Latte',
          qty: 2,
          price: 90,
          addons: [
            OrderAddonSelection(name: 'Oat Milk', qty: 1, price: 15),
          ],
        ),
      ],
      subtotal: 210,
      total: 210,
      paymentMethod: 'cash',
      ticketNo: 'A-013',
      paid: 250,
      change: 40,
    );

    final bir = PrinterService.formatBirReceipt(
      order,
      birDetails: {
        'registeredBusinessName': 'Synorra Coffee Corp.',
        'tradeStoreName': 'Synorra',
        'registeredAddress': 'Veterans Ave, Tetuan, Zamboanga City',
        'tinBranchCode': '123-456-789-000',
        'taxStatus': 'VAT REGISTERED',
        'min': 'MIN-0001',
        'ptuNumberDate': 'PTU-0001 01/01/2026',
        'posSerialNumber': 'SN-0001',
        'softwareVendorNameTinAddress': 'Vendor Inc. 111-222-333',
        'birAccreditationValidity': 'ACC-0001 valid until 2027',
      },
    );

    expect(bir, contains('Synorra Coffee Corp.'));
    expect(bir, contains('TIN / BRANCH: 123-456-789-000'));
    expect(bir, contains('VAT REGISTERED'));
    expect(bir, contains('SALES INVOICE'));
    expect(bir, contains('Invoice No.: A-013'));
    expect(bir, contains('Date: 2026-09-30 18:30:00'));
    expect(bir, contains('QTY'));
    expect(bir, contains('PRICE'));
    expect(bir, contains('TOTAL'));
    expect(bir, contains('Vatable Sales'));
    expect(bir, contains('12% VAT'));
    expect(bir, contains('VAT-Exempt Sales'));
    expect(bir, contains('Zero-Rated Sales'));
    expect(bir, contains('187.50'));
    expect(bir, contains('22.50'));
    expect(bir, contains('TOTAL AMOUNT DUE'));
    expect(bir, contains('Payment'));
    expect(bir, contains('MIN: MIN-0001'));
    expect(bir, contains('PTU: PTU-0001 01/01/2026'));
    expect(bir, contains('BIR ACCREDITATION: ACC-0001'));
    expect(bir, isNot(contains('Thank you')));
    expect(bir, isNot(contains('NOT VALID FOR CLAIM OF INPUT TAX')));
  });

  test('BIR copy for NON-VAT stores prints the exempt notice', () {
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

    final bir = PrinterService.formatBirReceipt(
      order,
      birDetails: {
        'registeredBusinessName': 'Synorra Coffee Corp.',
        'taxStatus': 'NON-VAT',
      },
    );

    expect(bir, contains('Vatable Sales'));
    expect(bir, contains('CLAIM OF INPUT TAX'));
  });
}

