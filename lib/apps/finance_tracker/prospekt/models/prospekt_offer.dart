class ProspektOffer {
  final int? id;
  final String market;
  final String title;
  final double priceEur;
  final String quantity;
  final DateTime? createdAt;
  final int? csvImportId;

  const ProspektOffer({
    this.id,
    required this.market,
    required this.title,
    required this.priceEur,
    required this.quantity,
    this.createdAt,
    this.csvImportId,
  });

  ProspektOffer copyWith({
    int? id,
    String? market,
    String? title,
    double? priceEur,
    String? quantity,
    DateTime? createdAt,
    int? csvImportId,
  }) {
    return ProspektOffer(
      id: id ?? this.id,
      market: market ?? this.market,
      title: title ?? this.title,
      priceEur: priceEur ?? this.priceEur,
      quantity: quantity ?? this.quantity,
      createdAt: createdAt ?? this.createdAt,
      csvImportId: csvImportId ?? this.csvImportId,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'id': id,
      'market': market,
      'title': title,
      'price_eur': priceEur,
      'quantity': quantity,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'csv_import_id': csvImportId,
    };
  }

  static ProspektOffer fromDb(Map<String, Object?> row) {
    final created = row['created_at'];
    DateTime? createdAt;
    if (created is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(created);
    }

    return ProspektOffer(
      id: row['id'] as int?,
      market: (row['market'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      priceEur: _asDouble(row['price_eur']),
      quantity: (row['quantity'] as String?) ?? '',
      createdAt: createdAt,
      csvImportId: row['csv_import_id'] as int?,
    );
  }

  static double _asDouble(Object? v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
    }
}