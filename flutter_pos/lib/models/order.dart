import 'order_item.dart';

class Order {
  final String id;
  final String createdAt;
  final String baristaName;
  final String? baristaUserId;
  final List<OrderItem> items;
  final double subtotal;
  final double discount;
  final String? promoLabel;
  final int? promoItemIndex;
  final int? promoItemQty;
  final double total;
  final String paymentMethod; // 'cash', 'gcash', 'maya'
  final String serviceMode;
  String ticketNo;
  final double paid;
  final double change;
  bool voided;
  String? voidReason;
  String? voidedBy;
  String? wasteReason;
  bool isSynced;

  bool get isWaste =>
      paymentMethod == 'waste' ||
      id.toLowerCase().startsWith('waste-') ||
      (wasteReason != null && wasteReason!.trim().isNotEmpty);

  Order({
    required this.id,
    required this.createdAt,
    required this.baristaName,
    this.baristaUserId,
    required this.items,
    required this.subtotal,
    this.discount = 0.0,
    this.promoLabel,
    this.promoItemIndex,
    this.promoItemQty,
    required this.total,
    this.paymentMethod = 'cash',
    this.serviceMode = 'dine-in',
    this.ticketNo = '',
    required this.paid,
    this.change = 0.0,
    this.voided = false,
    this.voidReason,
    this.voidedBy,
    this.wasteReason,
    this.isSynced = false,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    List<OrderItem> parsedItems = [];
    if (json['items'] is List) {
      parsedItems = (json['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => OrderItem.fromJson(e))
          .toList();
    }

    return Order(
      id: json['id'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      baristaName: json['baristaName'] as String? ?? json['barista_name'] as String? ?? 'Barista',
      baristaUserId: json['baristaUserId'] as String? ?? json['barista_user_id'] as String?,
      items: parsedItems,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      promoLabel: json['promoLabel'] as String? ?? json['promo_label'] as String?,
      promoItemIndex: (json['promoItemIndex'] as num?)?.toInt() ?? (json['promo_item_index'] as num?)?.toInt(),
      promoItemQty: (json['promoItemQty'] as num?)?.toInt() ?? (json['promo_item_qty'] as num?)?.toInt(),
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['paymentMethod'] as String? ?? json['payment_method'] as String? ?? 'cash',
      serviceMode: json['serviceMode'] as String? ?? json['service_mode'] as String? ?? (parsedItems.isNotEmpty ? parsedItems.first.serviceMode ?? 'dine-in' : 'dine-in'),
      ticketNo: json['ticketNo'] as String? ?? json['ticket_no'] as String? ?? '',
      paid: (json['paid'] as num?)?.toDouble() ?? (json['total'] as num?)?.toDouble() ?? 0.0,
      change: (json['change'] as num?)?.toDouble() ?? 0.0,
      voided: json['voided'] == true,
      voidReason: json['voidReason'] as String? ?? json['void_reason'] as String?,
      voidedBy: json['voidedBy'] as String? ?? json['voided_by'] as String?,
      wasteReason: json['wasteReason'] as String? ??
          json['waste_reason'] as String? ??
          ((json['paymentMethod'] == 'waste' || json['payment_method'] == 'waste' || (json['id'] as String? ?? '').toLowerCase().startsWith('waste-'))
              ? (json['voidReason'] as String? ?? json['void_reason'] as String?)
              : null),
      isSynced: json['isSynced'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt,
    'baristaName': baristaName,
    if (baristaUserId != null) 'baristaUserId': baristaUserId,
    'items': items.map((i) => i.toJson()).toList(),
    'subtotal': subtotal,
    'discount': discount,
    if (promoLabel != null) 'promoLabel': promoLabel,
    if (promoItemIndex != null) 'promoItemIndex': promoItemIndex,
    if (promoItemQty != null) 'promoItemQty': promoItemQty,
    'total': total,
    'paymentMethod': paymentMethod,
    'serviceMode': serviceMode,
    'ticketNo': ticketNo,
    'paid': paid,
    'change': change,
    'voided': voided,
    if (voidReason != null) 'voidReason': voidReason,
    if (voidedBy != null) 'voidedBy': voidedBy,
    if (wasteReason != null) 'wasteReason': wasteReason,
    if (wasteReason != null) 'waste_reason': wasteReason,
    'isSynced': isSynced,
  };
}
