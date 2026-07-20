class AnalyticsEvent {
  final String eventType;
  final String screen;
  final String? categoryName;
  final String? productName;
  final String? productId;
  final Map<String, dynamic>? metadata;

  const AnalyticsEvent({
    required this.eventType,
    required this.screen,
    this.categoryName,
    this.productName,
    this.productId,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'screen': screen,
      if (categoryName != null) 'category_name': categoryName,
      if (productName != null) 'product_name': productName,
      if (productId != null) 'product_id': productId,
      if (metadata != null) 'metadata': metadata,
    };
  }
}
