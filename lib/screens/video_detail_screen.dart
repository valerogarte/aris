import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../models/youtube_caption_track.dart';
import '../models/youtube_video.dart';
import '../services/quota_tracker.dart';
import '../services/ai_summary_service.dart';
import '../services/youtube_api_service.dart';
import '../services/youtube_transcript_service.dart';
import '../storage/ai_settings_store.dart';
import '../storage/expiring_cache_store.dart';
import '../services/ai_cost_tracker.dart';
import '../ui/channel_avatar.dart';
import 'channel_videos_screen.dart';

class VideoDetailScreen extends StatefulWidget {
  const VideoDetailScreen({
    super.key,
    required this.video,
    required this.accessToken,
    this.channelAvatarUrl = '',
    this.quotaTracker,
    this.aiCostTracker,
  });

  final YouTubeVideo video;
  final String accessToken;
  final String channelAvatarUrl;
  final QuotaTracker? quotaTracker;
  final AiCostTracker? aiCostTracker;

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  static const Duration _cacheTtl = Duration(days: 2);
  static const int _summaryPreviewLines = 10;
  static const int _ttsChunkLimit = 1000;

  late final YouTubeTranscriptService _transcripts;
  late final YouTubeApiService _api;
  final AiSettingsStore _aiSettingsStore = AiSettingsStore();
  late final AiSummaryService _aiSummaryService;
  late final ExpiringCacheStore _transcriptCache;
  late final ExpiringCacheStore _summaryCache;
  final ExpiringCacheStore _avatarCache =
      ExpiringCacheStore('channel_avatars');
  YoutubePlayerController? _playerController;
  Timer? _playerTimeout;
  bool _playerReady = false;
  bool _playerStuck = false;
  bool _useHybridComposition = true;
  List<YouTubeCaptionTrack> _tracks = const [];
  YouTubeCaptionTrack? _selectedTrack;
  bool _userSelectedTrack = false;
  String? _transcript;
  String? _summary;
  String? _summaryError;
  String? _error;
  bool _loadingTracks = false;
  bool _loadingTranscript = false;
  bool _loadingSummary = false;
  bool _summaryRequested = false;
  bool _summaryInFlight = false;
  bool _disposePending = false;
  bool _aiServiceDisposed = false;
  late final FlutterTts _tts;
  bool _ttsReady = false;
  bool _ttsPlaying = false;
  bool _ttsPaused = false;
  _TtsTarget _ttsTarget = _TtsTarget.none;
  String _ttsSpeechText = '';
  List<_TtsChunk> _ttsQueue = const [];
  int _ttsQueueIndex = 0;
  int _ttsChunkOffset = 0;
  String _ttsChunkText = '';
  bool _ttsSequenceActive = false;
  int _ttsQuestionsStartOffset = 0;
  bool _ttsQuestionsFromMainActive = false;
  int _ttsHighlightStart = 0;
  int _ttsMainHighlightEnd = 0;
  int _ttsIntroHighlightEnd = 0;
  String _ttsQuestionsText = '';
  int _ttsQuestionsPrefixLength = 0;
  List<_QuestionRange> _ttsQuestionRanges = const [];
  List<int> _ttsQuestionHighlightEnds = const [];
  String? _summaryIntro;
  String? _summaryMain;
  List<String> _summaryQuestions = const [];
  String _channelAvatarUrl = '';
  bool _loadingChannelAvatar = false;
  bool _summaryMainExpanded = false;
  bool _transcriptExpanded = false;
  _SummaryTab _activeTab = _SummaryTab.summary;

  @override
  void initState() {
    super.initState();
    _transcripts = YouTubeTranscriptService();
    _api = YouTubeApiService(
      accessToken: widget.accessToken,
      quotaTracker: widget.quotaTracker,
    );
    _aiSummaryService = AiSummaryService(costTracker: widget.aiCostTracker);
    _tts = FlutterTts();
    _configureTts();
    _transcriptCache = ExpiringCacheStore('transcripts');
    _summaryCache = ExpiringCacheStore('summaries');
    _channelAvatarUrl = widget.channelAvatarUrl;
    _log('init video=${widget.video.id}');
    _initPlayer();
    _loadChannelAvatar();
    _loadSummaryFromVideoCache();
    _ensureTranscriptLoaded();
  }

  @override
  void dispose() {
    _disposePending = true;
    _playerTimeout?.cancel();
    _playerController?.dispose();
    _transcripts.dispose();
    _api.dispose();
    if (!_summaryInFlight) {
      _disposeAiService();
    }
    _tts.stop();
    super.dispose();
  }

  void _disposeAiService() {
    if (_aiServiceDisposed) return;
    _aiSummaryService.dispose();
    _aiServiceDisposed = true;
  }

  void _initPlayer() {
    _playerTimeout?.cancel();
    _playerController?.dispose();
    _playerReady = false;
    _playerStuck = false;

    if (widget.video.id.isEmpty) {
      _playerController = null;
      return;
    }

    _playerController = YoutubePlayerController(
      initialVideoId: widget.video.id,
      flags: YoutubePlayerFlags(autoPlay: false, enableCaption: true, useHybridComposition: _useHybridComposition),
    );
    if (mounted) {
      setState(() {});
    }

    _playerTimeout = Timer(const Duration(seconds: 8), () {
      if (!mounted || _playerReady) return;
      if (_useHybridComposition) {
        _useHybridComposition = false;
        _initPlayer();
        return;
      }
      setState(() {
        _playerStuck = true;
      });
    });
  }

  void _handlePlayerReady() {
    if (_playerReady) return;
    _playerReady = true;
    _playerTimeout?.cancel();
    if (mounted) {
      setState(() {
        _playerStuck = false;
      });
    }
  }

