import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/youtube_caption_track.dart';
import '../models/youtube_subscription.dart';
import '../models/youtube_video.dart';
import 'quota_tracker.dart';

class YouTubeChannelVideosPage {
  const YouTubeChannelVideosPage({
    required this.videos,
    required this.nextPageToken,
    required this.uploadsPlaylistId,
  });

  final List<YouTubeVideo> videos;
  final String? nextPageToken;
  final String? uploadsPlaylistId;
}

class YouTubeApiService {
  YouTubeApiService({
    required this.accessToken,
    this.quotaTracker,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const int _unitsDefault = 1;
  static const int _unitsCaptionsList = 50;
  static const int _unitsCaptionsDownload = 200;
  static const int _unitsVideosList = 1;

  final String accessToken;
  final http.Client _client;
  final QuotaTracker? quotaTracker;

  Future<List<YouTubeVideo>> fetchRecentVideosFromSubscriptions({
    int maxSubscriptions = 20,
  }) async {
    final subscriptions = await _get(
      'subscriptions',
      {
        'part': 'snippet',
        'mine': 'true',
        'maxResults': '50',
      },
      units: _unitsDefault,
      label: 'subscriptions.list',
    );

    final items = (subscriptions['items'] as List?) ?? const [];
    if (items.isEmpty) return [];

    final channelIds = <String>[];
    for (final item in items) {
      final snippet = (item as Map<String, dynamic>)['snippet']
          as Map<String, dynamic>?;
      final resource = snippet?['resourceId'] as Map<String, dynamic>?;
      final channelId = resource?['channelId'] as String?;
      if (channelId != null && channelId.isNotEmpty) {
        channelIds.add(channelId);
      }
    }

    if (channelIds.isEmpty) return [];

    final limitedChannels = channelIds.take(maxSubscriptions).toList();
    return _fetchLatestVideosForChannels(limitedChannels);
  }

  Future<List<YouTubeVideo>> fetchRecentVideosForChannels(
    List<String> channelIds, {
    int? maxChannels,
  }) async {
    final seen = <String>{};
    final ordered = <String>[];
    for (final rawId in channelIds) {
      final id = rawId.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) {
        ordered.add(id);
      }
    }

    if (ordered.isEmpty) return [];

    final limited = (maxChannels != null && maxChannels > 0)
        ? ordered.take(maxChannels).toList()
        : ordered;
    return _fetchLatestVideosForChannels(limited);
  }

  Future<Map<String, String>> fetchChannelThumbnails(
    List<String> channelIds,
  ) async {
    final result = <String, String>{};
    final ids = channelIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return result;

    const chunkSize = 50;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        math.min(i + chunkSize, ids.length),
      );
      final data = await _get(
        'channels',
        {
          'part': 'snippet',
          'id': chunk.join(','),
        },
        units: _unitsDefault,
        label: 'channels.list',
      );

      final items = (data['items'] as List?) ?? const [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as String?;
        final snippet = map['snippet'] as Map<String, dynamic>?;
        final thumbnails = snippet?['thumbnails'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final url = _pickThumbnail(thumbnails);
        if (id != null && id.isNotEmpty && url.isNotEmpty) {
          result[id] = url;
        }
      }
    }

    return result;
  }

