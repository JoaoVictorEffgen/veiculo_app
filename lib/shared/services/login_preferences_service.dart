import 'package:shared_preferences/shared_preferences.dart';

class LoginPreferencesService {
  static const _rememberKey = 'login_remember_email';
  static const _emailKey = 'login_saved_email';

  Future<({bool remember, String? email})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberKey) ?? false;
    final email = prefs.getString(_emailKey);
    return (remember: remember, email: email);
  }

  Future<void> save({required bool remember, required String email}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, remember);
    if (remember && email.trim().isNotEmpty) {
      await prefs.setString(_emailKey, email.trim().toLowerCase());
    } else {
      await prefs.remove(_emailKey);
    }
  }
}
