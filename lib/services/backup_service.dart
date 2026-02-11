import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupService {
  static const int schemaVersion = 1;

  static const List<String> _fixedKeys = [
    'ai_provider_settings',
    'sftp_settings',
    'subscription_lists_state',
    'youtube_quota_state',
    'ai_cost_state',
    'ai_cost_history',
  ];

  static const List<String> _prefixes = [
    'expiring_cache:',
  ];

  Future<String> exportJson() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final data = <String, dynamic>{};

    for (final key in keys) {
      if (!_shouldIncludeKey(key)) continue;
      final value = prefs.get(key);
      final serialized = _serializeValue(value);
      if (serialized != null) {
        data[key] = serialized;
      }
    }

    final payload = {
      'version': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'preferences': data,
    };

    return jsonEncode(payload);
  }

  Future<void> importJson(String json) async {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final prefsData =
        (decoded['preferences'] as Map<String, dynamic>?) ?? {};

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (_shouldIncludeKey(key)) {
        await prefs.remove(key);
      }
    }

    for (final entry in prefsData.entries) {
      final key = entry.key;
      if (!_shouldIncludeKey(key)) continue;
      final value = entry.value as Map<String, dynamic>?;
      if (value == null) continue;
      await _restoreValue(prefs, key, value);
    }
  }

  bool _shouldIncludeKey(String key) {
    if (_fixedKeys.contains(key)) return true;
    for (final prefix in _prefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  Map<String, dynamic>? _serializeValue(Object? value) {
    if (value == null) return null;
    if (value is String) {
      return {'type': 'string', 'value': value};
    }
    if (value is int) {
      return {'type': 'int', 'value': value};
    }
    if (value is double) {
      return {'type': 'double', 'value': value};
    }
    if (value is bool) {
      return {'type': 'bool', 'value': value};
    }
    if (value is List<String>) {
      return {'type': 'string_list', 'value': value};
    }
    return null;
  }

  Future<void> _restoreValue(
    SharedPreferences prefs,
    String key,
    Map<String, dynamic> data,
  ) async {
    final type = data['type'] as String?;
    final value = data['value'];
    switch (type) {
      case 'string':
        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is Map || value is List || value is num || value is bool) {
          await prefs.setString(key, jsonEncode(value));
        } else if (value != null) {
          await prefs.setString(key, value.toString());
        }
        break;
      case 'int':
        if (value is int) {
          await prefs.setInt(key, value);
        }
        break;
      case 'double':
        if (value is num) {
          await prefs.setDouble(key, value.toDouble());
        }
        break;
      case 'bool':
        if (value is bool) {
          await prefs.setBool(key, value);
        }
        break;
      case 'string_list':
        if (value is List) {
          final list = value.whereType<String>().toList();
          await prefs.setStringList(key, list);
        }
        break;
    }
  }
}

class SftpBackupService {
  SftpBackupService({BackupService? backupService})
      : _backupService = backupService ?? BackupService();

  final BackupService _backupService;

  Future<List<String>> listBackupFiles({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final directory = _resolveListDirectory(remotePath);
    final socket = await SSHSocket.connect(host, port);
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    try {
      final sftp = await client.sftp();
      final entries = await sftp.listdir(directory);
      final files = <String>[];
      for (final entry in entries) {
        final name = entry.filename;
        if (name == '.' || name == '..') continue;
        files.add(_joinRemotePath(directory, name));
      }
      return files;
    } finally {
      client.close();
    }
  }

  Future<void> testConnection({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final socket = await SSHSocket.connect(host, port);
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    try {
      final sftp = await client.sftp();
      await sftp.handshake;
      final testPath = _resolveTestPath(remotePath);
      if (testPath.isNotEmpty) {
        await sftp.stat(testPath);
      } else {
        await sftp.absolute('.');
      }
    } finally {
      client.close();
    }
  }

  Future<void> exportToSftp({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final json = await _backupService.exportJson();
    final path = _resolveRemotePath(remotePath);

    final socket = await SSHSocket.connect(host, port);
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    try {
      final sftp = await client.sftp();
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      final bytes = Uint8List.fromList(utf8.encode(json));
      await file.writeBytes(bytes);
      await file.close();
    } finally {
      client.close();
    }
  }

  Future<void> importFromSftp({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final path = _resolveRemotePath(remotePath);
    final socket = await SSHSocket.connect(host, port);
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    try {
      final sftp = await client.sftp();
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.read,
      );
      final bytes = await file.readBytes();
      await file.close();
      final json = utf8.decode(bytes);
      await _backupService.importJson(json);
    } finally {
      client.close();
    }
  }

  String _resolveRemotePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed.endsWith('/')) {
      final name = _defaultFileName();
      return trimmed.isEmpty ? name : '$trimmed$name';
    }
    return trimmed;
  }

  String _resolveListDirectory(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '/home/Documentos/Aris';
    if (trimmed.endsWith('/')) {
      return trimmed.endsWith('/') && trimmed.length > 1
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
    }
    final lastSlash = trimmed.lastIndexOf('/');
    if (lastSlash == 0) return '/';
    if (lastSlash > 0) return trimmed.substring(0, lastSlash);
    return '.';
  }

  String _joinRemotePath(String dir, String name) {
    if (dir == '.' || dir.isEmpty) return name;
    if (dir.endsWith('/')) return '$dir$name';
    return '$dir/$name';
  }

  String _resolveTestPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.endsWith('/')) return trimmed;
    final lastSlash = trimmed.lastIndexOf('/');
    if (lastSlash == 0) return '/';
    if (lastSlash > 0) return trimmed.substring(0, lastSlash);
    return '.';
  }

  String _defaultFileName() {
    final now = DateTime.now();
    final stamp = [
      now.year.toString().padLeft(4, '0'),
      now.month.toString().padLeft(2, '0'),
      now.day.toString().padLeft(2, '0'),
      now.hour.toString().padLeft(2, '0'),
      now.minute.toString().padLeft(2, '0'),
    ].join('');
    return 'aris_backup_$stamp.json';
  }
}
