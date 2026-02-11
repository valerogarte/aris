import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/youtube_caption_track.dart';

class YouTubeTranscriptService {
  YouTubeTranscriptService({http.Client? client})
      : _client = client ?? http.Client();

  static const String _watchUrl = 'https://www.youtube.com/watch?v=';
  static const String _innertubeUrl =
      'https://www.youtube.com/youtubei/v1/player?key=';
  static const Map<String, dynamic> _innertubeContext = {
    'client': {
      'clientName': 'ANDROID',
      'clientVersion': '20.10.38',
    },
  };
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 11; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Map<String, String> _cookies = {};

  Future<List<YouTubeCaptionTrack>> fetchCaptionTracks(String videoId) async {
    if (videoId.isEmpty) return const [];
    final html = await _fetchVideoHtml(videoId);
    final apiKey = _extractInnertubeApiKey(html, videoId);
    final data = await _fetchInnertubeData(videoId, apiKey);
    return _extractCaptionTracks(data, videoId);
  }

  Future<String> downloadCaption(String baseUrl) async {
    if (baseUrl.isEmpty) return '';
    final response = await _client.get(
      Uri.parse(baseUrl),
      headers: _defaultHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'YouTube error (${response.statusCode}): '
        'no se pudo descargar la transcripción.',
      );
    }
    return _parseTranscriptXml(response.body);
  }

  void dispose() {
    _client.close();
  }

  Future<String> _fetchVideoHtml(String videoId) async {
    var html = await _fetchHtml(videoId);
    if (html.contains('action="https://consent.youtube.com/s"')) {
      _createConsentCookie(html, videoId);
      html = await _fetchHtml(videoId);
      if (html.contains('action="https://consent.youtube.com/s"')) {
        throw Exception(
          'No se pudo aceptar el consentimiento de cookies para el vídeo.',
        );
      }
    }
    return html;
  }

  Future<String> _fetchHtml(String videoId) async {
    final response = await _client.get(
      Uri.parse('$_watchUrl$videoId'),
      headers: _defaultHeaders(),
    );
    if (response.statusCode == 429) {
      throw Exception('Solicitud bloqueada por YouTube (demasiadas peticiones).');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo cargar la página del vídeo (HTTP ${response.statusCode}).',
      );
    }
    return _decodeHtmlEntities(response.body);
  }

  Map<String, String> _defaultHeaders() {
    final headers = <String, String>{
      'User-Agent': _userAgent,
      'Accept-Language': 'en-US,en;q=0.9',
    };
    final cookie = _cookieHeader();
    if (cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  String _cookieHeader() {
    if (_cookies.isEmpty) return '';
    return _cookies.entries.map((entry) {
      return '${entry.key}=${entry.value}';
    }).join('; ');
  }

  void _createConsentCookie(String html, String videoId) {
    final match = RegExp('name="v" value="(.*?)"').firstMatch(html);
    if (match == null || match.groupCount < 1) {
      throw Exception(
        'No se pudo crear la cookie de consentimiento para el vídeo.',
      );
    }
    _cookies['CONSENT'] = 'YES+${match.group(1)}';
  }

  String _extractInnertubeApiKey(String html, String videoId) {
    final match = RegExp(r'"INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)"')
        .firstMatch(html);
    if (match != null && match.groupCount == 1) {
      return match.group(1)!;
    }
    if (html.contains('class="g-recaptcha"')) {
      throw Exception('YouTube requiere verificación (captcha).');
    }
    throw Exception('No se pudo extraer la clave de YouTube.');
  }

  Future<Map<String, dynamic>> _fetchInnertubeData(
    String videoId,
    String apiKey,
  ) async {
    final response = await _client.post(
      Uri.parse('$_innertubeUrl$apiKey'),
      headers: {
        ..._defaultHeaders(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'context': _innertubeContext,
        'videoId': videoId,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'YouTube error (${response.statusCode}): '
        'no se pudo obtener metadata del vídeo.',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  List<YouTubeCaptionTrack> _extractCaptionTracks(
    Map<String, dynamic> data,
    String videoId,
  ) {
    final playability = _asMap(data['playabilityStatus']);
    final status = playability['status']?.toString();
    if (status != null && status != 'OK') {
      final reason = playability['reason']?.toString();
      final message = reason == null || reason.isEmpty
          ? 'Vídeo no disponible.'
          : 'Vídeo no disponible: $reason';
      throw Exception(message);
    }

    final captions = _asMap(data['captions']);
    final renderer = _asMap(captions['playerCaptionsTracklistRenderer']);
    final tracks = _asList(renderer['captionTracks']);
    if (tracks.isEmpty) {
      return const [];
    }

    return tracks
        .whereType<Map<String, dynamic>>()
        .map((track) {
          final baseUrl = _asString(track['baseUrl'])
              .replaceAll('&fmt=srv3', '')
              .replaceAll('&fmt=srv1', '');
          final languageCode = _asString(track['languageCode']);
          final name = _extractTrackName(track['name']);
          final kind = _asString(track['kind']).toLowerCase();
          return YouTubeCaptionTrack(
            id: baseUrl,
            language: languageCode.isEmpty ? 'und' : languageCode,
            name: name,
            isAutoGenerated: kind == 'asr',
          );
        })
        .where((track) => track.id.isNotEmpty)
        .toList();
  }

  String _extractTrackName(dynamic nameField) {
    if (nameField is Map<String, dynamic>) {
      final runs = nameField['runs'];
      if (runs is List && runs.isNotEmpty) {
        final first = runs.first;
        if (first is Map && first['text'] != null) {
          return first['text'].toString();
        }
      }
      final simple = nameField['simpleText'];
      if (simple != null) {
        return simple.toString();
      }
    }
    return '';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return const <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  String _parseTranscriptXml(String raw) {
    final regex = RegExp(r'<text[^>]*>(.*?)</text>', dotAll: true);
    final buffer = StringBuffer();
    for (final match in regex.allMatches(raw)) {
      var text = match.group(1) ?? '';
      if (text.isEmpty) continue;
      text = text
          .replaceAll('<br>', '\n')
          .replaceAll('<br/>', '\n')
          .replaceAll('<br />', '\n');
      text = text.replaceAll(RegExp(r'<[^>]+>'), '');
      text = _decodeHtmlEntities(text);
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      buffer.write(text);
      buffer.write(' ');
    }
    return buffer.toString().trim();
  }

  String _decodeHtmlEntities(String input) {
    var output = input;
    output = output.replaceAll('&amp;', '&');
    output = output.replaceAll('&lt;', '<');
    output = output.replaceAll('&gt;', '>');
    output = output.replaceAll('&quot;', '"');
    output = output.replaceAll('&#39;', "'");
    output = output.replaceAll('&nbsp;', ' ');
    output = output.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (match) => String.fromCharCode(
        int.parse(match.group(1)!, radix: 16),
      ),
    );
    output = output.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => String.fromCharCode(
        int.parse(match.group(1)!),
      ),
    );
    return output;
  }
}
