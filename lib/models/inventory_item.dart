class InventoryItem {
  final String id;
  final String name;
  final String category; // Fresh / Packaged / NonFood
  final double originalPrice;
  final DateTime expiryDate;
  final DateTime createdAt;

  final String? photoPath;
  final String? tag;
  final String? description;

  final String? barcode;

  InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.originalPrice,
    required this.expiryDate,
    required this.createdAt,
    this.photoPath,
    this.tag,
    this.description,
    this.barcode,
  });

  InventoryItem copyWith({
    String? id,
    String? name,
    String? category,
    double? originalPrice,
    DateTime? expiryDate,
    DateTime? createdAt,
    String? photoPath,
    String? tag,
    String? description,
    String? barcode,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      originalPrice: originalPrice ?? this.originalPrice,
      expiryDate: expiryDate ?? this.expiryDate,
      createdAt: createdAt ?? this.createdAt,
      photoPath: photoPath ?? this.photoPath,
      tag: tag ?? this.tag,
      description: description ?? this.description,
      barcode: barcode ?? this.barcode,
    );
  }

  // ===== Persistence (JSON) =====

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'originalPrice': originalPrice,
        'expiryDate': expiryDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'photoPath': photoPath,
        'tag': tag,
        'description': description,

        'barcode': barcode,
      };

  static InventoryItem fromJson(Map<String, dynamic> json) {
    final barcodeRaw = json['barcode']?.toString();
    final barcode = (barcodeRaw == null || barcodeRaw.trim().isEmpty) ? null : barcodeRaw.trim();

    return InventoryItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? 'Packaged').toString(),
      originalPrice: _toDouble(json['originalPrice']),
      expiryDate: DateTime.parse(
        (json['expiryDate'] ?? DateTime.now().toIso8601String()).toString(),
      ),
      createdAt: DateTime.parse(
        (json['createdAt'] ?? DateTime.now().toIso8601String()).toString(),
      ),
      photoPath: json['photoPath']?.toString(),
      tag: json['tag']?.toString(),
      description: json['description']?.toString(),

      barcode: barcode,
    );
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
