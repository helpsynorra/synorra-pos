import 'package:intl/intl.dart';
import '../manila_time.dart';
import '../models/menu_item.dart';
import '../models/order.dart';

class PrinterService {
  static const String cafeName = 'Synorra';
  static const String cafeStreet = 'Veterans Ave, Tetuan';
  static const String cafeCity = 'Zamboanga City';

  // Most 58mm thermal printers use around 32 characters per line.
  static const int receiptWidth = 32;
  static const int cupLabelWidth = receiptWidth;
  static const String _boldOn = '\x1B\x45\x01';
  static const String _boldOff = '\x1B\x45\x00';

  // ---------------------------------------------------------------------------
  // BASIC HELPERS
  // ---------------------------------------------------------------------------

  static String _center(String text, {int width = receiptWidth}) {
    if (text.length >= width) {
      return text.substring(0, width);
    }

    final leftPadding = ((width - text.length) / 2).floor();
    return '${' ' * leftPadding}$text';
  }

  static String _line({int width = receiptWidth, String char = '-'}) {
    return char * width;
  }

  static void _writeLine(
    StringBuffer buffer,
    String text, {
    bool bold = false,
    bool includePrinterCommands = false,
  }) {
    if (bold && includePrinterCommands) buffer.write(_boldOn);
    buffer.write(text);
    if (bold && includePrinterCommands) buffer.write(_boldOff);
    buffer.writeln();
  }

  static String _doubleLine({int width = receiptWidth}) {
    return '=' * width;
  }

  /// Creates a two-column row.
  ///
  /// Example:
  /// Subtotal                 P120.00
  static String _row(
    String left,
    String right, {
    int width = receiptWidth,
  }) {
    left = left.trim();
    right = right.trim();

    if (left.isEmpty) {
      return right.padLeft(width);
    }

    if (right.isEmpty) {
      return left;
    }

    // If the combined content is too long, don't overlap.
    if (left.length + right.length + 1 > width) {
      final availableLeft = width - right.length - 1;

      if (availableLeft <= 0) {
        return right.substring(0, width).padLeft(width);
      }

      left = left.substring(
        0,
        left.length > availableLeft ? availableLeft : left.length,
      );
    }

    final spaces = width - left.length - right.length;

    return '$left${' ' * spaces}$right';
  }

  /// Wraps text without breaking words whenever possible.
  static List<String> _wrap(
    String text, {
    int width = receiptWidth,
  }) {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return [''];
    }

    if (trimmed.length <= width) {
      return [trimmed];
    }

    final words = trimmed.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      // Handle a single word that is longer than the available width.
      if (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }

        for (var i = 0; i < word.length; i += width) {
          final end = (i + width < word.length) ? i + width : word.length;
          lines.add(word.substring(i, end));
        }