  Future<YouTubeChannelVideosPage> fetchChannelUploads({
    required String channelId,
    String? uploadsPlaylistId,
    String? pageToken,
    int maxResults = 20,
  }) async {
    final trimmedId = channelId.trim();
    if (trimmedId.isEmpty) {
      return const YouTubeChannelVideosPage(
        videos: <YouTubeVideo>[],
        nextPageToken: null,
        uploadsPlaylistId: null,
      );
    }

    var playlistId = uploadsPlaylistId?.trim();
    if (playlistId == null || playlistId.isEmpty) {
      final data = await _get(
        'channels',
        {
          'part': 'contentDetails',
          'id': trimmedId,
        },
        units: _unitsDefault,
        label: 'channels.list',
      );
      final items = (data['items'] as List?) ?? const [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final details = map['contentDetails'] as Map<String, dynamic>?;
        final related =
            details?['relatedPlaylists'] as Map<String, dynamic>?;
        final uploads = related?['uploads'] as String?;
        if (uploads != null && uploads.isNotEmpty) {
          playlistId = uploads;
          break;
        }
      }
    }

    if (playlistId == null || playlistId.isEmpty) {
      return const YouTubeChannelVideosPage(
        videos: <YouTubeVideo>[],
        nextPageToken: null,
        uploadsPlaylistId: null,
      );
    }

    final params = <String, String>{
      'part': 'snippet',
      'playlistId': playlistId,
      'maxResults': maxResults.clamp(1, 50).toString(),
    };
    if (pageToken != null && pageToken.isNotEmpty) {
      params['pageToken'] = pageToken;
    }

    final data = await _get(
      'playlistItems',
      params,
      units: _unitsDefault,
      label: 'playlistItems.list',
    );

    final items = (data['items'] as List?) ?? const [];
    final ids = <String>[];
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final snippet = map['snippet'] as Map<String, dynamic>?;
      final resource = snippet?['resourceId'] as Map<String, dynamic>?;
      final id = resource?['videoId'] as String?;
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      }
    }
    final durations = await _fetchVideoDurations(ids);
    final now = DateTime.now().toUtc();
    final videos = <YouTubeVideo>[];
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final snippet = map['snippet'] as Map<String, dynamic>?;
      final resource = snippet?['resourceId'] as Map<String, dynamic>?;
      final id = resource?['videoId'] as String?;
      if (id == null || id.isEmpty) continue;
      final video =
          YouTubeVideo.fromPlaylistItem(map, durationSeconds: durations[id]);
      if (video.publishedAt.toUtc().isAfter(now)) {
        continue;
      }
      videos.add(video);
    }

    return YouTubeChannelVideosPage(
      videos: videos,
      nextPageToken: data['nextPageToken'] as String?,
      uploadsPlaylistId: playlistId,
    );
  }

  Future<List<YouTubeSubscription>> fetchSubscriptions() async {
    final subscriptions = <YouTubeSubscription>[];
    String? pageToken;

    do {
      final params = <String, String>{
        'part': 'snippet',
        'mine': 'true',
        'maxResults': '50',
      };
      if (pageToken != null && pageToken.isNotEmpty) {
        params['pageToken'] = pageToken;
      }

      final data = await _get(
        'subscriptions',
        params,
        units: _unitsDefault,
        label: 'subscriptions.list',
      );
      final items = (data['items'] as List?) ?? const [];
      for (final item in items) {
        subscriptions.add(
          YouTubeSubscription.fromSubscriptionItem(
            item as Map<String, dynamic>,
          ),
        );
      }

      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);

    return subscriptions;
  }

  Future<List<YouTubeCaptionTrack>> fetchCaptionTracks(String videoId) async {
    final data = await _get(
      'captions',
      {
        'part': 'snippet',
        'videoId': videoId,
      },
      units: _unitsCaptionsList,
      label: 'captions.list',
    );

    final items = (data['items'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(YouTubeCaptionTrack.fromCaptionItem)
        .where((track) => track.id.isNotEmpty)
        .toList();
  }

  Future<String> downloadCaption(String captionId) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/youtube/v3/captions/$captionId',
      {
        'tfmt': 'srt',
        'alt': 'media',
      },
    );
    final response = await _client.get(
      uri,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $accessToken',
        HttpHeaders.acceptHeader: 'application/json',
      },
    );

    await _addUnits(_unitsCaptionsDownload, label: 'captions.download');

    if (response.statusCode != 200) {
      final message = _extractErrorMessage(response.body);
      throw HttpException(
        'YouTube API error (${response.statusCode}): $message',
      );
    }

    return _stripSrt(response.body);
  }

  Future<YouTubeVideo?> _fetchLatestFromPlaylist(String playlistId) async {
    final data = await _get(
      'playlistItems',
      {
        'part': 'snippet',
        'playlistId': playlistId,
        'maxResults': '5',
      },
      units: _unitsDefault,
      label: 'playlistItems.list',
    );

    final items = (data['items'] as List?) ?? const [];
    if (items.isEmpty) return null;

    final candidateIds = <String>[];
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final snippet = map['snippet'] as Map<String, dynamic>?;
      final resource = snippet?['resourceId'] as Map<String, dynamic>?;
      final videoId = resource?['videoId'] as String?;
      if (videoId != null && videoId.isNotEmpty) {
        candidateIds.add(videoId);
      }
    }

    final durations = await _fetchVideoDurations(candidateIds);
    final now = DateTime.now().toUtc();
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final snippet = map['snippet'] as Map<String, dynamic>?;
      final resource = snippet?['resourceId'] as Map<String, dynamic>?;
      final videoId = resource?['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) continue;
      final publishedAtRaw = snippet?['publishedAt'] as String?;
      final publishedAt = publishedAtRaw != null
          ? DateTime.tryParse(publishedAtRaw)
          : null;
      if (publishedAt != null && publishedAt.toUtc().isAfter(now)) {
        continue; // skip scheduled/unpublished videos
      }
      final seconds = durations[videoId];
      if (seconds != null && seconds > 0 && seconds <= 60) {
        continue; // skip shorts
      }
      return YouTubeVideo.fromPlaylistItem(
        map,
        durationSeconds: seconds,
      );
    }

    return null;
  }

  Future<Map<String, int>> _fetchVideoDurations(
    List<String> videoIds,
  ) async {
    final result = <String, int>{};
    final ids = videoIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return result;

    const chunkSize = 50;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        math.min(i + chunkSize, ids.length),
      );
      final data = await _get(
        'videos',
        {
          'part': 'contentDetails',
          'id': chunk.join(','),
        },
        units: _unitsVideosList,
        label: 'videos.list',
      );
      final items = (data['items'] as List?) ?? const [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as String?;
        final details = map['contentDetails'] as Map<String, dynamic>?;
        final duration = details?['duration'] as String?;
        if (id == null || id.isEmpty || duration == null) continue;
        final seconds = _parseDurationSeconds(duration);
        if (seconds != null) {
          result[id] = seconds;
        }
      }
    }

    return result;
  }

  Future<List<YouTubeVideo>> _fetchLatestVideosForChannels(
    List<String> channelIds,
  ) async {
    if (channelIds.isEmpty) return [];

    final uploadPlaylists = <String>[];
    const chunkSize = 50;
    for (var i = 0; i < channelIds.length; i += chunkSize) {
      final chunk = channelIds.sublist(
        i,
        math.min(i + chunkSize, channelIds.length),
      );
      final channels = await _get(
        'channels',
        {
          'part': 'contentDetails',
          'id': chunk.join(','),
        },
        units: _unitsDefault,
        label: 'channels.list',
      );

      final channelItems = (channels['items'] as List?) ?? const [];
      for (final item in channelItems) {
        final map = item as Map<String, dynamic>;
        final details = map['contentDetails'] as Map<String, dynamic>?;
        final related = details?['relatedPlaylists'] as Map<String, dynamic>?;
        final uploads = related?['uploads'] as String?;
        if (uploads != null && uploads.isNotEmpty) {
          uploadPlaylists.add(uploads);
        }
      }
    }

    if (uploadPlaylists.isEmpty) return [];

    final futures = uploadPlaylists
        .map((playlistId) => _fetchLatestFromPlaylist(playlistId));
    final results = await Future.wait(futures);

    final now = DateTime.now().toUtc();
    final videos = results
        .whereType<YouTubeVideo>()
        .where((video) => !video.publishedAt.toUtc().isAfter(now))
        .toList();
    videos.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return videos;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params, {
    int units = _unitsDefault,
    String? label,
  }) async {
    final uri = Uri.https('www.googleapis.com', '/youtube/v3/$path', params);
    final response = await _client.get(
      uri,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $accessToken',
        HttpHeaders.acceptHeader: 'application/json',
      },
    );

    await _addUnits(units, label: label);

    if (response.statusCode != 200) {
      final message = _extractErrorMessage(response.body);
      throw HttpException(
        'YouTube API error (${response.statusCode}): $message',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _extractErrorMessage(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final error = data['error'] as Map<String, dynamic>?;
      final message = error?['message'] as String?;
      return message ?? body;
    } catch (_) {
      return body;
    }
  }

  String _stripSrt(String srt) {
    final lines = srt.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(trimmed)) continue;
      if (RegExp(r'^\d{2}:\d{2}:\d{2},\d{3}').hasMatch(trimmed)) continue;
      buffer.write(trimmed);
      buffer.write(' ');
    }
    return buffer.toString().trim();
  }

  int? _parseDurationSeconds(String isoDuration) {
    final match = RegExp(
      r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
    ).firstMatch(isoDuration);
    if (match == null) return null;
    final days = int.tryParse(match.group(1) ?? '') ?? 0;
    final hours = int.tryParse(match.group(2) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(3) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(4) ?? '') ?? 0;
    return seconds + minutes * 60 + hours * 3600 + days * 86400;
  }

  String _pickThumbnail(Map<String, dynamic> thumbnails) {
    for (final key in ['high', 'medium', 'default']) {
      final data = thumbnails[key] as Map<String, dynamic>?;
      final url = data?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return '';
  }


  Future<void> _addUnits(int units, {String? label}) async {
    if (quotaTracker == null) return;
    await quotaTracker!.addUnits(units, label: label);
  }


  void dispose() {
    _client.close();
  }
}
