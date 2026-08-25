import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TripStartVoiceService {
  TripStartVoiceService() : _tts = FlutterTts();

  final FlutterTts _tts;
  var _configured = false;

  Future<void> announceTripStart(String driverName) async {
    if (kIsWeb) return;

    final trimmedName = driverName.trim();
    if (trimmedName.isEmpty) return;

    try {
      await _ensureConfigured();
      final greeting = _greetingForNow();
      await _tts.stop();
      await _tts.speak('$greeting, $trimmedName! Lembre-se de colocar o cinto, motorista.');
    } catch (error) {
      debugPrint('TripStartVoiceService: $error');
    }
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    _configured = true;
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Bom dia';
    if (hour >= 12 && hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
