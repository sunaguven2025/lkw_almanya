import 'package:flutter/material.dart';

class LocationDialog extends StatefulWidget {
  final String address;

  const LocationDialog({
    super.key,
    required this.address,
  });

  @override
  State<LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<LocationDialog> {
  final TextEditingController controller = TextEditingController();

  String selectedIcon = '🏠';

  final List<String> icons = <String>[
    '🏠',
    '🏢',
    '🚚',
    '⛽',
    '🏪',
    '🏭',
    '🛣️',
    '📍',
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _save() {
    final String name = controller.text.trim();

    Navigator.pop(
      context,
      <String, String>{
        'name': name.isEmpty ? 'Favori Konum' : name,
        'icon': selectedIcon,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Konumu Favorilere Kaydet',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.address,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Yer Adı',
                hintText: 'Ev, İş, Depo, Müşteri...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            const Text(
              'Simge seçin',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: icons.map(
                (String icon) {
                  final bool selected = selectedIcon == icon;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedIcon = icon;
                      });
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          selected ? Colors.blue : Colors.grey.shade300,
                      child: Text(
                        icon,
                        style: const TextStyle(
                          fontSize: 23,
                        ),
                      ),
                    ),
                  );
                },
              ).toList(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text(
            'İptal',
          ),
        ),
        ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(
            Icons.bookmark_add,
          ),
          label: const Text(
            'Kaydet',
          ),
        ),
      ],
    );
  }
}
