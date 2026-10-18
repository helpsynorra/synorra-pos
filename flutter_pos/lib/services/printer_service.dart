import 'package:intl/intl.dart';
import '../manila_time.dart';
import '../models/menu_item.dart';
import '../models/order.dart';

class PrinterService {
  static const String cafeName = 'Synorra';
  static const String cafeStreet = 'Veterans Ave, Tetuan';
  static const String cafeCity = 'Zamboanga City';
  static const String cafeTagline = 'have a seat, take a sip';

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
    bool includePrinterCommands,
  ) {
    _writeLine(
      buffer,
      _center(cafeName.toUpperCase()),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );
    buffer.writeln(_center(cafeStreet));
    buffer.writeln(_center(cafeCity));
    buffer.writeln(_center(cafeTagline));

    buffer.writeln();
    buffer.writeln(_doubleLine());

    _writeLine(
      buffer,
      _center(''),
      bold: true,
      includePrinterCommands: includePrinterCommands,
    );
    buffer.writeln();

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

    if (style != null && style.isNotEmpty) {
      final styleLines = _wrap(
        '• ${style.toUpperCase()}',
        width: receiptWidth - 2,
      );

      for (final line in styleLines) {
        buffer.writeln('  $line');
      }
    }

    // Add-ons
    if (item.addons.isNotEmpty) {
      for (final addon in item.addons) {
        final addonName = addon.name.toString().trim();
        final addonQty = addon.qty;

        final addonTotal = addon.price * addon.qty * item.qty;

        final addonText = '+ $addonName x$addonQty';

        final addonLines = _wrap(
          addonText,
          width: receiptWidth - 2,
        );

        for (var i = 0; i < addonLines.length; i++) {
          final line = addonLines[i];

          if (i == 0) {
            buffer.writeln(
              _row(
                '  $line',
                _money(addonTotal),
              ),
            );
          } else {
            buffer.writeln('    $line');
          }
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
    buffer.writeln(_center(cafeTagline));
    buffer.writeln();
    buffer.writeln(_center('Thank you!'));
    buffer.writeln(_center('Please come again.'));
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
  }) {
    final buffer = StringBuffer();

    _writeHeader(buffer, order, includePrinterCommands);

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

    // HEADER
    buffer.writeln(
      _cupCenter(cafeName.toUpperCase()),
    );

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
    final itemName = item.name.toString().trim().toUpperCase();
    final style = item.style?.toString().trim();
    final drinkName = style != null && style.isNotEmpty
        ? '(${style.toUpperCase()}) 1X $itemName'
        : '1X $itemName';

    final itemLines = _cupWrap(
      drinkName,
      width: cupLabelWidth,
    );

    for (final line in itemLines) {
      buffer.writeln(line);
    }

    // ADD-ONS
    if (item.addons.isNotEmpty) {
      final addonDetails = item.addons.map((addon) {
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
