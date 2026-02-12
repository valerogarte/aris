import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../storage/app_database.dart';

class SftpBackupService {
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
    final path = _resolveRemotePath(remotePath, ensureDb: true);
    final bytes = await _readDatabaseBytes();

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
    final path = _resolveRemotePath(remotePath, ensureDb: true);
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
      await _writeDatabaseBytes(bytes);
    } finally {
      client.close();
    }
  }

  String _resolveRemotePath(String path, {required bool ensureDb}) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed.endsWith('/')) {
      final name = _defaultFileName();
      return trimmed.isEmpty ? name : '$trimmed$name';
    }
    if (ensureDb && trimmed.toLowerCase().endsWith('.json')) {
      throw StateError('Solo se permiten backups .db');
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
    return 'aris_backup_$stamp.db';
  }

  Future<Uint8List> _readDatabaseBytes() async {
    final db = AppDatabase.instance;
    await db.keys();
    await db.checkpoint();
    try {
      await db.close();
    } catch (_) {
      // Ignore close errors to avoid breaking export.
    }
    final dbPath = await db.databasePath();
    final file = File(dbPath);
    if (!await file.exists()) {
      throw StateError('No se encontró la base de datos en $dbPath');
    }
    return await file.readAsBytes();
  }

  Future<void> _writeDatabaseBytes(Uint8List bytes) async {
    final db = AppDatabase.instance;
    await db.close();
    final dbPath = await db.databasePath();
    final file = File(dbPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    await _cleanupWalFiles(dbPath);
  }

  Future<void> _cleanupWalFiles(String dbPath) async {
    final wal = File('$dbPath-wal');
    if (await wal.exists()) {
      await wal.delete();
    }
    final shm = File('$dbPath-shm');
    if (await shm.exists()) {
      await shm.delete();
    }
  }
}
