import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/truck_profile.dart';

class TruckProfileStorage {
  static const String _storageKey = 'lkw_truck_profile';

  Future<TruckProfile> load() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final String? rawData = preferences.getString(_storageKey);

    if (rawData == null || rawData.isEmpty) {
      return TruckProfile.defaultProfile;
    }

    try {
      final dynamic decodedData = jsonDecode(rawData);

      if (decodedData is Map<String, dynamic>) {
        return TruckProfile.fromJson(decodedData);
      }

      return TruckProfile.defaultProfile;
    } catch (e) {
      return TruckProfile.defaultProfile;
    }
  }

  Future<void> save(TruckProfile profile) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _storageKey,
      jsonEncode(profile.toJson()),
    );
  }
}
