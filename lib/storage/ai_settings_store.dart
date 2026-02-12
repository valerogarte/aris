import 'dart:convert';

import 'app_database.dart';

class AiProviderSettings {
  AiProviderSettings({
    required this.provider,
    required this.model,
    required this.apiKey,
    this.narratorVoiceName = '',
    this.narratorVoiceLocale = '',
  });

  final String provider;
  final String model;
  final String apiKey;
  final String narratorVoiceName;
  final String narratorVoiceLocale;

  AiProviderSettings copyWith({
    String? provider,
    String? model,
    String? apiKey,
    String? narratorVoiceName,
    String? narratorVoiceLocale,
  }) {
    return AiProviderSettings(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      narratorVoiceName: narratorVoiceName ?? this.narratorVoiceName,
      narratorVoiceLocale: narratorVoiceLocale ?? this.narratorVoiceLocale,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        'apiKey': apiKey,
        'narratorVoiceName': narratorVoiceName,
        'narratorVoiceLocale': narratorVoiceLocale,
      };

  factory AiProviderSettings.fromJson(Map<String, dynamic> json) {
    return AiProviderSettings(
      provider: (json['provider'] as String?) ?? 'ChatGPT',
      model: (json['model'] as String?) ?? 'gpt-5-mini',
      apiKey: (json['apiKey'] as String?) ?? '',
      narratorVoiceName: (json['narratorVoiceName'] as String?) ?? '',
      narratorVoiceLocale: (json['narratorVoiceLocale'] as String?) ?? '',
    );
  }

  factory AiProviderSettings.defaults() {
    return AiProviderSettings(
      provider: 'ChatGPT',
      model: 'gpt-5-mini',
      apiKey: '',
      narratorVoiceName: '',
      narratorVoiceLocale: '',
    );
  }
}

class AiSettingsStore {
  static const String _storageKey = 'ai_provider_settings';

  Future<AiProviderSettings> load() async {
    final raw = await AppDatabase.instance.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return AiProviderSettings.defaults();
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AiProviderSettings.fromJson(decoded);
    } catch (_) {
      return AiProviderSettings.defaults();
    }
  }

  Future<void> save(AiProviderSettings settings) async {
    await AppDatabase.instance.setString(
      _storageKey,
      jsonEncode(settings.toJson()),
    );
  }
}