  Future<void> _loadChannelAvatar() async {
    if (_loadingChannelAvatar) return;
    if (_channelAvatarUrl.isNotEmpty) return;
    final channelId = widget.video.channelId.trim();
    if (channelId.isEmpty) return;
    _loadingChannelAvatar = true;
    try {
      final cached = await _avatarCache.get(channelId);
      if (!mounted) return;
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _channelAvatarUrl = cached;
        });
        return;
      }
      final fetched = await _api.fetchChannelThumbnails([channelId]);
      if (!mounted) return;
      final url = fetched[channelId];
      if (url != null && url.isNotEmpty) {
        await _avatarCache.set(channelId, url, _cacheTtl);
        if (mounted) {
          setState(() {
            _channelAvatarUrl = url;
          });
        }
      }
    } catch (_) {
      // Ignore avatar errors.
    } finally {
      _loadingChannelAvatar = false;
    }
  }

  void _openChannelVideos() {
    final channelId = widget.video.channelId.trim();
    if (channelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró el canal.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelVideosScreen(
          accessToken: widget.accessToken,
          channelId: channelId,
          channelTitle: widget.video.channelTitle,
          channelAvatarUrl: _channelAvatarUrl,
          quotaTracker: widget.quotaTracker,
          aiCostTracker: widget.aiCostTracker,
        ),
      ),
    );
  }

  Future<void> _loadTracksIfNeeded({bool silent = false}) async {
    if (_tracks.isNotEmpty || _loadingTracks) return;
    setState(() {
      _loadingTracks = true;
      if (!silent) {
        _error = null;
      }
    });
    _log('tracks: loading...');
    try {
      final tracks = await _transcripts.fetchCaptionTracks(widget.video.id);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        if (_selectedTrack == null) {
          _selectedTrack = _pickDefaultTrack(tracks);
          _userSelectedTrack = false;
        }
      });
      _log('tracks: loaded count=${tracks.length} selected=${_selectedTrack?.id ?? 'none'}');
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = 'No se pudieron cargar las pistas de subtítulos.\n$error';
        });
      }
      _log('tracks: error $error');
    } finally {
      if (mounted) {
        setState(() {
          _loadingTracks = false;
        });
      }
    }
  }

  Future<void> _ensureTranscriptLoaded() async {
    if (_loadingTranscript || widget.video.id.isEmpty) return;
    setState(() {
      _loadingTranscript = true;
      _error = null;
    });
    _log('transcript: start');

    try {
      await _loadSummaryFromVideoCache();
      await _loadTracksIfNeeded(silent: true);
      if (!mounted) return;
      if (_selectedTrack == null) {
        setState(() {
          _error = 'No hay transcripciones disponibles para este vídeo.';
        });
        _log('transcript: no tracks');
        return;
      }

      final trackKey = _trackCacheKey(_selectedTrack!);
      _log('transcript: trackKey=$trackKey');
      await _loadSummaryFromCache(
        trackKey: trackKey,
        allowFallback: !_userSelectedTrack,
      );

      final transcriptKey = '${widget.video.id}:$trackKey';
      final cachedTranscript = await _transcriptCache.get(transcriptKey);
      _log(cachedTranscript == null ? 'transcript: cache miss key=$transcriptKey' : 'transcript: cache hit key=$transcriptKey len=${cachedTranscript.length}');
      final text = cachedTranscript ?? await _transcripts.downloadCaption(_selectedTrack!.id);
      if (!mounted) return;
      setState(() {
        _transcript = text.isEmpty ? null : text;
        if (text.isEmpty) {
          _error = 'No se pudo generar la transcripción.';
        }
      });
      _log(text.isEmpty ? 'transcript: empty' : 'transcript: loaded len=${text.length}');
      if (cachedTranscript == null && text.isNotEmpty) {
        await _transcriptCache.set(transcriptKey, text, _cacheTtl);
        _log('transcript: cached key=$transcriptKey');
      }

      if (_summaryRequested) {
        await _maybeGenerateSummary();
      }
    } catch (error) {
      if (!mounted) return;
      if (_selectedTrack != null) {
        final trackKey = _trackCacheKey(_selectedTrack!);
        await _loadSummaryFromCache(
          trackKey: trackKey,
          allowFallback: !_userSelectedTrack,
        );
      }
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo generar la transcripción. Puede no estar disponible.\n$error';
        if (_summaryRequested) {
          if (_summary == null || _summary!.isEmpty) {
            _summaryError = 'No se pudo generar el resumen porque falló la transcripción.';
          }
          _loadingSummary = false;
          _summaryRequested = false;
        }
      });
      _log('transcript: error $error');
    } finally {
      if (mounted) {
        setState(() {
          _loadingTranscript = false;
        });
      }
    }
  }

  Future<void> _configureTts() async {
    final settings = await _aiSettingsStore.load();
    final voiceName = settings.narratorVoiceName;
    final voiceLocale = settings.narratorVoiceLocale;
    if (voiceLocale.isNotEmpty) {
      await _tts.setLanguage(voiceLocale);
    } else {
      await _tts.setLanguage('es-ES');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    if (voiceName.isNotEmpty && voiceLocale.isNotEmpty) {
      try {
        await _tts.setVoice({'name': voiceName, 'locale': voiceLocale});
      } catch (_) {}
    }
    _tts.setProgressHandler((text, start, end, _) {
      if (!mounted) return;
      if (!_ttsPlaying || _ttsTarget == _TtsTarget.none) {
        return;
      }
      String? targetText;
      if (_ttsTarget == _TtsTarget.intro) {
        targetText = _summaryIntro;
      } else if (_ttsTarget == _TtsTarget.main) {
        targetText = _summaryMain;
      } else {
        targetText = _ttsSpeechText;
      }
      if (targetText == null || targetText.isEmpty) return;
      var baseOffset = 0;
      if (_ttsSequenceActive &&
          _ttsTarget == _TtsTarget.main &&
          _ttsChunkText.isNotEmpty) {
        baseOffset = _ttsChunkOffset;
      } else if (_ttsSpeechText.isNotEmpty && text != _ttsSpeechText) {
        if (_ttsSpeechText.endsWith(text)) {
          baseOffset = _ttsSpeechText.length - text.length;
        } else {
          final index = _ttsSpeechText.indexOf(text);
          if (index >= 0) {
            baseOffset = index;
          } else {
            return;
          }
        }
      }
      final targetLen = targetText.length;
      final safeStart = start.clamp(0, text.length);
      final safeEnd = end.clamp(0, text.length);
      final progressIndex =
          _ttsTarget == _TtsTarget.main ? safeStart : safeEnd;
      final speechLen =
          (_ttsTarget == _TtsTarget.main && _ttsSpeechText.isNotEmpty)
              ? _ttsSpeechText.length
              : targetLen;
      final speechEnd = (baseOffset + progressIndex).clamp(0, speechLen);
      final highlightStart = (baseOffset + safeStart).clamp(0, targetLen);
      final highlightEnd = speechEnd.clamp(0, targetLen);
      setState(() {
        _ttsHighlightStart = highlightStart;
        if (_ttsTarget == _TtsTarget.intro) {
          _ttsIntroHighlightEnd = highlightEnd > _ttsIntroHighlightEnd
              ? highlightEnd
              : _ttsIntroHighlightEnd;
        } else if (_ttsTarget == _TtsTarget.main) {
          _ttsMainHighlightEnd = highlightEnd > _ttsMainHighlightEnd
              ? highlightEnd
              : _ttsMainHighlightEnd;
          if (_ttsQuestionsStartOffset > 0 &&
              _ttsQuestionRanges.isNotEmpty) {
            final relativeEnd = speechEnd - _ttsQuestionsStartOffset;
            _ttsQuestionsFromMainActive = relativeEnd > 0;
            if (relativeEnd > 0) {
              final updated = List<int>.from(_ttsQuestionHighlightEnds);
              for (var i = 0; i < _ttsQuestionRanges.length; i++) {
                final range = _ttsQuestionRanges[i];
                if (relativeEnd <= range.start) {
                  continue;
                }
                final clamped =
                    (relativeEnd.clamp(range.start, range.end)) - range.start;
                if (i < updated.length && clamped > updated[i]) {
                  updated[i] = clamped;
                }
              }
              _ttsQuestionHighlightEnds = updated;
            }
          } else {
            _ttsQuestionsFromMainActive = false;
          }
        } else if (_ttsTarget == _TtsTarget.questions) {
          final relativeEnd = highlightEnd - _ttsQuestionsPrefixLength;
          if (relativeEnd <= 0) return;
          final updated = List<int>.from(_ttsQuestionHighlightEnds);
          for (var i = 0; i < _ttsQuestionRanges.length; i++) {
            final range = _ttsQuestionRanges[i];
            if (relativeEnd <= range.start) {
              continue;
            }
            final clamped =
                (relativeEnd.clamp(range.start, range.end)) - range.start;
            if (i < updated.length && clamped > updated[i]) {
              updated[i] = clamped;
            }
          }
          _ttsQuestionHighlightEnds = updated;
        }
      });
    });
    _tts.setStartHandler(() {
      if (!mounted) return;
      setState(() {
        _ttsPlaying = true;
        _ttsPaused = false;
      });
    });
    _tts.setPauseHandler(() {
      if (!mounted) return;
      setState(() {
        _ttsPaused = true;
      });
    });
    _tts.setContinueHandler(() {
      if (!mounted) return;
      setState(() {
        _ttsPaused = false;
      });
    });
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      if (_ttsSequenceActive && _ttsQueue.isNotEmpty) {
        if (_ttsQueueIndex + 1 < _ttsQueue.length) {
          _ttsQueueIndex += 1;
          _speakNextChunk();
          return;
        }
        _resetTtsQueue();
      }
      setState(() {
        _ttsPlaying = false;
        _ttsPaused = false;
        _ttsTarget = _TtsTarget.none;
        _ttsHighlightStart = 0;
        _ttsMainHighlightEnd = 0;
        _ttsIntroHighlightEnd = 0;
        _ttsQuestionsText = '';
        _ttsQuestionsPrefixLength = 0;
        _ttsQuestionRanges = const [];
        _ttsQuestionHighlightEnds = const [];
        _ttsSpeechText = '';
      });
    });
    _tts.setErrorHandler((_) {
      if (!mounted) return;
      _resetTtsQueue();
      setState(() {
        _ttsPlaying = false;
        _ttsPaused = false;
        _ttsTarget = _TtsTarget.none;
        _ttsHighlightStart = 0;
        _ttsMainHighlightEnd = 0;
        _ttsIntroHighlightEnd = 0;
        _ttsQuestionsText = '';
        _ttsQuestionsPrefixLength = 0;
        _ttsQuestionRanges = const [];
        _ttsQuestionHighlightEnds = const [];
        _ttsSpeechText = '';
      });
    });
    if (mounted) {
      setState(() {
        _ttsReady = true;
      });
    }
  }

  Future<void> _loadSummaryFromCache({
    required String trackKey,
    bool allowFallback = true,
  }) async {
    final settings = await _aiSettingsStore.load();
    if (!mounted) return;
    final summaryKey =
        '${settings.provider}:${settings.model}:${widget.video.id}:$trackKey';
    final cachedSummary = await _summaryCache.get(summaryKey);
    if (!mounted) return;
    if (cachedSummary != null && cachedSummary.isNotEmpty) {
      _applySummary(cachedSummary);
      _log(
        'summary: cache hit key=$summaryKey len=${cachedSummary.length}',
      );
      return;
    }
    if (allowFallback) {
      final fallbackKey =
          '${settings.provider}:${settings.model}:${widget.video.id}';
      final fallbackSummary = await _summaryCache.get(fallbackKey);
      if (!mounted) return;
      if (fallbackSummary != null && fallbackSummary.isNotEmpty) {
        _applySummary(fallbackSummary);
        _log(
          'summary: cache hit (video) key=$fallbackKey len=${fallbackSummary.length}',
        );
        return;
      }
      _log(
        'summary: cache miss (video) key=$fallbackKey',
      );
    }
    _applySummary(null);
    _log('summary: cache miss key=$summaryKey');
  }

  Future<void> _loadSummaryFromVideoCache() async {
    if (_summary != null && _summary!.isNotEmpty) return;
    if (_userSelectedTrack) return;
    final settings = await _aiSettingsStore.load();
    if (!mounted) return;
    final summaryKey =
        '${settings.provider}:${settings.model}:${widget.video.id}';
    final cachedSummary = await _summaryCache.get(summaryKey);
    if (!mounted) return;
    if (cachedSummary != null && cachedSummary.isNotEmpty) {
      _applySummary(cachedSummary);
    }
    _log(cachedSummary == null
        ? 'summary: cache miss (video) key=$summaryKey'
        : 'summary: cache hit (video) key=$summaryKey len=${cachedSummary.length}');
  }

  Future<void> _requestSummaryGeneration() async {
    if (_loadingSummary) return;
    setState(() {
      _summaryRequested = true;
      _summaryError = null;
      _summary = null;
      _summaryIntro = null;
      _summaryMain = null;
      _summaryQuestions = const [];
      _summaryMainExpanded = false;
      _loadingSummary = true;
      _activeTab = _SummaryTab.summary;
    });
    _log('summary: generate requested');
    await _maybeGenerateSummary();
  }

  Future<void> _maybeGenerateSummary() async {
    if (!_summaryRequested || _loadingTranscript || _loadingTracks) return;
    _summaryInFlight = true;
    try {
      if (_selectedTrack == null) {
        _log('summary: waiting for transcript');
        await _ensureTranscriptLoaded();
        return;
      }

      final text = _transcript ?? '';
      if (text.isEmpty) {
        if (_error == null) {
          await _ensureTranscriptLoaded();
          return;
        }
        if (mounted) {
          setState(() {
            _summaryError = 'No hay texto para resumir.';
            _loadingSummary = false;
            _summaryRequested = false;
          });
        }
        return;
      }

      final settings = await _aiSettingsStore.load();
      if (settings.apiKey.isEmpty) {
        if (mounted) {
          setState(() {
            _summaryError = 'Configura una clave API en el perfil.';
            _loadingSummary = false;
            _summaryRequested = false;
          });
        }
        return;
      }
      if (settings.model.isEmpty) {
        if (mounted) {
          setState(() {
            _summaryError = 'Selecciona un modelo en el perfil.';
            _loadingSummary = false;
            _summaryRequested = false;
          });
        }
        return;
      }

      final trackKey = _trackCacheKey(_selectedTrack!);
      final summaryKey = '${settings.provider}:${settings.model}:${widget.video.id}:$trackKey';
      final cachedSummary = await _summaryCache.get(summaryKey);
      if (cachedSummary != null && cachedSummary.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loadingSummary = false;
            _summaryRequested = false;
          });
          _applySummary(cachedSummary);
        }
        _log('summary: cache hit key=$summaryKey');
        return;
      }
      final fallbackKey =
          '${settings.provider}:${settings.model}:${widget.video.id}';
      final fallbackSummary = await _summaryCache.get(fallbackKey);
      if (fallbackSummary != null && fallbackSummary.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loadingSummary = false;
            _summaryRequested = false;
          });
          _applySummary(fallbackSummary);
        }
        _log(
          'summary: cache hit (video) key=$fallbackKey len=${fallbackSummary.length}',
        );
        return;
      }

      _log('summary: calling provider=${settings.provider} model=${settings.model}');
      final summary = await _aiSummaryService.summarize(provider: settings.provider, model: settings.model, apiKey: settings.apiKey, transcript: text, title: widget.video.title, channel: widget.video.channelTitle);
      if (summary.isNotEmpty) {
        await _summaryCache.set(summaryKey, summary, _cacheTtl);
        await _summaryCache.set(fallbackKey, summary, _cacheTtl);
        _log('summary: cached key=$summaryKey len=${summary.length}');
      }
      if (mounted) {
        setState(() {
          _loadingSummary = false;
          _summaryRequested = false;
        });
        _applySummary(summary);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _summaryError = 'No se pudo generar el resumen.\n$error';
          _loadingSummary = false;
          _summaryRequested = false;
        });
      }
      _log('summary: error $error');
    } finally {
      _summaryInFlight = false;
      if (_disposePending) {
        _disposeAiService();
      }
    }
  }

  void _applySummary(String? raw) {
    if (!mounted) return;
    String? intro;
    String? main;
    var questions = <String>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final introRaw = decoded['resumen_inicial'];
        final mainRaw = decoded['contenido_principal'];
        final questionsRaw = decoded['preguntas'];
        if (introRaw is String) {
          intro = introRaw.trim();
        }
        if (mainRaw is String) {
          main = mainRaw.trim();
        }
        if (questionsRaw is List) {
          questions = questionsRaw.whereType<String>().map((q) => q.trim()).where((q) => q.isNotEmpty).toList();
        }
      } catch (_) {
        // Ignore parse errors.
      }
    }
    _resetTtsQueue();
    setState(() {
      if (raw != null && raw.trim().isNotEmpty) {
        _summaryError = null;
      }
      _summary = raw;
      _summaryIntro = intro;
      _summaryMain = main;
      _summaryQuestions = questions;
      _summaryMainExpanded = false;
      _ttsTarget = _TtsTarget.none;
      _ttsPaused = false;
      _ttsHighlightStart = 0;
      _ttsMainHighlightEnd = 0;
      _ttsIntroHighlightEnd = 0;
      _ttsQuestionsText = '';
      _ttsQuestionsPrefixLength = 0;
      _ttsQuestionRanges = const [];
      _ttsQuestionHighlightEnds = const [];
      _ttsSpeechText = '';
    });
  }

  _MainSpeech _buildMainSpeech() {
    final main = _summaryMain?.trim() ?? '';
    if (main.isEmpty) {
      return const _MainSpeech(
        text: '',
        questionsOffset: 0,
        questionRanges: <_QuestionRange>[],
      );
    }
    final buffer = StringBuffer(main);
    final questions = _summaryQuestions.take(3).toList();
    if (questions.isNotEmpty) {
      final lastChar = main.isNotEmpty ? main[main.length - 1] : '';
      if (lastChar != '.' && lastChar != '!' && lastChar != '?') {
        buffer.write('.');
      }
      const prefix = ' Te dejo algunas preguntas para reflexionar: ';
      buffer.write(prefix);
      final questionsOffset = buffer.length;
      final questionsSpeech = _buildQuestionsSpeech();
      buffer.write(questionsSpeech.questionText);
      return _MainSpeech(
        text: buffer.toString(),
        questionsOffset: questionsOffset,
        questionRanges: questionsSpeech.ranges,
      );
    }
    return _MainSpeech(
      text: buffer.toString(),
      questionsOffset: 0,
      questionRanges: const <_QuestionRange>[],
    );
  }

  void _resetTtsQueueOnly() {
    _ttsQueue = const [];
    _ttsQueueIndex = 0;
    _ttsChunkOffset = 0;
    _ttsChunkText = '';
    _ttsSequenceActive = false;
  }

  void _resetTtsQueue() {
    _resetTtsQueueOnly();
    _ttsQuestionsStartOffset = 0;
    _ttsQuestionsFromMainActive = false;
  }

  List<_TtsChunk> _splitTtsText(String text) {
    if (text.isEmpty) return const [];
    final chunks = <_TtsChunk>[];
    var index = 0;
    final length = text.length;
    while (index < length) {
      while (index < length && text[index].trim().isEmpty) {
        index++;
      }
      if (index >= length) break;
      final maxEnd =
          (index + _ttsChunkLimit < length) ? index + _ttsChunkLimit : length;
      var breakPos = maxEnd;
      if (maxEnd < length) {
        final slice = text.substring(index, maxEnd);
        var matchIndex = slice.lastIndexOf(RegExp(r'[.!?]\s'));
        if (matchIndex >= 0) {
          breakPos = index + matchIndex + 1;
        } else {
          matchIndex = slice.lastIndexOf(RegExp(r'[,:;]\s'));
          if (matchIndex >= 0) {
            breakPos = index + matchIndex + 1;
          } else {
            matchIndex = slice.lastIndexOf(' ');
            if (matchIndex >= 0) {
              breakPos = index + matchIndex;
            }
          }
        }
      }
      if (breakPos <= index) {
        breakPos = maxEnd;
      }
      final chunkText = text.substring(index, breakPos);
      if (chunkText.trim().isNotEmpty) {
        chunks.add(_TtsChunk(chunkText, index));
      }
      index = breakPos;
    }
    return chunks;
  }

  Future<void> _speakNextChunk() async {
    if (_ttsQueueIndex >= _ttsQueue.length) return;
    final chunk = _ttsQueue[_ttsQueueIndex];
    _ttsChunkOffset = chunk.offset;
    _ttsChunkText = chunk.text;
    await _tts.speak(chunk.text);
  }

  Future<void> _startTtsSequence(String speechText) async {
    _resetTtsQueueOnly();
    final chunks = _splitTtsText(speechText);
    if (chunks.length <= 1) {
      await _tts.speak(speechText);
      return;
    }
    _ttsQueue = chunks;
    _ttsQueueIndex = 0;
    _ttsSequenceActive = true;
    await _speakNextChunk();
  }

  _QuestionsSpeech _buildQuestionsSpeech() {
    final questions = _summaryQuestions.take(3).toList();
    if (questions.isEmpty) {
      return const _QuestionsSpeech(
        speechText: '',
        prefixLength: 0,
        questionText: '',
        ranges: <_QuestionRange>[],
      );
    }
    final questionRanges = <_QuestionRange>[];
    final questionsBuffer = StringBuffer();
    var offset = 0;
    for (var i = 0; i < questions.length; i++) {
      if (questionsBuffer.isNotEmpty) {
        questionsBuffer.write('. ');
        offset += 2;
      }
      final text = 'Pregunta ${i + 1}: ${questions[i]}';
      final start = offset;
      questionsBuffer.write(text);
      offset += text.length;
      questionRanges.add(_QuestionRange(start, offset));
    }
    final questionsText = questionsBuffer.toString();
    return _QuestionsSpeech(
      speechText: questionsText,
      prefixLength: 0,
      questionText: questionsText,
      ranges: questionRanges,
    );
  }

  Future<void> _toggleTts() async {
    if (!_ttsReady || _summaryMain == null || _summaryMain!.isEmpty) return;
    if (_ttsPlaying &&
        _ttsTarget == _TtsTarget.main &&
        !_ttsPaused) {
      await _tts.pause();
      return;
    }
    if (_ttsPlaying && _ttsTarget != _TtsTarget.main) {
      await _stopTts();
    }
    _resetTtsQueue();
    final mainSpeech = _buildMainSpeech();
    final speechText =
        _ttsSpeechText.isNotEmpty ? _ttsSpeechText : mainSpeech.text;
    if (speechText.isEmpty) return;
    if (mounted) {
      setState(() {
        _ttsTarget = _TtsTarget.main;
        _ttsSpeechText = speechText;
        _ttsQuestionsStartOffset = mainSpeech.questionsOffset;
        _ttsQuestionsFromMainActive = false;
        _ttsQuestionRanges = mainSpeech.questionRanges;
        _ttsQuestionHighlightEnds =
            List<int>.filled(mainSpeech.questionRanges.length, 0);
        if (!_ttsPaused) {
          _ttsHighlightStart = 0;
          _ttsMainHighlightEnd = 0;
          _ttsIntroHighlightEnd = 0;
        }
      });
    }
    await _startTtsSequence(speechText);
  }

  Future<void> _toggleIntroTts() async {
    if (!_ttsReady || _summaryIntro == null || _summaryIntro!.isEmpty) {
      return;
    }
    if (_ttsPlaying &&
        _ttsTarget == _TtsTarget.intro &&
        !_ttsPaused) {
      await _tts.pause();
      return;
    }
    if (_ttsPlaying && _ttsTarget != _TtsTarget.intro) {
      await _stopTts();
    }
    _resetTtsQueue();
    final speechText = _ttsSpeechText.isNotEmpty
        ? _ttsSpeechText
        : _summaryIntro!.trim();
    if (speechText.isEmpty) return;
    if (mounted) {
      setState(() {
        _ttsTarget = _TtsTarget.intro;
        _ttsSpeechText = speechText;
        if (!_ttsPaused) {
          _ttsHighlightStart = 0;
          _ttsIntroHighlightEnd = 0;
          _ttsMainHighlightEnd = 0;
        }
      });
    }
    await _tts.speak(speechText);
  }

  Future<void> _toggleQuestionsTts() async {
    if (!_ttsReady || _summaryQuestions.isEmpty) {
      return;
    }
    if (_ttsPlaying &&
        _ttsTarget == _TtsTarget.questions &&
        !_ttsPaused) {
      await _tts.pause();
      return;
    }
    if (_ttsPlaying && _ttsTarget != _TtsTarget.questions) {
      await _stopTts();
    }
    _resetTtsQueue();
    final speech = _buildQuestionsSpeech();
    final speechText =
        _ttsSpeechText.isNotEmpty ? _ttsSpeechText : speech.speechText;
    if (speechText.isEmpty) return;
    if (mounted) {
      setState(() {
        _ttsTarget = _TtsTarget.questions;
        _ttsSpeechText = speechText;
        _ttsQuestionsText = speech.questionText;
        _ttsQuestionsPrefixLength = speech.prefixLength;
        _ttsQuestionRanges = speech.ranges;
        if (!_ttsPaused) {
          _ttsHighlightStart = 0;
          _ttsQuestionHighlightEnds =
              List<int>.filled(speech.ranges.length, 0);
        }
      });
    }
    await _tts.speak(speechText);
  }

  Future<void> _stopTts() async {
    if (!_ttsReady) return;
    await _tts.stop();
    if (!mounted) return;
    _resetTtsQueue();
    setState(() {
      _ttsPlaying = false;
      _ttsPaused = false;
      _ttsTarget = _TtsTarget.none;
      _ttsHighlightStart = 0;
      _ttsMainHighlightEnd = 0;
      _ttsIntroHighlightEnd = 0;
      _ttsQuestionsText = '';
      _ttsQuestionsPrefixLength = 0;
      _ttsQuestionRanges = const [];
      _ttsQuestionHighlightEnds = const [];
      _ttsSpeechText = '';
    });
  }

  Future<void> _openQuestion(String question) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) return;
    final summaryContext = (_summaryMain ?? '').trim();
    final prompt = summaryContext.isNotEmpty
        ? 'Contexto: $summaryContext\nAhora me gustaría reflexionar sobre: $trimmedQuestion'
        : trimmedQuestion;
    final uri = Uri.parse(
      'https://chatgpt.com/?prompt=${Uri.encodeComponent(prompt)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace.')));
    }
  }

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[VideoDetail] $message');
  }

  TextSpan _buildHighlightedSpan({
    required String text,
    TextStyle? style,
    required int highlightEnd,
    required bool active,
  }) {
    if (!active || highlightEnd <= 0 || text.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final end = highlightEnd.clamp(0, text.length);
    if (end <= 0) {
      return TextSpan(text: text, style: style);
    }
    final highlightStyle =
        (style ?? const TextStyle()).copyWith(color: const Color(0xFFFA1021));
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, end), style: highlightStyle),
        if (end < text.length) TextSpan(text: text.substring(end)),
      ],
    );
  }

  Widget _buildHighlightedText({
    required String text,
    TextStyle? style,
    required int highlightEnd,
    required bool active,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    final span = _buildHighlightedSpan(
      text: text,
      style: style,
      highlightEnd: highlightEnd,
      active: active,
    );
    return Text.rich(
      span,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  void _copyText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    Clipboard.setData(ClipboardData(text: trimmed));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado al portapapeles.')));
  }

  void _copyTranscript() {
    final text = (_transcript != null && _transcript!.isNotEmpty)
        ? _transcript!
        : (_error != null && _error!.isNotEmpty)
        ? _error!
        : null;
    if (text == null || text.isEmpty) return;
    _copyText(text);
  }

  void _copySummary() {
    final text = (_summary != null && _summary!.isNotEmpty)
        ? _summary!
        : (_summaryError != null && _summaryError!.isNotEmpty)
        ? _summaryError!
        : null;
    if (text == null || text.isEmpty) return;
    _copyText(text);
  }

  YouTubeCaptionTrack? _pickDefaultTrack(List<YouTubeCaptionTrack> tracks) {
    if (tracks.isEmpty) return null;
    final spanish = tracks.firstWhere((track) => track.language.toLowerCase().startsWith('es'), orElse: () => tracks.first);
    return spanish;
  }

  String _formatTrackLabel(YouTubeCaptionTrack track) {
    final autoLabel = track.isAutoGenerated ? ' (auto)' : '';
    final name = track.name.isNotEmpty ? ' • ${track.name}' : '';
    return '${track.language}$autoLabel$name';
  }

  String _trackCacheKey(YouTubeCaptionTrack track) {
    final language = track.language.trim().toLowerCase();
    final kind = track.isAutoGenerated ? 'asr' : 'manual';
    final name = track.name.trim().toLowerCase();
    final raw = '$language|$kind|$name';
    return stableHash(raw);
  }

  String? _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final total = seconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$minutes:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final playerWidth = screenSize.width;
    final targetHeight = playerWidth * 9 / 16;
    final playerHeight = targetHeight > screenSize.height ? screenSize.height : targetHeight;
    final playerAspectRatio = playerWidth / playerHeight;
    final hasStructuredSummary = _summaryMain != null && _summaryMain!.isNotEmpty;
    final showGenerateSummary = !hasStructuredSummary && _summaryError == null;
    final introActive = _ttsTarget == _TtsTarget.intro && _ttsPlaying;
    final mainActive = _ttsTarget == _TtsTarget.main && _ttsPlaying;
    final questionsActive =
        _ttsTarget == _TtsTarget.questions && _ttsPlaying;
    final questionsHighlightActive = _ttsPlaying &&
        (_ttsTarget == _TtsTarget.questions ||
            (_ttsTarget == _TtsTarget.main && _ttsQuestionsFromMainActive));
    final visibleQuestions = _summaryQuestions.take(3).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.video.channelTitle)),
      body: ListView(
        padding: EdgeInsets.only(bottom: mediaQuery.padding.bottom),
        children: [
          SizedBox(
            width: double.infinity,
            height: playerHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _playerController != null
                      ? YoutubePlayer(controller: _playerController!, showVideoProgressIndicator: true, aspectRatio: playerAspectRatio, onReady: _handlePlayerReady)
                      : Container(alignment: Alignment.center, color: Colors.black12, child: const Text('Vídeo no disponible')),
                ),
                if (_formatDuration(widget.video.durationSeconds) != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xB8000000), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        _formatDuration(widget.video.durationSeconds)!,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_playerStuck) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'El reproductor no terminó de cargar. '
                            'Prueba recargar el vídeo.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _useHybridComposition = true;
                            });
                            _initPlayer();
                          },
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    InkWell(
                      onTap: _openChannelVideos,
                      borderRadius: BorderRadius.circular(28),
                      child: ChannelAvatar(
                        name: widget.video.channelTitle,
                        imageUrl: _channelAvatarUrl,
                        size: 44,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.video.channelTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(widget.video.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fullWidth = constraints.maxWidth;
                    const borderWidth = 1.0;
                    final buttonWidth = (fullWidth - borderWidth * 3) / 2;
                    final summaryLoading = _loadingSummary;
                    final transcriptLoading = _loadingTranscript || _loadingTracks;
                    return ToggleButtons(
                      isSelected: [_activeTab == _SummaryTab.summary, _activeTab == _SummaryTab.transcript],
                      onPressed: (index) {
                        setState(() {
                          _activeTab = index == 0 ? _SummaryTab.summary : _SummaryTab.transcript;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      borderWidth: borderWidth,
                      constraints: BoxConstraints.tightFor(width: buttonWidth, height: 40),
                      children: [
                        _TabLabel(text: 'Resumen IA', loading: summaryLoading),
                        _TabLabel(text: 'Transcripción', loading: transcriptLoading),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (_activeTab == _SummaryTab.summary) ...[
                  Row(
                    children: [
                      Text('Resumen IA', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton.icon(onPressed: (_summary != null && _summary!.isNotEmpty) || (_summaryError != null && _summaryError!.isNotEmpty) ? _copySummary : null, icon: const Icon(Icons.copy), label: const Text('Copy All')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_summaryIntro != null && _summaryIntro!.isNotEmpty) ...[
                    Row(
                      children: [
                        Text('Resumen inicial', style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _ttsReady ? _toggleIntroTts : null,
                              icon: Icon(
                                introActive && !_ttsPaused
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              tooltip: introActive
                                  ? (_ttsPaused
                                      ? 'Reanudar audio'
                                      : 'Pausar audio')
                                  : 'Reproducir audio',
                            ),
                            IconButton(
                              onPressed:
                                  _ttsReady && introActive ? _stopTts : null,
                              icon: const Icon(Icons.stop),
                              tooltip: 'Detener audio',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onLongPress: () => _copyText(_summaryIntro!),
                      child: _buildHighlightedText(
                        text: _summaryIntro!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        highlightEnd: _ttsIntroHighlightEnd,
                        active: introActive,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_summaryMain != null && _summaryMain!.isNotEmpty) ...[
                    Row(
                      children: [
                        Text('Contenido principal', style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _ttsReady ? _toggleTts : null,
                              icon: Icon(
                                mainActive && !_ttsPaused
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              tooltip: mainActive
                                  ? (_ttsPaused
                                      ? 'Reanudar audio'
                                      : 'Pausar audio')
                                  : 'Reproducir audio',
                            ),
                            IconButton(
                              onPressed:
                                  _ttsReady && mainActive ? _stopTts : null,
                              icon: const Icon(Icons.stop),
                              tooltip: 'Detener audio',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textStyle =
                            Theme.of(context).textTheme.bodyMedium;
                        final span = _buildHighlightedSpan(
                          text: _summaryMain!,
                          style: textStyle,
                          highlightEnd: _ttsMainHighlightEnd,
                          active: mainActive,
                        );
                        final painter = TextPainter(
                          text: span,
                          maxLines: _summaryPreviewLines,
                          textDirection: Directionality.of(context),
                        )..layout(maxWidth: constraints.maxWidth);
                        final exceeds = painter.didExceedMaxLines;
                        final showFull = _summaryMainExpanded || mainActive;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onLongPress: () => _copyText(_summaryMain!),
                              child: _buildHighlightedText(
                                text: _summaryMain!,
                                style: textStyle,
                                highlightEnd: _ttsMainHighlightEnd,
                                active: mainActive,
                                maxLines:
                                    showFull ? null : _summaryPreviewLines,
                                overflow: showFull
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                              ),
                            ),
                            if (exceeds || _summaryMainExpanded)
                              TextButton(
                                onPressed: mainActive
                                    ? null
                                    : () {
                                        setState(() {
                                          _summaryMainExpanded =
                                              !_summaryMainExpanded;
                                        });
                                      },
                                child: Text(_summaryMainExpanded
                                    ? 'Ver menos'
                                    : 'Ver más'),
                              ),
                          ],
                        );
                      },
                    ),
                  ] else if (_summary != null && _summaryIntro == null && _summaryMain == null)
                    SelectableText(_summary!)
                  else if (_summaryError != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_summaryError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _loadingSummary ? null : _requestSummaryGeneration, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
                      ],
                    )
                  else if (showGenerateSummary)
                    OutlinedButton.icon(
                      onPressed: _loadingSummary ? null : _requestSummaryGeneration,
                      icon: _loadingSummary ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high),
                      label: Text(_loadingSummary ? 'Generando...' : 'Generar'),
                    ),
                  if (_summaryQuestions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Preguntas para profundizar',
                            style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _ttsReady ? _toggleQuestionsTts : null,
                              icon: Icon(
                                questionsActive && !_ttsPaused
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              tooltip: questionsActive
                                  ? (_ttsPaused
                                      ? 'Reanudar audio'
                                      : 'Pausar audio')
                                  : 'Reproducir audio',
                            ),
                            IconButton(
                              onPressed: _ttsReady && questionsActive
                                  ? _stopTts
                                  : null,
                              icon: const Icon(Icons.stop),
                              tooltip: 'Detener audio',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < visibleQuestions.length; i++)
                      TextButton(
                        onPressed: () => _openQuestion(visibleQuestions[i]),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildHighlightedText(
                            text: visibleQuestions[i],
                            highlightEnd: (questionsHighlightActive &&
                                    i < _ttsQuestionHighlightEnds.length)
                                ? _ttsQuestionHighlightEnds[i]
                                : 0,
                            active: questionsHighlightActive,
                          ),
                        ),
                      ),
                  ],
                ] else ...[
                  Row(
                    children: [
                      Text('Transcripción', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton.icon(onPressed: (_transcript != null && _transcript!.isNotEmpty) || (_error != null && _error!.isNotEmpty) ? _copyTranscript : null, icon: const Icon(Icons.copy), label: const Text('Copy All')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_tracks.isNotEmpty) ...[
                    DropdownButtonFormField<YouTubeCaptionTrack>(
                      value: _selectedTrack,
                      items: _tracks.map((track) => DropdownMenuItem(value: track, child: Text(_formatTrackLabel(track)))).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _resetTtsQueue();
                        setState(() {
                          _activeTab = _SummaryTab.transcript;
                          _selectedTrack = value;
                          _userSelectedTrack = true;
                          _transcript = null;
                          _transcriptExpanded = false;
                          _summary = null;
                          _summaryError = null;
                          _error = null;
                          _summaryRequested = false;
                          _loadingSummary = false;
                          _summaryIntro = null;
                          _summaryMain = null;
                          _summaryQuestions = const [];
                          _summaryMainExpanded = false;
                          _ttsPlaying = false;
                          _ttsPaused = false;
                          _ttsTarget = _TtsTarget.none;
                          _ttsHighlightStart = 0;
                          _ttsMainHighlightEnd = 0;
                          _ttsIntroHighlightEnd = 0;
                          _ttsSpeechText = '';
                        });
                        _tts.stop();
                        _ensureTranscriptLoaded();
                      },
                      decoration: const InputDecoration(labelText: 'Pista de subtítulos', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_transcript != null)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final style = Theme.of(context).textTheme.bodyMedium;
                        final fullText = _transcript!;
                        final painter = TextPainter(
                          text: TextSpan(text: fullText, style: style),
                          maxLines: 10,
                          textDirection: TextDirection.ltr,
                        )..layout(maxWidth: constraints.maxWidth);
                        var endOffset = painter.getPositionForOffset(Offset(constraints.maxWidth, painter.height)).offset;
                        if (endOffset < 0) endOffset = 0;
                        if (endOffset > fullText.length) {
                          endOffset = fullText.length;
                        }
                        final exceeds = endOffset < fullText.length;
                        final previewText = exceeds ? '${fullText.substring(0, endOffset).trimRight()}…' : fullText;
                        final displayText = _transcriptExpanded || !exceeds ? fullText : previewText;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(displayText),
                            if (exceeds || _transcriptExpanded)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _transcriptExpanded = !_transcriptExpanded;
                                  });
                                },
                                child: Text(_transcriptExpanded ? 'Ver menos' : 'Ver más'),
                              ),
                          ],
                        );
                      },
                    )
                  else if (_error != null)
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                  else if (_loadingTranscript)
                    const Text('Cargando transcripción...')
                  else
                    const Text('No hay transcripción disponible.'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _SummaryTab { summary, transcript }

enum _TtsTarget { none, intro, main, questions }

class _QuestionRange {
  const _QuestionRange(this.start, this.end);

  final int start;
  final int end;
}

class _QuestionsSpeech {
  const _QuestionsSpeech({
    required this.speechText,
    required this.prefixLength,
    required this.questionText,
    required this.ranges,
  });

  final String speechText;
  final int prefixLength;
  final String questionText;
  final List<_QuestionRange> ranges;
}

class _MainSpeech {
  const _MainSpeech({
    required this.text,
    required this.questionsOffset,
    required this.questionRanges,
  });

  final String text;
  final int questionsOffset;
  final List<_QuestionRange> questionRanges;
}

class _TtsChunk {
  const _TtsChunk(this.text, this.offset);

  final String text;
  final int offset;
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, required this.loading});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[Text(text)];
    if (loading) {
      children.addAll([const SizedBox(width: 8), const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))]);
    }
    return Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
