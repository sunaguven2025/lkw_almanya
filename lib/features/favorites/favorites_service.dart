import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'favorite_place.dart';

class FavoritesService {
  static const String storageKey = 'favorite_places';

  Future<List<FavoritePlace>> getFavorites() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? data = prefs.getString(storageKey);

    if (data == null || data.trim().isEmpty) {
      return <FavoritePlace>[];
    }

    try {
      final dynamic decoded = jsonDecode(data);

      if (decoded is! List) {
        return <FavoritePlace>[];
      }

      final List<FavoritePlace> favorites = <FavoritePlace>[];

      for (final dynamic item in decoded) {
        if (item is! Map) {
          continue;
        }

        try {
          final FavoritePlace place = FavoritePlace.fromMap(
            Map<String, dynamic>.from(item),
          );

          if (place.id.isNotEmpty) {
            favorites.add(place);
          }
        } catch (e) {
          // Bozuk tek bir kayıt bütün favori listesini bozmasın.
        }
      }

      return favorites;
    } catch (e) {
      return <FavoritePlace>[];
    }
  }

  Future<bool> saveFavorites(
    List<FavoritePlace> favorites,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    try {
      final String data = jsonEncode(
        favorites
            .map(
              (FavoritePlace place) => place.toMap(),
            )
            .toList(),
      );

      return await prefs.setString(
        storageKey,
        data,
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> addFavorite(
    FavoritePlace place,
  ) async {
    final List<FavoritePlace> favorites = await getFavorites();

    favorites.removeWhere(
      (FavoritePlace item) => item.id == place.id,
    );

    favorites.insert(
      0,
      place,
    );

    return saveFavorites(
      favorites,
    );
  }

  Future<bool> deleteFavorite(
    String id,
  ) async {
    final List<FavoritePlace> favorites = await getFavorites();

    favorites.removeWhere(
      (FavoritePlace item) => item.id == id,
    );

    return saveFavorites(
      favorites,
    );
  }

  Future<bool> clearFavorites() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.remove(
      storageKey,
    );
  }

  Future<bool> isFavorite(
    String id,
  ) async {
    final List<FavoritePlace> favorites = await getFavorites();

    return favorites.any(
      (FavoritePlace place) => place.id == id,
    );
  }
}