        continue;
      }

      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }

    return lines;
  }

  /// Formats currency consistently.
  static String _money(num amount) {
    final currency = NumberFormat('#,##0.00', 'en_PH');
    return 'P${currency.format(amount)}';
  }

  static String _moneyNoSymbol(num amount) {
    final currency = NumberFormat('#,##0.00', 'en_PH');
    return currency.format(amount);
  }

  // ---------------------------------------------------------------------------
  // RECEIPT HEADER
  // ---------------------------------------------------------------------------

  static void _writeHeader(
    StringBuffer buffer,
    Order order,
    bool includePrinterCommands, {
    bool includeBusinessInfo = true,
  }) {
    if (includeBusinessInfo) {
      _writeLine(
        buffer,
        _center(cafeName.toUpperCase()),
        bold: true,
        includePrinterCommands: includePrinterCommands,
      );
      buffer.writeln(_center(cafeStreet));
      buffer.writeln(_center(cafeCity));
      buffer.writeln();
    }
    buffer.writeln(_doubleLine());

    final ticket =
        order.ticketNo.trim().isNotEmpty ? order.ticketNo.trim() : 'N/A';

    _writeLine(
      buffer,
      _row('ORDER NO.', ticket),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    final createdAt = ManilaTime.parse(order.createdAt) ?? ManilaTime.now();

    final dateText = DateFormat('MM/dd/yyyy hh:mm a').format(createdAt);

    buffer.writeln(_row('DATE', dateText));

    final cashier =
        order.baristaName.trim().isNotEmpty ? order.baristaName.trim() : 'N/A';

    buffer.writeln(_row('OWNER', cashier));
    buffer.writeln(_center(order.serviceMode == 'take-out' ? 'TAKE OUT' : 'DINE IN'));

    buffer.writeln(_doubleLine());
  }

  // ---------------------------------------------------------------------------
  // BIR SALES INVOICE
  // ---------------------------------------------------------------------------

  /// Invoice amounts are printed without currency symbol, e.g. `150.00`.
  static String _birAmount(num amount) => amount.toStringAsFixed(2);

  /// Writes wrapped left-aligned lines, matching the admin template layout.
  static void _writeBirLines(StringBuffer buffer, String text) {
    for (final line in _wrap(text)) {
      buffer.writeln(line);
    }
  }

  /// True when the registered tax status is VAT-registered (not NON-VAT).
  static bool _birIsVatRegistered(Map<String, String> details) {
    final taxStatus = (details['taxStatus'] ?? '').toUpperCase();
    if (taxStatus.contains('NON-VAT')) return false;
    return taxStatus.contains('VAT');
  }

  static void _writeBirHeader(
    StringBuffer buffer,
    Order order,
    Map<String, String> details,
    bool includePrinterCommands,
  ) {
    final registeredName = details['registeredBusinessName']?.trim() ?? '';
    final storeName = details['tradeStoreName']?.trim() ?? '';
    final address = details['registeredAddress']?.trim() ?? '';
    final taxStatus = details['taxStatus']?.trim() ?? '';
    final tin = details['tinBranchCode']?.trim() ?? '';

    void writeBold(String text) {
      if (includePrinterCommands) buffer.write(_boldOn);
      _writeBirLines(buffer, text);
      if (includePrinterCommands) buffer.write(_boldOff);
    }

    if (registeredName.isNotEmpty) writeBold(registeredName);
    if (storeName.isNotEmpty && storeName != registeredName) {
      _writeBirLines(buffer, storeName);
    }
    if (address.isNotEmpty) {
      _writeBirLines(buffer, address);
    }
    if (tin.isNotEmpty) {
      _writeBirLines(buffer, 'TIN / BRANCH: $tin');
    }
    if (taxStatus.isNotEmpty) {
      _writeBirLines(buffer, taxStatus);
    }

    buffer.writeln(_doubleLine());
    _writeLine(
      buffer,
      _center('SALES INVOICE'),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    final ticket =
        order.ticketNo.trim().isNotEmpty ? order.ticketNo.trim() : order.id;
    _writeBirLines(buffer, 'Invoice No.: $ticket');
    final createdAt = ManilaTime.parse(order.createdAt) ?? ManilaTime.now();
    _writeBirLines(
      buffer,
      'Date: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(createdAt)}',
    );
  }

  // Column widths for the QTY/ITEM/PRICE/TOTAL invoice table (32 chars total).
  static const int _birPriceWidth = 7;
  static const int _birTotalWidth = 8;
  static const int _birNameWidth =
      receiptWidth - 4 - _birPriceWidth - _birTotalWidth - 2;

  /// One `QTY  ITEM  PRICE  TOTAL` table row using fixed column widths.
  static String _birTableRow(String qty, String name, String price, String total) {
    return '${qty.padRight(4)}${name.padRight(_birNameWidth)} '
        '${price.padLeft(_birPriceWidth)} ${total.padLeft(_birTotalWidth)}';
  }

  static void _writeBirItems(
    StringBuffer buffer,
    Order order,
    bool includePrinterCommands,
  ) {
    buffer.writeln(_line());

    _writeLine(
      buffer,
      _birTableRow('QTY', 'ITEM', 'PRICE', 'TOTAL'),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    buffer.writeln(_line());

    for (final item in order.items) {
      final nameLines = _wrap(item.name.trim(), width: _birNameWidth);
      final unitPrice = _birAmount(item.unitPrice);
      final lineTotal = _birAmount(item.lineTotal);

      for (var i = 0; i < nameLines.length; i++) {
        final chunk = nameLines[i];

        if (i == 0) {
          buffer.writeln(
            _birTableRow('${item.qty}', chunk, unitPrice, lineTotal),
          );
        } else {
          buffer.writeln(_birTableRow('', chunk, '', ''));
        }
      }
    }

    buffer.writeln();
  }

  static void _writeBirTotals(
    StringBuffer buffer,
    Order order,
    Map<String, String> details,
    bool includePrinterCommands,
  ) {
    buffer.writeln(_line());

    // Prices already include VAT, so the 12% VAT is backed out of the total.
    final vatRegistered = _birIsVatRegistered(details);
    final totalDue = order.total;
    final vatable = vatRegistered ? totalDue / 1.12 : 0.0;
    final vat = vatRegistered ? totalDue - vatable : 0.0;
    final vatExempt = vatRegistered ? 0.0 : totalDue;

    buffer.writeln(_row('Vatable Sales', _birAmount(vatable)));
    buffer.writeln(_row('12% VAT', _birAmount(vat)));
    buffer.writeln(_row('VAT-Exempt Sales', _birAmount(vatExempt)));
    buffer.writeln(_row('Zero-Rated Sales', _birAmount(0)));

    buffer.writeln(_line());

    _writeLine(
      buffer,
      _row('TOTAL AMOUNT DUE', _birAmount(totalDue)),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    buffer.writeln();

    final paymentMethod = order.paymentMethod.trim().toUpperCase();
    buffer.writeln(
      _row('Payment', paymentMethod.isEmpty ? 'N/A' : paymentMethod),
    );

    if (order.paymentMethod.toLowerCase() == 'cash') {
      buffer.writeln(_row('Cash Tendered', _birAmount(order.paid)));
      buffer.writeln(_row('Change', _birAmount(order.change)));
    }
  }

  static void _writeBirFooter(
    StringBuffer buffer,
    Map<String, String> details,
  ) {
    buffer.writeln(_doubleLine());

    final footerDetails = <String, String>{
      'MIN': 'min',
      'PTU': 'ptuNumberDate',
      'POS SERIAL': 'posSerialNumber',
      'VENDOR': 'softwareVendorNameTinAddress',
      'BIR ACCREDITATION': 'birAccreditationValidity',
    };

    for (final entry in footerDetails.entries) {
      final value = details[entry.value]?.trim() ?? '';
      if (value.isNotEmpty) {
        _writeBirLines(buffer, '${entry.key}: $value');
      }
    }

    if ((details['taxStatus'] ?? '').toUpperCase().contains('NON-VAT')) {
      _writeBirLines(buffer, 'THIS DOCUMENT IS NOT VALID FOR CLAIM OF INPUT TAX');
    }
  }

  // ---------------------------------------------------------------------------
  // ITEMS
  // ---------------------------------------------------------------------------

  static void _writeItem(
    StringBuffer buffer,
    dynamic item,
    bool includePrinterCommands,
  ) {
    final itemName = item.name.toString().trim();
    final quantity = item.qty;
    final total = item.lineTotal;

    // First line:
    // 2x Iced Spanish Latte
    //
    //                         P180.00
    final itemLines = _wrap(
      '$quantity x $itemName',
      width: receiptWidth - 9,
    );

    for (var i = 0; i < itemLines.length; i++) {
      final text = itemLines[i];

      if (i == 0) {
        _writeLine(
          buffer,
          _row(text, _money(total)),
          bold: true,
          includePrinterCommands: includePrinterCommands,
        );
      } else {
        buffer.writeln('  $text');
      }
    }

    // Drink style / size
    final style = item.style?.toString().trim();
    String? sizeName;
    for (final addon in item.addons) {
      if (addon.id?.startsWith('size:') == true) {
        sizeName = addon.name.toString().trim();
        break;
      }
    }

    if ((style != null && style.isNotEmpty) || (sizeName != null && sizeName.isNotEmpty)) {
      final styleLabel = style == null || style.isEmpty
          ? sizeName!
          : '${style[0].toUpperCase()}${style.substring(1)}${sizeName == null ? '' : ') $sizeName'}';
      final styleLines = _wrap(
        styleLabel,
        width: receiptWidth - 2,
      );

      for (final line in styleLines) {
        buffer.writeln('  $line');
      }
    }

    // Only real add-ons get a plus sign and price. Cup sizes are printed above.
    final regularAddons = item.addons
        .where((addon) => addon.id?.startsWith('size:') != true)
        .toList();
    if (regularAddons.isNotEmpty) {
      for (final addon in regularAddons) {
        final addonName = addon.name.toString().trim();
        final addonQty = addon.qty;

        final addonTotal = addon.price * addon.qty * item.qty;

        final quantityLabel = addonQty > 1 ? '$addonQty x ' : '';
        final priceLabel = addonTotal > 0 ? ' ${_money(addonTotal)}' : '';
        final addonText = 'Add-ons + $quantityLabel$addonName$priceLabel';

        final addonLines = _wrap(
          addonText,
          width: receiptWidth - 2,
        );

        for (var i = 0; i < addonLines.length; i++) {
          final line = addonLines[i];

          buffer.writeln(i == 0 ? '  $line' : '    $line');
        }
      }
    }

    buffer.writeln();
  }

  // ---------------------------------------------------------------------------
  // TOTALS
  // ---------------------------------------------------------------------------

  static void _writeTotals(
    StringBuffer buffer,
    Order order,
    bool includePrinterCommands,
  ) {
    buffer.writeln(_line());

    _writeLine(
      buffer,
      _row('Subtotal', _money(order.subtotal)),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    if (order.discount > 0) {
      buffer.writeln(
        _row(
          'Discount',
          '-${_moneyNoSymbol(order.discount)}',
        ),
      );
    }

    buffer.writeln(_line());

    _writeLine(
      buffer,
      _row('TOTAL', _money(order.total)),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    buffer.writeln(_line());
  }

  // ---------------------------------------------------------------------------
  // PAYMENT
  // ---------------------------------------------------------------------------

  static void _writePayment(
    StringBuffer buffer,
    Order order,
    bool includePrinterCommands,
  ) {
    final paymentMethod = order.paymentMethod.trim().toUpperCase();

    _writeLine(
      buffer,
      _row('PAYMENT', paymentMethod.isEmpty ? 'N/A' : paymentMethod),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    if (order.paymentMethod.toLowerCase() == 'cash') {
      buffer.writeln(
        _row(
          'Cash / Tendered',
          _money(order.paid),
        ),
      );

      buffer.writeln(
        _row(
          'Change',
          _money(order.change),
        ),
      );
    } else {
      buffer.writeln(
        _row(
          'Paid',
          _money(order.paid),
        ),
      );
    }

    buffer.writeln(_line());
  }

  // ---------------------------------------------------------------------------
  // RECEIPT FOOTER
  // ---------------------------------------------------------------------------

  static void _writeFooter(
    StringBuffer buffer,
  ) {
    buffer.writeln();

    buffer.writeln(_center('***'));
  }

  // ---------------------------------------------------------------------------
  // MAIN RECEIPT
  // ---------------------------------------------------------------------------

  /// Generates a clean plain-text thermal receipt.
  static String formatReceipt(
    Order order, {
    bool includePrinterCommands = false,
    bool birCopy = false,
    Map<String, String> birDetails = const {},
  }) {
    final buffer = StringBuffer();

    if (birCopy) {
      _writeBirHeader(buffer, order, birDetails, includePrinterCommands);
      _writeBirItems(buffer, order, includePrinterCommands);
      _writeBirTotals(buffer, order, birDetails, includePrinterCommands);
      _writeBirFooter(buffer, birDetails);

      return buffer.toString().trimRight();
    }

    _writeHeader(
      buffer,
      order,
      includePrinterCommands,
      includeBusinessInfo: false,
    );

    // ITEMS HEADER
    _writeLine(
      buffer,
      _row('ITEM', 'AMOUNT'),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );

    buffer.writeln(_line());

    // ITEMS
    for (final item in order.items) {
      _writeItem(buffer, item, includePrinterCommands);
    }

    // TOTALS
    _writeTotals(buffer, order, includePrinterCommands);

    // PAYMENT
    _writePayment(buffer, order, includePrinterCommands);

    // FOOTER
    _writeFooter(buffer);

    return buffer.toString().trimRight();
  }

  /// Returns the BIR version of the customer receipt with merchant details
  /// that must be filled in for the registered establishment.
  static String formatBirReceipt(
    Order order, {
    bool includePrinterCommands = false,
    Map<String, String> birDetails = const {},
  }) => formatReceipt(
        order,
        includePrinterCommands: includePrinterCommands,
        birCopy: true,
        birDetails: birDetails,
      );

  // ---------------------------------------------------------------------------
  // DRINK CATEGORY
  // ---------------------------------------------------------------------------

  static bool isDrinkCategory(String? category) {
    if (category == null || category.trim().isEmpty) {
      return false;
    }

    final normalized = category.trim().toLowerCase();

    // Food / pastry categories are not drinks.
    if (RegExp(
      r'^\s*(food|pastr)',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return false;
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // CUP LABEL INDEXES
  // ---------------------------------------------------------------------------

  /// Returns the order-item indexes that need cup labels.
  ///
  /// If an order has:
  ///
  /// 2x Iced Latte
  /// 1x Americano
  ///
  /// This returns:
  ///
  /// [0, 0, 1]
  ///
  /// This allows the printer to create one label per drink.
  static List<int> cupLabelItemIndexes(
    Order order,
    List<MenuItem> menu,
  ) {
    final indexes = <int>[];

    for (var itemIndex = 0; itemIndex < order.items.length; itemIndex++) {
      final item = order.items[itemIndex];

      String? category = item.category;

      if (category == null || category.trim().isEmpty) {
        for (final menuItem in menu) {
          if (menuItem.id == item.productId) {
            category = menuItem.category;
            break;
          }
        }
      }

      if (!isDrinkCategory(category)) {
        continue;
      }

      for (var copy = 0; copy < item.qty; copy++) {
        indexes.add(itemIndex);
      }
    }

    return indexes;
  }

  // ---------------------------------------------------------------------------
  // CUP LABEL HELPERS
  // ---------------------------------------------------------------------------

  static String _cupCenter(String text) {
    return _center(
      text,
      width: cupLabelWidth,
    );
  }

  static String _cupLine() {
    return '-' * cupLabelWidth;
  }

  static List<String> _cupWrap(
    String text, {
    int width = cupLabelWidth,
  }) {
    return _wrap(
      text,
      width: width,
    );
  }

  // ---------------------------------------------------------------------------
  // CUP LABEL
  // ---------------------------------------------------------------------------

  /// Formats a single drink cup label.
  static String formatCupLabel(
    Order order,
    int itemIndex,
  ) {
    if (itemIndex < 0 || itemIndex >= order.items.length) {
      return '';
    }

    final item = order.items[itemIndex];

    final buffer = StringBuffer();

    final ticket =
        order.ticketNo.trim().isNotEmpty ? order.ticketNo.trim() : 'N/A';

    buffer.writeln(_cupLine());

    buffer.writeln(
      _row(
        'ORDER #$ticket',
        order.serviceMode == 'take-out' ? 'TAKE OUT' : 'DINE IN',
        width: cupLabelWidth,
      ),
    );

    buffer.writeln(_cupLine());

    // QUANTITY + ITEM
    final rawItemName = item.name.toString().trim();
    final style = item.style?.toString().trim();
    final sizeAddon = item.addons.cast<dynamic?>().firstWhere(
      (addon) => addon?.id?.toString().startsWith('size:') == true,
      orElse: () => null,
    );
    final sizeName = sizeAddon?.name?.toString().trim() ??
        RegExp(r'\(?-?\s*(\d+(?:\.\d+)?\s*oz)\)?', caseSensitive: false)
            .firstMatch(rawItemName)
            ?.group(1)
            ?.replaceAll(RegExp(r'\s+'), '');
    final itemName = rawItemName
        .replaceAll(RegExp(r'\s*\(?-?\s*\d+(?:\.\d+)?\s*oz\)?', caseSensitive: false), '')
        .trim()
        .toUpperCase();
    final drinkName = '${style != null && style.isNotEmpty ? '(${style.toUpperCase()}) ' : ''}'
        '1X $itemName${sizeName != null && sizeName.isNotEmpty ? ' (-$sizeName)' : ''}';

    final itemLines = _cupWrap(
      drinkName,
      width: cupLabelWidth,
    );

    for (final line in itemLines) {
      buffer.writeln(line);
    }

    // ADD-ONS
    final labelAddons = item.addons
        .where((addon) => addon.id?.startsWith('size:') != true)
        .toList();
    if (labelAddons.isNotEmpty) {
      final addonDetails = labelAddons.map((addon) {
        final addonName = addon.name.toString().trim();
        return '+${addon.qty} $addonName';
      }).join(', ');
      final detailLines = _cupWrap(
        addonDetails,
        width: cupLabelWidth,
      );

      for (final line in detailLines) {
        buffer.writeln(line);
      }
    }

    return buffer.toString().trimRight();
  }
}
