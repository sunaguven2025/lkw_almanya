import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'favorite_place.dart';
import 'favorites_service.dart';

class FavoritesPage extends StatefulWidget {
  final Function(LatLng location) onNavigate;

  const FavoritesPage({
    super.key,
    required this.onNavigate,
  });

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final FavoritesService service = FavoritesService();

  List<FavoritePlace> favorites = <FavoritePlace>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    final List<FavoritePlace> loadedFavorites = await service.getFavorites();

    if (!mounted) {
      return;
    }

    setState(() {
      favorites = loadedFavorites;
      loading = false;
    });
  }

  Future<void> remove(FavoritePlace place) async {
    final bool success = await service.deleteFavorite(place.id);

    if (!mounted) {
      return;
    }

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Favori silinemedi.',
          ),
        ),
      );
      return;
    }

    await load();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${place.name} favorilerden silindi.',
        ),
        duration: const Duration(
          seconds: 2,
        ),
      ),
    );
  }

  Future<void> clearAll() async {
    if (favorites.isEmpty) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            'Favorileri Temizle',
          ),
          content: const Text(
            'Tüm favori konumları silmek istediğinizden emin misiniz?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'İptal',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                'Tümünü Sil',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final bool success = await service.clearFavorites();

    if (!mounted) {
      return;
    }

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Favoriler silinemedi.',
          ),
        ),
      );
      return;
    }

    setState(() {
      favorites = <FavoritePlace>[];
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Tüm favoriler silindi.',
        ),
        duration: Duration(
          seconds: 2,
        ),
      ),
    );
  }

  void navigateToFavorite(FavoritePlace place) {
    Navigator.of(context).pop();

    widget.onNavigate(
      LatLng(
        place.latitude,
        place.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Favori Yerler',
        ),
        actions: <Widget>[
          if (favorites.isNotEmpty)
            IconButton(
              tooltip: 'Tümünü Sil',
              icon: const Icon(
                Icons.delete_sweep,
              ),
              onPressed: clearAll,
            ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : favorites.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                    ),
                    itemCount: favorites.length,
                    itemBuilder: (
                      BuildContext context,
                      int index,
                    ) {
                      final FavoritePlace place = favorites[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.blue.shade50,
                            child: Text(
                              place.icon,
                              style: const TextStyle(
                                fontSize: 26,
                              ),
                            ),
                          ),
                          title: Text(
                            place.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(
                              top: 4,
                            ),
                            child: Text(
                              place.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (String value) {
                              switch (value) {
                                case 'git':
                                  navigateToFavorite(place);
                                  break;

                                case 'sil':
                                  remove(place);
                                  break;
                              }
                            },
                            itemBuilder: (
                              BuildContext context,
                            ) {
                              return const <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'git',
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.navigation,
                                      ),
                                      SizedBox(
                                        width: 8,
                                      ),
                                      Text(
                                        'Navigasyona Git',
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'sil',
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      SizedBox(
                                        width: 8,
                                      ),
                                      Text(
                                        'Sil',
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.bookmark_border,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(
              height: 20,
            ),
            const Text(
              'Henüz favori konum eklenmedi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Navigasyon sırasında bir konumu favorilere '
              'ekleyerek buradan hızlıca ulaşabilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
