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
import '../storage/history_store.dart';
import '../services/ai_cost_tracker.dart';
import '../ui/channel_avatar.dart';
import 'channel_videos_screen.dart';

String formatRelativeTime(DateTime date) {
  final now = DateTime.now().toLocal();
  final target = date.toLocal();
  var diff = now.difference(target);
  if (diff.isNegative) {
    diff = Duration.zero;
  }
  final minutes = diff.inMinutes;
  if (minutes < 60) {
    if (minutes <= 1) return 'hace 1 minuto';
    return 'hace $minutes minutos';
  }
  final hours = diff.inHours;
  if (hours < 24) {
    if (hours == 1) return 'hace 1 hora';
    return 'hace $hours horas';
  }
  final days = diff.inDays;
  if (days < 7) {
    if (days == 1) return 'hace 1 día';
    return 'hace $days días';
  }
  if (days < 30) {
    final weeks = (days / 7).floor();
    if (weeks <= 1) return 'hace 1 semana';
    return 'hace $weeks semanas';
  }
  if (days < 365) {
    final months = (days / 30).floor();
    if (months <= 1) return 'hace 1 mes';
    return 'hace $months meses';
  }
  final years = (days / 365).floor();
  if (years <= 1) return 'hace 1 año';
  return 'hace $years años';
}

class VideoDetailScreen extends StatefulWidget {
  const VideoDetailScreen({super.key, required this.video, required this.accessToken, this.channelAvatarUrl = '', this.quotaTracker, this.aiCostTracker});

  final YouTubeVideo video;
  final String accessToken;
  final String channelAvatarUrl;
  final QuotaTracker? quotaTracker;
  final AiCostTracker? aiCostTracker;

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  static const Duration _cacheTtl = Duration(days: 365);
  static const int _summaryPreviewLines = 10;
  static const int _ttsChunkLimit = 1000;
  static final Map<String, Future<String?>> _summaryJobs = {};
  static final Map<String, Future<String?>> _summaryVideoJobs = {};

  late final YouTubeTranscriptService _transcripts;
  late final YouTubeApiService _api;
  final AiSettingsStore _aiSettingsStore = AiSettingsStore();
  late final ExpiringCacheStore _transcriptCache;
  late final ExpiringCacheStore _summaryCache;
  final ExpiringCacheStore _avatarCache = ExpiringCacheStore('channel_avatars');
  final HistoryStore _historyStore = HistoryStore();
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
  Future<String?>? _attachedSummaryFuture;
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
  bool _historyWatchedLogged = false;
  bool _historySummaryLogged = false;
  int _ttsQuestionsStartOffset = 0;
  bool _ttsQuestionsFromMainActive = false;
  int _ttsHighlightStart = 0;
  int _ttsMainHighlightEnd = 0;
  int _ttsIntroHighlightEnd = 0;
  String _ttsQuestionsText = '';
  int _ttsQuestionsPrefixLength = 0;
  List<_QuestionRange> _ttsQuestionRanges = const [];
  List<int> _ttsQuestionHighlightEnds = const [];
  _NormalizedText? _ttsNormalizedSpeech;
  String _aiModelLabel = '';
  String? _summaryIntro;
  String? _summaryMain;
  List<String> _summaryQuestions = const [];
  String _channelAvatarUrl = '';
  bool _loadingChannelAvatar = false;
  bool _summaryMainExpanded = false;

  @override
  void initState() {
    super.initState();
    _transcripts = YouTubeTranscriptService();
    _api = YouTubeApiService(accessToken: widget.accessToken, quotaTracker: widget.quotaTracker);
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
    _attachPendingSummaryJob();
  }

  @override
  void dispose() {
    _playerTimeout?.cancel();
    _playerController?.removeListener(_handlePlayerState);
    _playerController?.dispose();
    _transcripts.dispose();
    _api.dispose();
    _tts.stop();
    super.dispose();
  }

