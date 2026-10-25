class PrintJob {
  final String id;
  final String orderId;
  final String type; // 
  String status; // 'pending', 'printed', 'failed', 'cancelled'
  final String createdAt;
  String updatedAt;
  String? lastError;

  PrintJob({
    required this.id,
    required this.orderId,
    required this.type,
    this.status = 'pending',
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    return PrintJob(
      id: json['id'] as String? ?? '',
      orderId: json['orderId'] as String? ?? json['order_id'] as String? ?? '',
      type: json['type'] as String? ?? 'internal-slip',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['createdAt'] as String? ?? json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      updatedAt: json['updatedAt'] as String? ?? json['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      lastError: json['lastError'] as String? ?? json['last_error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'orderId': orderId,
    'type': type,
    'status': status,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (lastError != null) 'lastError': lastError,
  };
}
