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

  String selectedIcon = "📍";

  final List<String> icons = [
    "🏠",
    "🏢",
    "🚛",
    "⛽",
    "🅿️",
    "🍴",
    "🛏️",
    "📍",
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Konumu Favorilere Kaydet"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.address),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Yer Adı",
                hintText: "Ev, İş, Depo, Müşteri...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: icons.map((icon) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedIcon = icon;
                    });
                  },
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: selectedIcon == icon
                        ? Colors.blue
                        : Colors.grey.shade300,
                    child: Text(
                      icon,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                );
              }).toList(),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text("İptal"),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          child: const Text("Kaydet"),
          onPressed: () {
            Navigator.pop(context, {
              "name": controller.text.trim(),
              "icon": selectedIcon,
            });
          },
        ),
      ],
    );
  }
}