  void _initPlayer() {
    _playerTimeout?.cancel();
    _playerController?.removeListener(_handlePlayerState);
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
    _playerController!.addListener(_handlePlayerState);
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

  void _handlePlayerState() {
    final controller = _playerController;
    if (controller == null || _historyWatchedLogged) return;
    final state = controller.value.playerState;
    if (state == PlayerState.playing) {
      _historyWatchedLogged = true;
      _historyStore.markWatched(widget.video);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró el canal.')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelVideosScreen(accessToken: widget.accessToken, channelId: channelId, channelTitle: widget.video.channelTitle, channelAvatarUrl: _channelAvatarUrl, quotaTracker: widget.quotaTracker, aiCostTracker: widget.aiCostTracker),
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

  Future<void> _ensureTranscriptLoaded({bool force = false}) async {
    if (_loadingTranscript || widget.video.id.isEmpty) return;
    setState(() {
      _loadingTranscript = true;
      _error = null;
    });
    _log('transcript: start');

    try {
      await _loadSummaryFromVideoCache();
      if (!force && (_summary ?? '').trim().isNotEmpty) {
        _log('transcript: skipped (summary cached)');
        return;
      }
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
      await _loadSummaryFromCache(trackKey: trackKey, allowFallback: !_userSelectedTrack);
      if (!force && (_summary ?? '').trim().isNotEmpty) {
        _log('transcript: skipped (summary cached)');
        return;
      }

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
    } catch (error) {
      if (!mounted) return;
      if (_selectedTrack != null) {
        final trackKey = _trackCacheKey(_selectedTrack!);
        await _loadSummaryFromCache(trackKey: trackKey, allowFallback: !_userSelectedTrack);
      }
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo generar la transcripción. Puede no estar disponible.\n$error';
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
    final modelLabel = settings.model.trim();
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
      if (_ttsSequenceActive && _ttsTarget == _TtsTarget.main && _ttsChunkText.isNotEmpty) {
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
      final progressIndex = safeStart;
      final speechLen = (_ttsTarget == _TtsTarget.main && _ttsSpeechText.isNotEmpty) ? _ttsSpeechText.length : targetLen;
      final speechEnd = (baseOffset + progressIndex).clamp(0, speechLen);
      final mappedEnd = _mapNormalizedSpeechEnd(speechEnd);
      final highlightStart = (baseOffset + safeStart).clamp(0, targetLen);
      final highlightEnd = mappedEnd.clamp(0, targetLen);
      setState(() {
        _ttsHighlightStart = highlightStart;
        if (_ttsTarget == _TtsTarget.intro) {
          _ttsIntroHighlightEnd = highlightEnd > _ttsIntroHighlightEnd ? highlightEnd : _ttsIntroHighlightEnd;
        } else if (_ttsTarget == _TtsTarget.main) {
          _ttsMainHighlightEnd = highlightEnd > _ttsMainHighlightEnd ? highlightEnd : _ttsMainHighlightEnd;
          if (_ttsQuestionsStartOffset > 0 && _ttsQuestionRanges.isNotEmpty) {
            final relativeEnd = mappedEnd - _ttsQuestionsStartOffset;
            _ttsQuestionsFromMainActive = relativeEnd > 0;
            if (relativeEnd > 0) {
              final updated = List<int>.from(_ttsQuestionHighlightEnds);
              for (var i = 0; i < _ttsQuestionRanges.length; i++) {
                final range = _ttsQuestionRanges[i];
                if (relativeEnd <= range.start) {
                  continue;
                }
                final clamped = (relativeEnd.clamp(range.start, range.end)) - range.start;
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
            final clamped = (relativeEnd.clamp(range.start, range.end)) - range.start;
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
        _ttsNormalizedSpeech = null;
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
        _ttsNormalizedSpeech = null;
      });
    });
    if (mounted) {
      setState(() {
        _ttsReady = true;
        _aiModelLabel = modelLabel;
      });
    }
  }

  Future<void> _loadSummaryFromCache({required String trackKey, bool allowFallback = true}) async {
    final settings = await _aiSettingsStore.load();
    if (!mounted) return;
    final summaryKey = '${settings.provider}:${settings.model}:${widget.video.id}:$trackKey';
    final cachedSummary = await _summaryCache.get(summaryKey);
    if (!mounted) return;
    if (cachedSummary != null && cachedSummary.isNotEmpty) {
      _applySummary(cachedSummary);
      _log('summary: cache hit key=$summaryKey len=${cachedSummary.length}');
      return;
    }
    if (allowFallback) {
      final fallbackKey = '${settings.provider}:${settings.model}:${widget.video.id}';
      final fallbackSummary = await _summaryCache.get(fallbackKey);
      if (!mounted) return;
      if (fallbackSummary != null && fallbackSummary.isNotEmpty) {
        _applySummary(fallbackSummary);
        _log('summary: cache hit (video) key=$fallbackKey len=${fallbackSummary.length}');
        return;
      }
      _log('summary: cache miss (video) key=$fallbackKey');
    }
    final inFlight = _summaryJobs[summaryKey];
    if (inFlight != null) {
      setState(() {
        _loadingSummary = true;
        _summaryRequested = true;
        _summaryError = null;
      });
      _applySummary(null);
      _trackSummaryFuture(inFlight);
      _log('summary: in-flight key=$summaryKey');
      return;
    }
    _applySummary(null);
    _log('summary: cache miss key=$summaryKey');
  }

  Future<void> _loadSummaryFromVideoCache() async {
    if (_summary != null && _summary!.isNotEmpty) return;
    if (_userSelectedTrack) return;
    final settings = await _aiSettingsStore.load();
    if (!mounted) return;
    final summaryKey = '${settings.provider}:${settings.model}:${widget.video.id}';
    final cachedSummary = await _summaryCache.get(summaryKey);
    if (!mounted) return;
    if (cachedSummary != null && cachedSummary.isNotEmpty) {
      _applySummary(cachedSummary);
    }
    _log(cachedSummary == null ? 'summary: cache miss (video) key=$summaryKey' : 'summary: cache hit (video) key=$summaryKey len=${cachedSummary.length}');
  }

  String _formatSummaryError(Object error) {
    final raw = error.toString();
    const prefix = 'Exception: ';
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length);
    }
    return raw;
  }

  Future<void> _attachPendingSummaryJob() async {
    if (_loadingSummary || _summaryRequested) return;
    if ((_summary ?? '').trim().isNotEmpty) return;
    final settings = await _aiSettingsStore.load();
    if (!mounted) return;
    final fallbackKey = '${settings.provider}:${settings.model}:${widget.video.id}';
    final future = _summaryVideoJobs[fallbackKey];
    if (future == null) return;
    setState(() {
      _loadingSummary = true;
      _summaryRequested = true;
      _summaryError = null;
    });
    _trackSummaryFuture(future);
  }

  void _trackSummaryFuture(Future<String?> future) {
    if (_attachedSummaryFuture == future) return;
    _attachedSummaryFuture = future;
    future
        .then((summary) {
          if (!mounted || _attachedSummaryFuture != future) return;
          _attachedSummaryFuture = null;
          if (summary != null && summary.isNotEmpty) {
            setState(() {
              _loadingSummary = false;
              _summaryRequested = false;
            });
            _applySummary(summary);
          } else {
            setState(() {
              _summaryError = 'No se pudo generar el resumen.';
              _loadingSummary = false;
              _summaryRequested = false;
            });
          }
        })
        .catchError((error) {
          _log('summary: error $error');
          if (!mounted || _attachedSummaryFuture != future) return;
          _attachedSummaryFuture = null;
          setState(() {
            _summaryError = 'No se pudo generar el resumen.\n${_formatSummaryError(error)}';
            _loadingSummary = false;
            _summaryRequested = false;
          });
        });
  }

  Future<String?> _ensureSummaryCached({YouTubeCaptionTrack? preferredTrack, String? transcript}) async {
    if (widget.video.id.isEmpty) {
      throw Exception('No se encontró el vídeo.');
    }
    final settings = await _aiSettingsStore.load();
    if (settings.apiKey.isEmpty) {
      throw Exception('Configura una clave API en el perfil.');
    }
    if (settings.model.isEmpty) {
      throw Exception('Selecciona un modelo en el perfil.');
    }

    final fallbackKey = '${settings.provider}:${settings.model}:${widget.video.id}';
    var track = preferredTrack;
    if (track == null || track.id.isEmpty) {
      final transcriptService = YouTubeTranscriptService();
      try {
        final tracks = await transcriptService.fetchCaptionTracks(widget.video.id);
        track = _pickDefaultTrack(tracks);
      } catch (error) {
        final fallbackSummary = await _summaryCache.get(fallbackKey);
        if (fallbackSummary != null && fallbackSummary.isNotEmpty) {
          _log('summary: cache hit (video) key=$fallbackKey len=${fallbackSummary.length}');
          return fallbackSummary;
        }
        rethrow;
      } finally {
        transcriptService.dispose();
      }
    }
    if (track == null) {
      final fallbackSummary = await _summaryCache.get(fallbackKey);
      if (fallbackSummary != null && fallbackSummary.isNotEmpty) {
        _log('summary: cache hit (video) key=$fallbackKey len=${fallbackSummary.length}');
        return fallbackSummary;
      }
      throw Exception('No hay transcripciones disponibles para este vídeo.');
    }

    final trackKey = _trackCacheKey(track);
    final summaryKey = '${settings.provider}:${settings.model}:${widget.video.id}:$trackKey';
    final cachedSummary = await _summaryCache.get(summaryKey);
    if (cachedSummary != null && cachedSummary.isNotEmpty) {
      _log('summary: cache hit key=$summaryKey len=${cachedSummary.length}');
      return cachedSummary;
    }
    final fallbackSummary = await _summaryCache.get(fallbackKey);
    if (fallbackSummary != null && fallbackSummary.isNotEmpty) {
      _log('summary: cache hit (video) key=$fallbackKey len=${fallbackSummary.length}');
      return fallbackSummary;
    }

    final existing = _summaryJobs[summaryKey];
    if (existing != null) {
      _summaryVideoJobs[fallbackKey] = existing;
      _log('summary: waiting existing job key=$summaryKey');
      return await existing;
    }

    final future = _runSummaryJob(settings: settings, track: track, trackKey: trackKey, summaryKey: summaryKey, fallbackKey: fallbackKey, transcript: transcript);
    _summaryJobs[summaryKey] = future;
    _summaryVideoJobs[fallbackKey] = future;
    try {
      return await future;
    } finally {
      if (_summaryJobs[summaryKey] == future) {
        _summaryJobs.remove(summaryKey);
      }
      if (_summaryVideoJobs[fallbackKey] == future) {
        _summaryVideoJobs.remove(fallbackKey);
      }
    }
  }

  Future<String?> _runSummaryJob({required AiProviderSettings settings, required YouTubeCaptionTrack track, required String trackKey, required String summaryKey, required String fallbackKey, String? transcript}) async {
    final transcriptService = YouTubeTranscriptService();
    final aiService = AiSummaryService(costTracker: widget.aiCostTracker);
    try {
      final transcriptKey = '${widget.video.id}:$trackKey';
      var text = transcript?.trim() ?? '';
      String? cachedTranscript;
      if (text.isEmpty) {
        cachedTranscript = await _transcriptCache.get(transcriptKey);
        text = cachedTranscript?.trim() ?? '';
      }
      if (text.isEmpty) {
        text = (await transcriptService.downloadCaption(track.id)).trim();
      }
      if (text.isEmpty) {
        throw Exception('No hay texto para resumir.');
      }
      if ((cachedTranscript == null || cachedTranscript.isEmpty) && text.isNotEmpty) {
        await _transcriptCache.set(transcriptKey, text, _cacheTtl);
        _log('transcript: cached key=$transcriptKey');
      }

      _log('summary: calling provider=${settings.provider} model=${settings.model}');
      final summary = await aiService.summarize(provider: settings.provider, model: settings.model, apiKey: settings.apiKey, transcript: text, title: widget.video.title, channel: widget.video.channelTitle);
      if (summary.isNotEmpty) {
        await _summaryCache.set(summaryKey, summary, _cacheTtl);
        await _summaryCache.set(fallbackKey, summary, _cacheTtl);
        _log('summary: cached key=$summaryKey len=${summary.length}');
        return summary;
      }
      throw Exception('No se pudo generar el resumen.');
    } finally {
      transcriptService.dispose();
      aiService.dispose();
    }
  }

  Future<void> _requestSummaryGeneration() async {
    if (_loadingSummary) return;
    if (!_historySummaryLogged) {
      _historySummaryLogged = true;
      _historyStore.markSummaryRequested(widget.video);
    }
    setState(() {
      _summaryRequested = true;
      _summaryError = null;
      _summary = null;
      _summaryIntro = null;
      _summaryMain = null;
      _summaryQuestions = const [];
      _summaryMainExpanded = false;
      _loadingSummary = true;
    });
    _log('summary: generate requested');
    final future = _ensureSummaryCached(preferredTrack: _selectedTrack, transcript: _transcript);
    _trackSummaryFuture(future);
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
      return const _MainSpeech(text: '', questionsOffset: 0, questionRanges: <_QuestionRange>[]);
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
      return _MainSpeech(text: buffer.toString(), questionsOffset: questionsOffset, questionRanges: questionsSpeech.ranges);
    }
    return _MainSpeech(text: buffer.toString(), questionsOffset: 0, questionRanges: const <_QuestionRange>[]);
  }

  void _resetTtsQueueOnly() {
    _ttsQueue = const [];
    _ttsQueueIndex = 0;
    _ttsChunkOffset = 0;
    _ttsChunkText = '';
    _ttsSequenceActive = false;
    _ttsNormalizedSpeech = null;
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
      final maxEnd = (index + _ttsChunkLimit < length) ? index + _ttsChunkLimit : length;
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
      return const _QuestionsSpeech(speechText: '', prefixLength: 0, questionText: '', ranges: <_QuestionRange>[]);
    }
    final questionRanges = <_QuestionRange>[];
    final questionsBuffer = StringBuffer();
    var offset = 0;
    for (var i = 0; i < questions.length; i++) {
      if (questionsBuffer.isNotEmpty) {
        questionsBuffer.write('. ');
        offset += 2;
      }
      final prefix = 'Pregunta ${i + 1}: ';
      final text = '$prefix${questions[i]}';
      final start = offset + prefix.length;
      questionsBuffer.write(text);
      offset += text.length;
      questionRanges.add(_QuestionRange(start, offset));
    }
    final questionsText = questionsBuffer.toString();
    return _QuestionsSpeech(speechText: questionsText, prefixLength: 0, questionText: questionsText, ranges: questionRanges);
  }

  Future<void> _toggleTts() async {
    if (!_ttsReady || _summaryMain == null || _summaryMain!.isEmpty) return;
    if (_ttsPlaying && _ttsTarget == _TtsTarget.main && !_ttsPaused) {
      await _tts.pause();
      return;
    }
    if (_ttsPlaying && _ttsTarget != _TtsTarget.main) {
      await _stopTts();
    }
    _resetTtsQueue();
    final mainSpeech = _buildMainSpeech();
    final originalSpeech = mainSpeech.text;
    if (originalSpeech.isEmpty) return;
    if (mounted) {
      setState(() {
        _ttsTarget = _TtsTarget.main;
        _applyNormalizedSpeech(originalSpeech);
        _ttsQuestionsStartOffset = mainSpeech.questionsOffset;
        _ttsQuestionsFromMainActive = false;
        _ttsQuestionRanges = mainSpeech.questionRanges;
        _ttsQuestionHighlightEnds = List<int>.filled(mainSpeech.questionRanges.length, 0);
        if (!_ttsPaused) {
          _ttsHighlightStart = 0;
          _ttsMainHighlightEnd = 0;
          _ttsIntroHighlightEnd = 0;
        }
      });
    }
    await _startTtsSequence(_ttsSpeechText);
  }

  Future<void> _toggleIntroTts() async {
    if (!_ttsReady || _summaryIntro == null || _summaryIntro!.isEmpty) {
      return;
    }
    if (_ttsPlaying && _ttsTarget == _TtsTarget.intro && !_ttsPaused) {
      await _tts.pause();
      return;
    }
    if (_ttsPlaying && _ttsTarget != _TtsTarget.intro) {
      await _stopTts();
    }
    _resetTtsQueue();
    final originalSpeech = _summaryIntro!.trim();
    if (originalSpeech.isEmpty) return;
    if (mounted) {
      setState(() {
        _ttsTarget = _TtsTarget.intro;
        _applyNormalizedSpeech(originalSpeech);
        if (!_ttsPaused) {
          _ttsHighlightStart = 0;
          _ttsIntroHighlightEnd = 0;
          _ttsMainHighlightEnd = 0;
        }
      });
    }
    await _tts.speak(_ttsSpeechText);
  }

  Future<void> _toggleQuestionsTts() async {
    if (!_ttsReady || _summaryQuestions.isEmpty) {
      return;
    }
    if (_ttsPlaying && _ttsTarget == _TtsTarget.questions && !_ttsPaused) {
      await _tts.pause();
      return;
    }
    if (_ttsPlaying && _ttsTarget != _TtsTarget.questions) {
      await _stopTts();
    }
    _resetTtsQueue();
    final speech = _buildQuestionsSpeech();
    final originalSpeech = speech.speechText;
    if (originalSpeech.isEmpty) return;
    if (mounted) {
      setState(() {
        _ttsTarget = _TtsTarget.questions;
        _applyNormalizedSpeech(originalSpeech);
        _ttsQuestionsText = speech.questionText;
        _ttsQuestionsPrefixLength = speech.prefixLength;
        _ttsQuestionRanges = speech.ranges;
        if (!_ttsPaused) {
          _ttsHighlightStart = 0;
          _ttsQuestionHighlightEnds = List<int>.filled(speech.ranges.length, 0);
        }
      });
    }
    await _tts.speak(_ttsSpeechText);
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
      _ttsNormalizedSpeech = null;
    });
  }

  void _applyNormalizedSpeech(String original) {
    final normalized = _normalizeSpeech(original);
    _ttsSpeechText = normalized.text;
    _ttsNormalizedSpeech = normalized;
  }

  _NormalizedText _normalizeSpeech(String input) {
    if (input.isEmpty) {
      return const _NormalizedText('', <int>[]);
    }
    final buffer = StringBuffer();
    final map = <int>[];
    var inWhitespace = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char.trim().isEmpty) {
        if (buffer.isEmpty) {
          continue;
        }
        if (!inWhitespace) {
          buffer.write(' ');
          map.add(i);
          inWhitespace = true;
        }
        continue;
      }
      inWhitespace = false;
      buffer.write(char);
      map.add(i);
    }
    var normalized = buffer.toString();
    if (normalized.endsWith(' ') && map.isNotEmpty) {
      normalized = normalized.substring(0, normalized.length - 1);
      map.removeLast();
    }
    return _NormalizedText(normalized, map);
  }

  int _mapNormalizedSpeechEnd(int normalizedEnd) {
    final normalized = _ttsNormalizedSpeech;
    if (normalized == null || normalized.map.isEmpty) {
      return normalizedEnd;
    }
    if (normalizedEnd <= 0) return 0;
    final index = (normalizedEnd - 1).clamp(0, normalized.map.length - 1);
    return normalized.map[index] + 1;
  }

  Future<void> _openQuestion(String question) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) return;
    final summaryContext = (_summaryMain ?? '').trim();
    final prompt = summaryContext.isNotEmpty ? 'Contexto: $summaryContext\nAhora me gustaría reflexionar sobre: $trimmedQuestion' : trimmedQuestion;
    final uri = Uri.parse('https://chatgpt.com/?prompt=${Uri.encodeComponent(prompt)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace.')));
    }
  }

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[VideoDetail] $message');
  }

  TextSpan _buildHighlightedSpan({required String text, TextStyle? style, required int highlightEnd, required bool active}) {
    if (!active || highlightEnd <= 0 || text.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final end = highlightEnd.clamp(0, text.length);
    if (end <= 0) {
      return TextSpan(text: text, style: style);
    }
    final highlightStyle = (style ?? const TextStyle()).copyWith(color: const Color(0xFFFA1021));
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, end), style: highlightStyle),
        if (end < text.length) TextSpan(text: text.substring(end)),
      ],
    );
  }

  Widget _buildHighlightedText({required String text, TextStyle? style, required int highlightEnd, required bool active, int? maxLines, TextOverflow? overflow}) {
    final span = _buildHighlightedSpan(text: text, style: style, highlightEnd: highlightEnd, active: active);
    return Text.rich(span, maxLines: maxLines, overflow: overflow);
  }

  void _copyText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    Clipboard.setData(ClipboardData(text: trimmed));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado al portapapeles.')));
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

  String _trackCacheKey(YouTubeCaptionTrack track) {
    final language = track.language.trim().toLowerCase();
    final kind = track.isAutoGenerated ? 'asr' : 'manual';
    final name = track.name.trim().toLowerCase();
    final raw = '$language|$kind|$name';
    return stableHash(raw);
  }

  Widget _buildSummarySection(BuildContext context) {
    final hasIntro = _summaryIntro != null && _summaryIntro!.isNotEmpty;
    final hasMain = _summaryMain != null && _summaryMain!.isNotEmpty;
    final hasRaw = _summary != null && _summary!.trim().isNotEmpty;
    final summaryAvailable = hasRaw || hasIntro || hasMain;
    final showGeneratingSummary = _loadingSummary && !summaryAvailable && _summaryError == null;
    final showGenerateSummary = !summaryAvailable && _summaryError == null && !_loadingSummary;
    final preparingContext = !summaryAvailable && (_loadingTranscript || _loadingTracks) && _summaryError == null;
    final hasTranscriptError = _error != null && _error!.isNotEmpty;
    final canGenerate = !hasTranscriptError;
    final introActive = _ttsTarget == _TtsTarget.intro && _ttsPlaying;
    final mainActive = _ttsTarget == _TtsTarget.main && _ttsPlaying;
    final questionsActive = _ttsTarget == _TtsTarget.questions && _ttsPlaying;
    final questionsHighlightActive = _ttsPlaying && (_ttsTarget == _TtsTarget.questions || (_ttsTarget == _TtsTarget.main && _ttsQuestionsFromMainActive));
    final visibleQuestions = _summaryQuestions.take(3).toList();

    Widget summaryBlock({required String title, required Widget child, Widget? trailing}) {
      final titleStyle = Theme.of(context).textTheme.titleSmall;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: titleStyle?.copyWith(fontWeight: FontWeight.w600) ?? const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1C1C1C), Color(0xFF0F0F0F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 28,
                decoration: BoxDecoration(color: const Color(0xFFFA1021), borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Resumen IA', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(onPressed: summaryAvailable || (_summaryError != null && _summaryError!.isNotEmpty) ? _copySummary : null, icon: const Icon(Icons.copy), label: const Text('Copy All')),
            ],
          ),
          const SizedBox(height: 12),
          if (showGeneratingSummary)
            Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text('Se está generando el resumen', style: Theme.of(context).textTheme.bodyMedium)),
              ],
            )
          else if (showGenerateSummary) ...[
            Text('Genera un resumen claro, ideas clave y preguntas de seguimiento.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canGenerate ? _requestSummaryGeneration : null,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFA1021), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Generar'),
              ),
            ),
            if (_aiModelLabel.isNotEmpty) ...[const SizedBox(height: 6), Text('Modelo: $_aiModelLabel', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54))],
            if (preparingContext) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Preparando la transcripción para dar contexto a la IA.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ),
                ],
              ),
            ] else if (_transcript != null && _transcript!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFFFA1021), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Transcripción generada.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ),
                ],
              ),
            ] else if (hasTranscriptError) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ] else if (_summaryError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_summaryError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _loadingSummary ? null : _requestSummaryGeneration, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
                ],
              ),
            ),
          ] else ...[
            if (hasIntro) ...[
              summaryBlock(
                title: 'Resumen inicial',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(onPressed: _ttsReady ? _toggleIntroTts : null, icon: Icon(introActive && !_ttsPaused ? Icons.pause : Icons.play_arrow), tooltip: introActive ? (_ttsPaused ? 'Reanudar audio' : 'Pausar audio') : 'Reproducir audio'),
                    IconButton(onPressed: _ttsReady && introActive ? _stopTts : null, icon: const Icon(Icons.stop), tooltip: 'Detener audio'),
                  ],
                ),
                child: GestureDetector(
                  onLongPress: () => _copyText(_summaryIntro!),
                  child: _buildHighlightedText(text: _summaryIntro!, style: Theme.of(context).textTheme.bodyMedium, highlightEnd: _ttsIntroHighlightEnd, active: introActive),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (hasMain) ...[
              summaryBlock(
                title: 'Contenido principal',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(onPressed: _ttsReady ? _toggleTts : null, icon: Icon(mainActive && !_ttsPaused ? Icons.pause : Icons.play_arrow), tooltip: mainActive ? (_ttsPaused ? 'Reanudar audio' : 'Pausar audio') : 'Reproducir audio'),
                    IconButton(onPressed: _ttsReady && mainActive ? _stopTts : null, icon: const Icon(Icons.stop), tooltip: 'Detener audio'),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textStyle = Theme.of(context).textTheme.bodyMedium;
                    final span = _buildHighlightedSpan(text: _summaryMain!, style: textStyle, highlightEnd: _ttsMainHighlightEnd, active: mainActive);
                    final painter = TextPainter(text: span, maxLines: _summaryPreviewLines, textDirection: Directionality.of(context))..layout(maxWidth: constraints.maxWidth);
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
                            maxLines: showFull ? null : _summaryPreviewLines,
                            overflow: showFull ? TextOverflow.visible : TextOverflow.ellipsis,
                          ),
                        ),
                        if (exceeds || _summaryMainExpanded)
                          TextButton(
                            onPressed: mainActive
                                ? null
                                : () {
                                    setState(() {
                                      _summaryMainExpanded = !_summaryMainExpanded;
                                    });
                                  },
                            child: Text(_summaryMainExpanded ? 'Ver menos' : 'Ver más'),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!hasMain && !hasIntro && hasRaw) ...[summaryBlock(title: 'Resumen completo', child: SelectableText(_summary!)), if (_summaryQuestions.isNotEmpty) const SizedBox(height: 12)],
            if (_summaryQuestions.isNotEmpty) ...[
              summaryBlock(
                title: 'Preguntas para profundizar',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _ttsReady ? _toggleQuestionsTts : null,
                      icon: Icon(questionsActive && !_ttsPaused ? Icons.pause : Icons.play_arrow),
                      tooltip: questionsActive ? (_ttsPaused ? 'Reanudar audio' : 'Pausar audio') : 'Reproducir audio',
                    ),
                    IconButton(onPressed: _ttsReady && questionsActive ? _stopTts : null, icon: const Icon(Icons.stop), tooltip: 'Detener audio'),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < visibleQuestions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => _openQuestion(visibleQuestions[i]),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                        child: _buildHighlightedText(text: visibleQuestions[i], highlightEnd: (questionsHighlightActive && i < _ttsQuestionHighlightEnds.length) ? _ttsQuestionHighlightEnds[i] : 0, active: questionsHighlightActive),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(color: Colors.white70);
    final hasSummaryIndicator = (_summary != null && _summary!.trim().isNotEmpty) || (_summaryMain != null && _summaryMain!.isNotEmpty) || (_summaryIntro != null && _summaryIntro!.isNotEmpty) || _summaryQuestions.isNotEmpty;
    final screenSize = mediaQuery.size;
    final playerWidth = screenSize.width;
    final targetHeight = playerWidth * 9 / 16;
    final playerHeight = targetHeight > screenSize.height ? screenSize.height : targetHeight;
    final playerAspectRatio = playerWidth / playerHeight;

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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          InkWell(
                            onTap: _openChannelVideos,
                            customBorder: const CircleBorder(),
                            child: ChannelAvatar(name: widget.video.channelTitle, imageUrl: _channelAvatarUrl),
                          ),
                          const SizedBox(height: 6),
                          if (hasSummaryIndicator) const Icon(Icons.auto_fix_high, color: Color(0xFFFA1021), size: 16),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.video.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white, height: 1.3),
                            ),
                            const SizedBox(height: 6),
                            Text('${widget.video.channelTitle} • ${formatRelativeTime(widget.video.publishedAt)}', style: subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                    ],
                  ),
                ),
                _buildSummarySection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _TtsTarget { none, intro, main, questions }

class _QuestionRange {
  const _QuestionRange(this.start, this.end);

  final int start;
  final int end;
}

class _NormalizedText {
  const _NormalizedText(this.text, this.map);

  final String text;
  final List<int> map;
}

class _QuestionsSpeech {
  const _QuestionsSpeech({required this.speechText, required this.prefixLength, required this.questionText, required this.ranges});

  final String speechText;
  final int prefixLength;
  final String questionText;
  final List<_QuestionRange> ranges;
}

class _MainSpeech {
  const _MainSpeech({required this.text, required this.questionsOffset, required this.questionRanges});

  final String text;
  final int questionsOffset;
  final List<_QuestionRange> questionRanges;
}

class _TtsChunk {
  const _TtsChunk(this.text, this.offset);

  final String text;
  final int offset;
}
