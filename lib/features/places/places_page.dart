import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/saved_place.dart';
import '../../services/saved_places_service.dart';
import '../../theme/app_theme.dart';

class PlacesPage extends StatefulWidget {
  final void Function(LatLng point)? onPlaceSelected;

  const PlacesPage({
    super.key,
    this.onPlaceSelected,
  });

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  final SavedPlacesService _service = SavedPlacesService();

  List<SavedPlace> _places = <SavedPlace>[];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    final List<SavedPlace> places = await _service.getPlaces();

    if (!mounted) {
      return;
    }

    setState(() {
      _places = places;
      _isLoading = false;
    });
  }

  Future<void> _deletePlace(
    SavedPlace place,
  ) async {
    await _service.deletePlace(
      place.id,
    );

    await _loadPlaces();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${place.name} silindi.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    SavedPlace place,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            'Yeri Sil',
          ),
          content: Text(
            '${place.name} kaydını silmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Vazgeç',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Sil',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deletePlace(
        place,
      );
    }
  }

  void _selectPlace(
    SavedPlace place,
  ) {
    if (widget.onPlaceSelected != null) {
      widget.onPlaceSelected!(
        LatLng(
          place.latitude,
          place.longitude,
        ),
      );

      Navigator.pop(
        context,
      );

      return;
    }
  }

  IconData _getPlaceIcon(
    String name,
  ) {
    final String lowerName = name.toLowerCase();

    if (lowerName == 'ev') {
      return Icons.home;
    }

    if (lowerName == 'iş' || lowerName == 'is') {
      return Icons.work;
    }

    if (lowerName.contains('depo')) {
      return Icons.warehouse;
    }

    if (lowerName.contains('müşteri') || lowerName.contains('musteri')) {
      return Icons.person_pin_circle;
    }

    return Icons.location_on;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Yerler ve Favoriler',
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _places.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadPlaces,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(
                      16,
                    ),
                    itemCount: _places.length,
                    separatorBuilder: (
                      BuildContext context,
                      int index,
                    ) {
                      return const SizedBox(
                        height: 10,
                      );
                    },
                    itemBuilder: (
                      BuildContext context,
                      int index,
                    ) {
                      final SavedPlace place = _places[index];

                      return _buildPlaceCard(
                        place,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          30,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(
              height: 20,
            ),
            const Text(
              'Henüz kayıtlı yer yok.',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              'Bulunduğunuz konumu veya haritada seçtiğiniz '
              'bir yeri favorilerinize ekleyebilirsiniz.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceCard(
    SavedPlace place,
  ) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryBlue,
          child: Icon(
            _getPlaceIcon(
              place.name,
            ),
            color: Colors.white,
          ),
        ),
        title: Text(
          place.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(
            top: 5,
          ),
          child: Text(
            place.address.isEmpty
                ? '${place.latitude.toStringAsFixed(5)}, '
                    '${place.longitude.toStringAsFixed(5)}'
                : place.address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (String value) {
            if (value == 'go') {
              _selectPlace(
                place,
              );
            }

            if (value == 'delete') {
              _confirmDelete(
                place,
              );
            }
          },
          itemBuilder: (
            BuildContext context,
          ) {
            return const [
              PopupMenuItem<String>(
                value: 'go',
                child: ListTile(
                  leading: Icon(
                    Icons.navigation,
                  ),
                  title: Text(
                    'Buraya Git',
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(
                    Icons.delete,
                  ),
                  title: Text(
                    'Sil',
                  ),
                ),
              ),
            ];
          },
        ),
        onTap: () {
          _selectPlace(
            place,
          );
        },
      ),
    );
  }
}
