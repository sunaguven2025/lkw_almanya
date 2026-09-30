import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/truck_profile.dart';

class TruckProfileStorage {
  static const String _key = 'lkw_truck_profile';

  Future<TruckProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) {
      return TruckProfile.defaultProfile;
    }

    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        return TruckProfile.fromJson(map);
      }
    } catch (_) {}

    return TruckProfile.defaultProfile;
  }

  Future<void> save(TruckProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }
}
