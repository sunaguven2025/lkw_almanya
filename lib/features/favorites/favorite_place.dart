class FavoritePlace {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String icon;
  final DateTime createdAt;

  FavoritePlace({
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
      "id": id,
      "name": name,
      "address": address,
      "latitude": latitude,
      "longitude": longitude,
      "icon": icon,
      "createdAt": createdAt.toIso8601String(),
    };
  }

  factory FavoritePlace.fromMap(Map<String, dynamic> map) {
    return FavoritePlace(
      id: map["id"],
      name: map["name"],
      address: map["address"],
      latitude: map["latitude"],
      longitude: map["longitude"],
      icon: map["icon"],
      createdAt: DateTime.parse(map["createdAt"]),
    );
  }
}
