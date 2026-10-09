import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Uygulama ortam değişkenlerine merkezi erişim noktası.
///
/// Öncelik sırası:
///   1. --dart-define ile verilen değer (üretim/CI-CD için önerilen)
///   2. .env dosyasındaki değer (geliştirme için pratik)
///
/// Kullanım:
///   final key = Env.tomtomApiKey;
class Env {
  Env._(); // Nesne oluşturulmasın

  // ============================================================
  // TOMTOM API
  // ============================================================
  static String get tomtomApiKey {
    const fromDefine = String.fromEnvironment('TOMTOM_API_KEY');
    if (fromDefine.isNotEmpty) return fromDefine;
    return dotenv.env['TOMTOM_API_KEY'] ?? '';
  }

  static bool get hasTomTomKey => tomtomApiKey.isNotEmpty;

  // ============================================================
  // ORS API (eski servis için — yedek olarak tutuyoruz)
  // ============================================================
  static String get orsApiKey {
    const fromDefine = String.fromEnvironment('ORS_API_KEY');
    if (fromDefine.isNotEmpty) return fromDefine;
    return dotenv.env['ORS_API_KEY'] ?? '';
  }

  static bool get hasOrsKey => orsApiKey.isNotEmpty;

  // ============================================================
  // DEBUG YARDIMCISI
  // ============================================================
  /// Uygulama başlarken anahtarların yüklendiğini doğrulamak için.
  /// Sadece debug modda çağır.
  static void printStatus() {
    assert(() {
      // ignore: avoid_print
      print('🔑 Env durumu:');
      // ignore: avoid_print
      print('   TOMTOM_API_KEY: ${hasTomTomKey ? "✅ yüklü" : "❌ eksik"}');
      // ignore: avoid_print
      print('   ORS_API_KEY:    ${hasOrsKey ? "✅ yüklü" : "❌ eksik"}');
      return true;
    }());
  }
}
