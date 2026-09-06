class FavoritePlace {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String icon;
  final DateTime createdAt;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.icon,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'icon': icon,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory FavoritePlace.fromMap(Map<String, dynamic> map) {
    return FavoritePlace(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      latitude: _toDouble(map['latitude']),
      longitude: _toDouble(map['longitude']),
      icon: map['icon']?.toString() ?? '📍',
      createdAt: _toDateTime(map['createdAt']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0.0;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    final String text = value?.toString() ?? '';

    return DateTime.tryParse(text) ?? DateTime.now();
  }
}
