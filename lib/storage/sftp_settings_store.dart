import 'dart:convert';

import 'app_database.dart';

class SftpSettings {
  SftpSettings({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.remotePath,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'remotePath': remotePath,
      };

  factory SftpSettings.fromJson(Map<String, dynamic> json) {
    return SftpSettings(
      host: (json['host'] as String?) ?? '192.168.1.33',
      port: (json['port'] as num?)?.toInt() ?? 322,
      username: (json['username'] as String?) ?? 'valerogarte',
      password: (json['password'] as String?) ?? '',
      remotePath:
          (json['remotePath'] as String?) ?? '/home/Documentos/Aris/',
    );
  }

  factory SftpSettings.defaults() {
    return SftpSettings(
      host: '192.168.1.33',
      port: 322,
      username: 'valerogarte',
      password: '',
      remotePath: '/home/Documentos/Aris/',
    );
  }
}

class SftpSettingsStore {
  static const String _storageKey = 'sftp_settings';

  Future<SftpSettings> load() async {
    final raw = await AppDatabase.instance.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return SftpSettings.defaults();
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SftpSettings.fromJson(decoded);
    } catch (_) {
      return SftpSettings.defaults();
    }
  }

  Future<void> save(SftpSettings settings) async {
    await AppDatabase.instance.setString(
      _storageKey,
      jsonEncode(settings.toJson()),
    );
  }
}
