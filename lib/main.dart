import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'config/env.dart';
import 'features/home/home_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env dosyasını güvenli şekilde yükle
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('⚠️ .env dosyası yüklenemedi: $e');
  }

  // Geliştirme aşamasında anahtarların yüklendiğini doğrula
  // (Release modda hiçbir şey yazmaz)
  Env.printStatus();

  runApp(const LkwAlmanyaApp());
}

class LkwAlmanyaApp extends StatelessWidget {
  const LkwAlmanyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LKW Almanya Navigasyon',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
