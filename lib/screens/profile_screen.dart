import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../storage/ai_settings_store.dart';
import '../storage/subscription_lists_store.dart';
import '../ui/list_hierarchy.dart';
import '../ui/list_icons.dart';
import '../services/ai_summary_service.dart';
import '../services/ai_cost_tracker.dart';
import '../services/backup_service.dart';
import '../storage/sftp_settings_store.dart';

class _ListFormResult {
  const _ListFormResult({
    required this.name,
    required this.iconKey,
    required this.parentId,
  });

  final String name;
  final String iconKey;
  final String parentId;
}

class _ListDragData {
  const _ListDragData(this.id);

  final String id;
}

class _ModelOption {
  const _ModelOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class _VoiceOption {
  const _VoiceOption({
    required this.id,
    required this.name,
    required this.locale,
    required this.label,
  });

  final String id;
  final String name;
  final String locale;
  final String label;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onSignOut,
    this.onListsChanged,
    this.aiCostTracker,
  });

  final VoidCallback onSignOut;
  final VoidCallback? onListsChanged;
  final AiCostTracker? aiCostTracker;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AiSettingsStore _store = AiSettingsStore();
  final SftpSettingsStore _sftpStore = SftpSettingsStore();
  final SubscriptionListsStore _listsStore = SubscriptionListsStore();
  late final AiSummaryService _aiSummaryService;
  final SftpBackupService _backupService = SftpBackupService();

  static const String _priceNote =
      'Precio por 1M tokens: entrada / caché / salida (cuando aplica)';

  static const List<String> _providers = [
    'ChatGPT',
    'Gemini',
    'Antrophic',
    'Grok',
  ];

  static const Map<String, List<_ModelOption>> _modelsByProvider = {
    'ChatGPT': [
      _ModelOption(
        id: 'gpt-5-mini',
        label: 'gpt-5-mini (€0.25 / €0.025 / €2.00)',
      ),
      _ModelOption(
        id: 'gpt-5-nano',
        label: 'gpt-5-nano (€0.05 / €0.005 / €0.40)',
      ),
      _ModelOption(
        id: 'gpt-4.1-mini',
        label: 'gpt-4.1-mini (€0.40 / €0.10 / €1.60)',
      ),
      _ModelOption(
        id: 'gpt-4.1-nano',
        label: 'gpt-4.1-nano (€0.10 / €0.025 / €0.40)',
      ),
      _ModelOption(
        id: 'gpt-4o-mini',
        label: 'gpt-4o-mini (€0.15 / €0.075 / €0.60)',
      ),
    ],
    'Gemini': [
      _ModelOption(
        id: 'gemini-3-pro-preview',
        label: 'gemini-3-pro-preview (€2.00 / €12.00)',
      ),
      _ModelOption(
        id: 'gemini-3-flash-preview',
        label: 'gemini-3-flash-preview (€0.50 / €3.00)',
      ),
      _ModelOption(
        id: 'gemini-2.5-pro',
        label: 'gemini-2.5-pro (€1.25 / €10.00)',
      ),
      _ModelOption(
        id: 'gemini-2.5-flash',
        label: 'gemini-2.5-flash (€0.30 / €2.50)',
      ),
      _ModelOption(
        id: 'gemini-2.5-flash-lite',
        label: 'gemini-2.5-flash-lite (€0.10 / €0.40)',
      ),
    ],
    'Antrophic': [
      _ModelOption(
        id: 'claude-opus-4-6',
        label: 'claude-opus-4-6 (€5.00 / €25.00)',
      ),
      _ModelOption(
        id: 'claude-sonnet-4-5',
        label: 'claude-sonnet-4-5 (€3.00 / €15.00)',
      ),
      _ModelOption(
        id: 'claude-haiku-4-5',
        label: 'claude-haiku-4-5 (€1.00 / €5.00)',
      ),
    ],
    'Grok': [
      _ModelOption(
        id: 'grok-4',
        label: 'grok-4 (€3.00 / €15.00)',
      ),
      _ModelOption(
        id: 'grok-4-1-fast-reasoning',
        label: 'grok-4-1-fast-reasoning (€0.20 / €0.50)',
      ),
      _ModelOption(
        id: 'grok-4-1-fast-non-reasoning',
        label: 'grok-4-1-fast-non-reasoning (€0.20 / €0.50)',
      ),
      _ModelOption(
        id: 'grok-4-fast-reasoning',
        label: 'grok-4-fast-reasoning (€0.20 / €0.50)',
      ),
      _ModelOption(
        id: 'grok-4-fast-non-reasoning',
        label: 'grok-4-fast-non-reasoning (€0.20 / €0.50)',
      ),
      _ModelOption(
        id: 'grok-code-fast-1',
        label: 'grok-code-fast-1 (€0.20 / €1.50)',
      ),
    ],
  };

  String _selectedProvider = _providers.first;
  String _selectedModel = _modelsByProvider[_providers.first]!.first.id;
  final FlutterTts _tts = FlutterTts();
  List<_VoiceOption> _voiceOptions = const [];
  bool _loadingVoices = true;
  String _selectedVoiceName = '';
  String _selectedVoiceLocale = '';
  String? _previewingVoiceId;
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _sftpHostController =
      TextEditingController(text: '192.168.1.33');
  final TextEditingController _sftpPortController =
      TextEditingController(text: '322');
  final TextEditingController _sftpUserController =
      TextEditingController(text: 'valerogarte');
  final TextEditingController _sftpPasswordController = TextEditingController();
  final TextEditingController _sftpPathController =
      TextEditingController(text: '/home/Documentos/Aris/');
  bool _loading = true;
  bool _testingAi = false;
  bool _showApiKey = false;
  bool _showSftpPassword = false;
  bool _importingBackup = false;
  bool _exportingBackup = false;
  bool _testingSftp = false;
  bool _loadingLists = true;
  List<SubscriptionList> _lists = const [];
  Map<String, Set<String>> _assignments = {};
  String? _draggingListId;
  String? _dragHoverParentId;

  static final RegExp _backupFilePattern =
      RegExp(r'^aris_backup_(\d{12})\.db$');
  static const String _voiceSeparator = '::';
  static const String _defaultVoicePreviewId = '_default_voice';

  @override
  void dispose() {
    _apiKeyController.removeListener(_saveSettings);
    _apiKeyController.dispose();
    _sftpHostController.dispose();
    _sftpPortController.dispose();
    _sftpUserController.dispose();
    _sftpPasswordController.dispose();
    _sftpPathController.dispose();
    _aiSummaryService.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _aiSummaryService = AiSummaryService(costTracker: widget.aiCostTracker);
    _apiKeyController.addListener(_saveSettings);
    _loadSettings();
    _loadVoices();
    _loadSftpSettings();
    _loadLists();
  }

  Future<void> _loadSettings() async {
    final settings = await _store.load();
    if (!mounted) return;
    final provider = _providers.contains(settings.provider)
        ? settings.provider
        : _providers.first;
    final models = _modelsByProvider[provider] ?? const [];
    final model = models.any((item) => item.id == settings.model)
        ? settings.model
        : (models.isNotEmpty ? models.first.id : '');
    setState(() {
      _selectedProvider = provider;
      _selectedModel = model;
      _apiKeyController.text = settings.apiKey;
      _selectedVoiceName = settings.narratorVoiceName;
      _selectedVoiceLocale = settings.narratorVoiceLocale;
      _loading = false;
    });
  }

  String _voiceId(String name, String locale) {
    return '$locale$_voiceSeparator$name';
  }

  Future<void> _loadVoices() async {
    try {
      final rawVoices = await _tts.getVoices;
      final options = <_VoiceOption>[];
      final seen = <String>{};
      if (rawVoices is List) {
        for (final entry in rawVoices) {
          if (entry is! Map) continue;
          final name = entry['name']?.toString() ?? '';
          final locale = entry['locale']?.toString() ?? '';
          if (name.isEmpty || locale.isEmpty) continue;
          final localeLower = locale.toLowerCase();
          if (!localeLower.startsWith('es')) continue;
          final id = _voiceId(name, locale);
          if (!seen.add(id)) continue;
          options.add(
            _VoiceOption(
              id: id,
              name: name,
              locale: locale,
              label: '$name ($locale)',
            ),
          );
        }
      }
      options.sort((a, b) => a.label.compareTo(b.label));
      if (!mounted) return;
      setState(() {
        _voiceOptions = options;
        _loadingVoices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voiceOptions = const [];
        _loadingVoices = false;
      });
    }
  }

  Future<void> _previewVoice({
    required String previewId,
    String? name,
    String? locale,
  }) async {
    if (_previewingVoiceId != null) return;
    setState(() {
      _previewingVoiceId = previewId;
    });
    try {
      await _tts.stop();
      final targetLocale =
          (locale != null && locale.isNotEmpty) ? locale : 'es-ES';
      await _tts.setLanguage(targetLocale);
      if (name != null &&
          name.isNotEmpty &&
          locale != null &&
          locale.isNotEmpty) {
        await _tts.setVoice({
          'name': name,
          'locale': locale,
        });
      }
      await _tts.speak(
        'Hola, a partir de ahora te leeré tus transcripciones.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _previewingVoiceId = null;
        });
      }
    }
  }

  Future<void> _loadSftpSettings() async {
    final settings = await _sftpStore.load();
    if (!mounted) return;
    setState(() {
      _sftpHostController.text = settings.host;
      _sftpPortController.text = settings.port.toString();
      _sftpUserController.text = settings.username;
      _sftpPasswordController.text = settings.password;
      _sftpPathController.text = settings.remotePath;
    });
  }

  void _onProviderChanged(String? provider) {
    if (provider == null || provider == _selectedProvider) return;
    final models = _modelsByProvider[provider] ?? const [];
    setState(() {
      _selectedProvider = provider;
      _selectedModel = models.isNotEmpty ? models.first.id : '';
    });
    _saveSettings();
  }

  void _onModelChanged(String? model) {
    if (model == null) return;
    setState(() {
      _selectedModel = model;
    });
    _saveSettings();
  }

  void _onVoiceChanged(String? value) {
    if (value == null) return;
    setState(() {
      if (value.isEmpty) {
        _selectedVoiceName = '';
        _selectedVoiceLocale = '';
        return;
      }
      final separatorIndex = value.indexOf(_voiceSeparator);
      if (separatorIndex <= 0) {
        _selectedVoiceName = '';
        _selectedVoiceLocale = '';
        return;
      }
      _selectedVoiceLocale = value.substring(0, separatorIndex);
      _selectedVoiceName =
          value.substring(separatorIndex + _voiceSeparator.length);
    });
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    if (_loading) return;
    final settings = AiProviderSettings(
      provider: _selectedProvider,
      model: _selectedModel,
      apiKey: _apiKeyController.text.trim(),
      narratorVoiceName: _selectedVoiceName,
      narratorVoiceLocale: _selectedVoiceLocale,
    );
    await _store.save(settings);
  }

  Future<void> _saveAiSettingsWithFeedback() async {
    await _saveSettings();
    if (!mounted || _loading) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos de IA guardados.')),
    );
  }

  Future<void> _saveSftpSettings({bool showFeedback = true}) async {
    final settings = SftpSettings(
      host: _sftpHostController.text.trim(),
      port: int.tryParse(_sftpPortController.text.trim()) ?? 22,
      username: _sftpUserController.text.trim(),
      password: _sftpPasswordController.text,
      remotePath: _sftpPathController.text.trim().isEmpty
          ? '/home/Documentos/Aris/'
          : _sftpPathController.text.trim(),
    );
    await _sftpStore.save(settings);
    if (!mounted || !showFeedback) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos SFTP guardados.')),
    );
  }

  Future<void> _exportBackup() async {
    final host = _sftpHostController.text.trim();
    final user = _sftpUserController.text.trim();
    final password = _sftpPasswordController.text;
    final port = int.tryParse(_sftpPortController.text.trim()) ?? 22;
    final path = _sftpPathController.text.trim();

    if (host.isEmpty || user.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa host, usuario y contraseña.')),
      );
      return;
    }

    await _saveSftpSettings(showFeedback: false);

    setState(() {
      _exportingBackup = true;
    });
    try {
      await _backupService.exportToSftp(
        host: host,
        port: port,
        username: user,
        password: password,
        remotePath: path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup exportado.')),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Error al exportar'),
            content: SingleChildScrollView(
              child: SelectableText(error.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingBackup = false;
        });
      }
    }
  }

  Future<void> _importBackup() async {
    final host = _sftpHostController.text.trim();
    final user = _sftpUserController.text.trim();
    final password = _sftpPasswordController.text;
    final port = int.tryParse(_sftpPortController.text.trim()) ?? 22;
    final path = _sftpPathController.text.trim();

    if (host.isEmpty || user.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa host, usuario y contraseña.')),
      );
      return;
    }

    setState(() {
      _importingBackup = true;
    });
    try {
      final selectedPath = await _selectBackupFile(
        host: host,
        port: port,
        user: user,
        password: password,
        remotePath: path,
      );
      if (selectedPath == null) return;

      final selectedName = _basename(selectedPath);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Importar backup'),
            content: Text(
              'Se importará "$selectedName" y se reemplazará la configuración local. ¿Quieres continuar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Importar'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;

      await _saveSftpSettings(showFeedback: false);

      await _backupService.importFromSftp(
        host: host,
        port: port,
        username: user,
        password: password,
        remotePath: selectedPath,
      );
      if (!mounted) return;
      await _loadSettings();
      await _loadLists();
      widget.onListsChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup importado.')),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Error al importar'),
            content: SingleChildScrollView(
              child: SelectableText(error.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _importingBackup = false;
        });
      }
    }
  }

  Future<void> _testSftp() async {
    final host = _sftpHostController.text.trim();
    final user = _sftpUserController.text.trim();
    final password = _sftpPasswordController.text;
    final port = int.tryParse(_sftpPortController.text.trim()) ?? 22;
    final path = _sftpPathController.text.trim();

    if (host.isEmpty || user.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa host, usuario y contraseña.')),
      );
      return;
    }

    await _saveSftpSettings(showFeedback: false);

    setState(() {
      _testingSftp = true;
    });
    try {
      await _backupService.testConnection(
        host: host,
        port: port,
        username: user,
        password: password,
        remotePath: path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conexión SFTP correcta.')),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Error en la conexión'),
            content: SingleChildScrollView(
              child: SelectableText(error.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingSftp = false;
        });
      }
    }
  }

  Future<void> _testProvider() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduce una clave API primero.')),
      );
      return;
    }
    if (_selectedModel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un modelo primero.')),
      );
      return;
    }

    setState(() {
      _testingAi = true;
    });

    try {
      final result = await _aiSummaryService.summarize(
        provider: _selectedProvider,
        model: _selectedModel,
        apiKey: apiKey,
        transcript:
            'Este es un texto corto de prueba para verificar la conexión.',
        title: 'Prueba de conexión',
        channel: 'ARIS',
      );
      if (!mounted) return;
      setState(() {
        _testingAi = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Prueba correcta'),
            content: SingleChildScrollView(
              child: SelectableText(result),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testingAi = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Prueba fallida'),
            content: SingleChildScrollView(
              child: SelectableText(error.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<String?> _selectBackupFile({
    required String host,
    required int port,
    required String user,
    required String password,
    required String remotePath,
  }) async {
    List<String> files;
    try {
      files = await _backupService.listBackupFiles(
        host: host,
        port: port,
        username: user,
        password: password,
        remotePath: remotePath,
      );
    } catch (error) {
      if (!mounted) return null;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Error al listar backups'),
            content: SingleChildScrollView(
              child: SelectableText(error.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
      return null;
    }

    final candidates = files
        .where((path) => _backupFilePattern.hasMatch(_basename(path)))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontraron backups válidos.')),
      );
      return null;
    }

    candidates.sort((a, b) {
      final aTime = _parseBackupTimestamp(_basename(a));
      final bTime = _parseBackupTimestamp(_basename(b));
      if (aTime == null && bTime == null) return a.compareTo(b);
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Selecciona un backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final path = candidates[index];
                final name = _basename(path);
                final dateLabel = _formatBackupDateLabel(name);
                return ListTile(
                  leading: const Icon(Icons.description),
                  title: Text(name),
                  subtitle: dateLabel == null ? null : Text(dateLabel),
                  onTap: () => Navigator.of(context).pop(path),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  String _basename(String path) {
    final index = path.lastIndexOf('/');
    if (index == -1) return path;
    return path.substring(index + 1);
  }

  DateTime? _parseBackupTimestamp(String filename) {
    final match = _backupFilePattern.firstMatch(filename);
    if (match == null) return null;
    final stamp = match.group(1);
    if (stamp == null || stamp.length != 12) return null;
    try {
      final year = int.parse(stamp.substring(0, 4));
      final month = int.parse(stamp.substring(4, 6));
      final day = int.parse(stamp.substring(6, 8));
      final hour = int.parse(stamp.substring(8, 10));
      final minute = int.parse(stamp.substring(10, 12));
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  String? _formatBackupDateLabel(String filename) {
    final date = _parseBackupTimestamp(filename);
    if (date == null) return null;
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString().padLeft(4, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  Future<void> _loadLists() async {
    try {
      final data = await _listsStore.load();
      if (!mounted) return;
      setState(() {
        _lists = data.lists;
        _assignments = data.assignments;
        _loadingLists = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLists = false;
      });
    }
  }

  Future<void> _saveLists() async {
    await _listsStore.save(_lists, _assignments);
    widget.onListsChanged?.call();
  }

  Set<String> _collectDescendantIds(String rootId) {
    final childrenByParent = <String, List<String>>{};
    for (final list in _lists) {
      final parentId = list.parentId.trim();
      if (parentId.isEmpty) continue;
      childrenByParent.putIfAbsent(parentId, () => []).add(list.id);
    }
    final visited = <String>{};
    final descendants = <String>{};
    final stack = <String>[rootId];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (!visited.add(current)) continue;
      final children = childrenByParent[current];
      if (children == null) continue;
      for (final child in children) {
        if (descendants.add(child)) {
          stack.add(child);
        }
      }
    }
    return descendants;
  }

  bool _canAssignParent(String childId, String parentId) {
    if (childId.isEmpty || parentId.isEmpty) return false;
    if (childId == parentId) return false;
    final descendants = _collectDescendantIds(childId);
    return !descendants.contains(parentId);
  }

  void _assignParentByDrag(String childId, String parentId) {
    if (!_canAssignParent(childId, parentId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No puedes asignar como padre una etiqueta hija.'),
        ),
      );
      return;
    }
    final current = _lists.firstWhere(
      (list) => list.id == childId,
      orElse: () => SubscriptionList(id: '', name: '', iconKey: 'label'),
    );
    if (current.id.isEmpty || current.parentId == parentId) return;
    setState(() {
      _lists = _lists
          .map(
            (list) => list.id == childId
                ? list.copyWith(parentId: parentId)
                : list,
          )
          .toList();
      _dragHoverParentId = null;
    });
    _saveLists();
  }

  void _reorderLists(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final updated = [..._lists];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    setState(() {
      _lists = updated;
    });
    _saveLists();
  }

  Future<void> _createList() async {
    final result = await _promptListForm();
    if (result == null) return;
    final list = SubscriptionList(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: result.name,
      iconKey: result.iconKey,
      parentId: result.parentId,
    );
    setState(() {
      _lists = [..._lists, list];
    });
    await _saveLists();
  }

  Future<void> _renameList(SubscriptionList list) async {
    final result = await _promptListForm(
      initialName: list.name,
      initialIconKey: list.iconKey,
      initialParentId: list.parentId,
      currentListId: list.id,
    );
    if (result == null) return;
    setState(() {
      _lists = _lists
          .map(
            (item) => item.id == list.id
                ? item.copyWith(
                    name: result.name,
                    iconKey: result.iconKey,
                    parentId: result.parentId,
                  )
                : item,
          )
          .toList();
    });
    await _saveLists();
  }

  Future<void> _deleteList(SubscriptionList list) async {
    final confirm = await _confirmDelete(list.name);
    if (!confirm) return;
    setState(() {
      _lists = _lists
          .map(
            (item) => item.parentId == list.id
                ? item.copyWith(parentId: '')
                : item,
          )
          .where((item) => item.id != list.id)
          .toList();
      _assignments.remove(list.id);
    });
    await _saveLists();
  }

  Future<_ListFormResult?> _promptListForm({
    String? initialName,
    String? initialIconKey,
    String? initialParentId,
    String? currentListId,
  }) {
    final controller = TextEditingController(text: initialName ?? '');
    var selectedIconKey = initialIconKey ?? listIconOptions.first.key;
    final listById = {
      for (final list in _lists) list.id: list,
    };
    final excluded = <String>{};
    if (currentListId != null && currentListId.isNotEmpty) {
      excluded.add(currentListId);
      excluded.addAll(_collectDescendantIds(currentListId));
    }
    final parentCandidates = _lists
        .where((list) => !excluded.contains(list.id))
        .toList()
      ..sort(
        (a, b) => listDisplayName(a, listById)
            .compareTo(listDisplayName(b, listById)),
      );
    var selectedParentId = initialParentId ?? '';
    if (selectedParentId.isNotEmpty &&
        !parentCandidates.any((list) => list.id == selectedParentId)) {
      selectedParentId = '';
    }
    return showDialog<_ListFormResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title:
                  Text(initialName == null ? 'Nueva lista' : 'Editar lista'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la lista',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedIconKey,
                    items: listIconOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option.key,
                            child: Row(
                              children: [
                                Icon(option.icon),
                                const SizedBox(width: 8),
                                Text(option.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedIconKey = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Icono',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedParentId,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sin padre'),
                      ),
                      for (final list in parentCandidates)
                        DropdownMenuItem(
                          value: list.id,
                          child: Text(listDisplayName(list, listById)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedParentId = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta padre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isEmpty) return;
                    Navigator.of(context).pop(
                      _ListFormResult(
                        name: name,
                        iconKey: selectedIconKey,
                        parentId: selectedParentId.trim(),
                      ),
                    );
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmDelete(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar lista'),
          content: Text('¿Quieres eliminar la lista "$name"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Widget _buildAiSection(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final models = _modelsByProvider[_selectedProvider] ?? const [];
        final selectedModel = models.any((item) => item.id == _selectedModel)
            ? _selectedModel
            : (models.isNotEmpty ? models.first.id : null);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedProvider,
                items: _providers
                    .map(
                      (provider) => DropdownMenuItem(
                        value: provider,
                        child: Text(provider),
                      ),
                    )
                    .toList(),
                onChanged: _loading
                    ? null
                    : (provider) {
                        _onProviderChanged(provider);
                        setModalState(() {});
                      },
                decoration: const InputDecoration(
                  labelText: 'Proveedor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedModel,
                items: models
                    .map(
                      (model) => DropdownMenuItem(
                        value: model.id,
                        child: Text(model.label),
                      ),
                    )
                    .toList(),
                onChanged: _loading || models.isEmpty ? null : _onModelChanged,
                decoration: const InputDecoration(
                  labelText: 'Modelo',
                  helperText: _priceNote,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiKeyController,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: !_showApiKey,
                decoration: InputDecoration(
                  labelText: 'Clave API',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _showApiKey = !_showApiKey;
                      });
                    },
                    icon: Icon(
                      _showApiKey ? Icons.visibility_off : Icons.visibility,
                    ),
                    tooltip: _showApiKey ? 'Ocultar clave' : 'Mostrar clave',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _testingAi ? null : _testProvider,
                icon: _testingAi
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _testingAi ? 'Probando...' : 'Probar proveedor',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _saveAiSettingsWithFeedback,
                icon: const Icon(Icons.save),
                label: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceSection(BuildContext context) {
    final currentVoiceId =
        (_selectedVoiceName.isNotEmpty && _selectedVoiceLocale.isNotEmpty)
            ? _voiceId(_selectedVoiceName, _selectedVoiceLocale)
            : '';
    final selectedId =
        _voiceOptions.any((option) => option.id == currentVoiceId)
            ? currentVoiceId
            : '';
    final previewingId = _previewingVoiceId;
    final canPreview = !_loadingVoices && previewingId == null;
    final helperStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Colors.white70);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Selecciona la voz del narrador (solo español).',
            style: helperStyle,
          ),
          if (_loadingVoices) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (!_loadingVoices && _voiceOptions.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('No se encontraron voces en español.'),
          ],
          const SizedBox(height: 8),
          _buildVoiceOptionTile(
            label: 'Predeterminada',
            value: '',
            selectedValue: selectedId,
            previewId: _defaultVoicePreviewId,
            canPreview: canPreview,
            isPreviewing: previewingId == _defaultVoicePreviewId,
            onSelect: () => _onVoiceChanged(''),
            onPreview: () => _previewVoice(
              previewId: _defaultVoicePreviewId,
            ),
          ),
          for (final option in _voiceOptions)
            _buildVoiceOptionTile(
              label: option.label,
              value: option.id,
              selectedValue: selectedId,
              previewId: option.id,
              canPreview: canPreview,
              isPreviewing: previewingId == option.id,
              onSelect: () => _onVoiceChanged(option.id),
              onPreview: () => _previewVoice(
                previewId: option.id,
                name: option.name,
                locale: option.locale,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceOptionTile({
    required String label,
    required String value,
    required String selectedValue,
    required String previewId,
    required bool canPreview,
    required bool isPreviewing,
    required VoidCallback onSelect,
    required VoidCallback onPreview,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<String>(
        value: value,
        groupValue: selectedValue,
        onChanged: (_) => onSelect(),
      ),
      title: Text(label),
      trailing: IconButton(
        onPressed: canPreview && !isPreviewing ? onPreview : null,
        icon: isPreviewing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.volume_up),
        tooltip: isPreviewing ? 'Reproduciendo...' : 'Reproducir demo',
      ),
      onTap: onSelect,
    );
  }

  Widget _buildSftpSection(BuildContext context) {
    final sftpBusy = _importingBackup || _exportingBackup || _testingSftp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _sftpHostController,
            decoration: const InputDecoration(
              labelText: 'Host',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sftpPortController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Puerto',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sftpUserController,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sftpPasswordController,
            obscureText: !_showSftpPassword,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _showSftpPassword = !_showSftpPassword;
                  });
                },
                icon: Icon(
                  _showSftpPassword ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: _showSftpPassword
                    ? 'Ocultar contraseña'
                    : 'Mostrar contraseña',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sftpPathController,
            decoration: const InputDecoration(
              labelText: 'Ruta remota (archivo o carpeta)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: sftpBusy ? null : _saveSftpSettings,
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: sftpBusy ? null : _testSftp,
            icon: _testingSftp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(_testingSftp ? 'Probando...' : 'Test'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sftpBusy ? null : _importBackup,
                  icon: _importingBackup
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Importar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: sftpBusy ? null : _exportBackup,
                  icon: _exportingBackup
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.upload),
                  label: const Text('Exportar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListsSection(BuildContext context) {
    final listById = {
      for (final list in _lists) list.id: list,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Listas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: TextButton.icon(
              onPressed: _loadingLists ? null : _createList,
              icon: const Icon(Icons.add),
              label: const Text('Crear'),
            ),
          ),
          if (_loadingLists) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ] else if (_lists.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('No tienes listas creadas.'),
          ] else ...[
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _lists.length,
              onReorder: _reorderLists,
              itemBuilder: (context, index) {
                final list = _lists[index];
                final displayName = listDisplayName(list, listById);
                final isDropTarget = _dragHoverParentId == list.id;
                final isDragging = _draggingListId == list.id;
                return DragTarget<_ListDragData>(
                  key: ValueKey(list.id),
                  onWillAcceptWithDetails: (details) {
                    final canAccept =
                        _canAssignParent(details.data.id, list.id);
                    if (canAccept) {
                      setState(() {
                        _dragHoverParentId = list.id;
                      });
                    }
                    return canAccept;
                  },
                  onLeave: (_) {
                    if (_dragHoverParentId == list.id) {
                      setState(() {
                        _dragHoverParentId = null;
                      });
                    }
                  },
                  onAcceptWithDetails: (details) {
                    _assignParentByDrag(details.data.id, list.id);
                  },
                  builder: (context, candidateData, rejectedData) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: isDropTarget
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isDropTarget
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                      child: Opacity(
                        opacity: isDragging ? 0.4 : 1,
                        child: ListTile(
                          minLeadingWidth: 72,
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              ),
                              const SizedBox(width: 8),
                              Icon(iconForListKey(list.iconKey)),
                            ],
                          ),
                          title: Text(displayName),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LongPressDraggable<_ListDragData>(
                                data: _ListDragData(list.id),
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 240),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1F1F1F),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x55000000),
                                            blurRadius: 8,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        displayName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                                childWhenDragging: Icon(
                                  Icons.account_tree,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                                onDragStarted: () {
                                  setState(() {
                                    _draggingListId = list.id;
                                  });
                                },
                                onDragEnd: (_) {
                                  if (!mounted) return;
                                  setState(() {
                                    _draggingListId = null;
                                    _dragHoverParentId = null;
                                  });
                                },
                                child: IconButton(
                                  icon: const Icon(Icons.account_tree),
                                  tooltip: 'Arrastra para asignar padre',
                                  onPressed: () {},
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'Editar',
                                onPressed: () => _renameList(list),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                tooltip: 'Eliminar',
                                onPressed: () => _deleteList(list),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _openSection({
    required String title,
    required Widget Function(BuildContext) builder,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: builder(context),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerSubtitle = _loading
        ? 'Cargando...'
        : '$_selectedProvider • $_selectedModel';
    final voiceSubtitle =
        _selectedVoiceName.isNotEmpty && _selectedVoiceLocale.isNotEmpty
            ? '$_selectedVoiceName ($_selectedVoiceLocale)'
            : 'Predeterminada';
    final sftpHost = _sftpHostController.text.trim();
    final sftpPort = _sftpPortController.text.trim();
    final sftpSubtitle = sftpHost.isEmpty
        ? 'Sin configurar'
        : sftpPort.isEmpty
            ? sftpHost
            : '$sftpHost:$sftpPort';
    final listsSubtitle =
        _loadingLists ? 'Cargando...' : '${_lists.length} listas';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            onPressed: () {
              widget.onSignOut();
              if (mounted) {
                Navigator.of(context).maybePop();
              }
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildMenuTile(
            icon: Icons.auto_fix_high,
            title: 'Proveedor de IA',
            subtitle: providerSubtitle,
            onTap: () => _openSection(
              title: 'Proveedor de IA',
              builder: (context) => _buildAiSection(context),
            ),
          ),
          _buildMenuTile(
            icon: Icons.record_voice_over,
            title: 'Voz del narrador',
            subtitle: voiceSubtitle,
            onTap: () => _openSection(
              title: 'Voz del narrador',
              builder: _buildVoiceSection,
            ),
          ),
          _buildMenuTile(
            icon: Icons.sync_alt,
            title: 'Importar / Exportar (SFTP)',
            subtitle: sftpSubtitle,
            onTap: () => _openSection(
              title: 'Importar / Exportar (SFTP)',
              builder: _buildSftpSection,
            ),
          ),
          _buildMenuTile(
            icon: Icons.view_list,
            title: 'Listas',
            subtitle: listsSubtitle,
            onTap: () => _openSection(
              title: 'Listas',
              builder: _buildListsSection,
            ),
          ),
        ],
      ),
    );
  }
}
