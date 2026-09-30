class RouteRestriction {
  final String id;
  final double latitude;
  final double longitude;
  final String type; // 'height', 'weight', 'width', 'hazmat'
  final double? value; // max value (meters, tons)
  final String description;
  final bool isCritical; // true = kamyona engel, false = uyarı

  const RouteRestriction({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.value,
    required this.description,
    this.isCritical = false,
  });

  factory RouteRestriction.fromJson(Map<String, dynamic> json) {
    return RouteRestriction(
      id: json['id']?.toString() ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      type: json['type']?.toString() ?? 'unknown',
      value: (json['value'] as num?)?.toDouble(),
      description: json['description']?.toString() ?? '',
      isCritical: json['isCritical'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'type': type,
        'value': value,
        'description': description,
        'isCritical': isCritical,
      };
}
