import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../models/truck_profile.dart';

class TruckProfileSheet extends StatefulWidget {
  final TruckProfile profile;
  final ValueChanged<TruckProfile> onSaved;

  const TruckProfileSheet({
    super.key,
    required this.profile,
    required this.onSaved,
  });

  @override
  State<TruckProfileSheet> createState() => _TruckProfileSheetState();
}

class _TruckProfileSheetState extends State<TruckProfileSheet> {
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _widthController;
  late final TextEditingController _lengthController;
  late final TextEditingController _axleController;

  @override
  void initState() {
    super.initState();
    _weightController =
        TextEditingController(text: widget.profile.weight.toStringAsFixed(1));
    _heightController =
        TextEditingController(text: widget.profile.height.toStringAsFixed(1));
    _widthController =
        TextEditingController(text: widget.profile.width.toStringAsFixed(2));
    _lengthController =
        TextEditingController(text: widget.profile.length.toStringAsFixed(1));
    _axleController =
        TextEditingController(text: widget.profile.axleLoad.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _widthController.dispose();
    _lengthController.dispose();
    _axleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.local_shipping, color: AppTheme.primaryBlue),
                  SizedBox(width: 8),
                  Text(
                    'Kamyon Profili',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _inputRow('Ağırlık (t)', _weightController),
              _inputRow('Yükseklik (m)', _heightController),
              _inputRow('Genişlik (m)', _widthController),
              _inputRow('Uzunluk (m)', _lengthController),
              _inputRow('Aks yükü (t)', _axleController),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final profile = TruckProfile(
                      weight: double.tryParse(_weightController.text) ?? 40.0,
                      height: double.tryParse(_heightController.text) ?? 4.0,
                      width: double.tryParse(_widthController.text) ?? 2.55,
                      length: double.tryParse(_lengthController.text) ?? 16.5,
                      axleLoad: double.tryParse(_axleController.text) ?? 11.5,
                    );

                    widget.onSaved(profile);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputRow(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
