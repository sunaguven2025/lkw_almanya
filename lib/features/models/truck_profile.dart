class TruckProfile {
  final double weight;
  final double height;
  final double width;
  final double length;
  final double axleLoad;

  const TruckProfile({
    required this.weight,
    required this.height,
    required this.width,
    required this.length,
    required this.axleLoad,
  });

  static const TruckProfile defaultProfile = TruckProfile(
    weight: 40.0,
    height: 4.0,
    width: 2.55,
    length: 16.5,
    axleLoad: 11.5,
  );

  Map<String, dynamic> toJson() {
    return {
      'weight': weight,
      'height': height,
      'width': width,
      'length': length,
      'axleLoad': axleLoad,
    };
  }

  factory TruckProfile.fromJson(Map<String, dynamic> json) {
    return TruckProfile(
      weight: (json['weight'] as num?)?.toDouble() ?? 40.0,
      height: (json['height'] as num?)?.toDouble() ?? 4.0,
      width: (json['width'] as num?)?.toDouble() ?? 2.55,
      length: (json['length'] as num?)?.toDouble() ?? 16.5,
      axleLoad: (json['axleLoad'] as num?)?.toDouble() ?? 11.5,
    );
  }
}
