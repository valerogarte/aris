import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'ai_cost_tracker.dart';

class AiSummaryService {
  AiSummaryService({
    http.Client? client,
    AiCostTracker? costTracker,
  })  : _client = client ?? http.Client(),
        _costTracker = costTracker;

  final http.Client _client;
  final AiCostTracker? _costTracker;

  static const Map<String, _ModelPricing> _pricingByModel = {
    'gpt-5.2': _ModelPricing(1.75, 14.0),
    'gpt-5-mini': _ModelPricing(0.25, 2.0),
    'gemini-3-pro-preview': _ModelPricing(2.0, 12.0),
    'gemini-3-flash-preview': _ModelPricing(0.5, 3.0),
    'claude-opus-4-6': _ModelPricing(5.0, 25.0),
    'claude-sonnet-4-5-20250929': _ModelPricing(3.0, 15.0),
    'claude-haiku-4-5-20251001': _ModelPricing(1.0, 5.0),
    'grok-4': _ModelPricing(3.0, 15.0),
    'grok-4-1-fast-non-reasoning': _ModelPricing(0.2, 0.5),
  };

  Future<String> summarize({
    required String provider,
    required String model,
    required String apiKey,
    required String transcript,
    String? title,
    String? channel,
  }) async {
    final normalized = provider.trim().toLowerCase();
    final prompt = _buildPrompt(
      transcript,
      title: title,
      channel: channel,
    );
    switch (normalized) {
      case 'chatgpt':
        return _summarizeOpenAi(
          model: model,
          apiKey: apiKey,
          prompt: prompt,
        );
      case 'gemini':
        return _summarizeGemini(
          model: model,
          apiKey: apiKey,
          prompt: prompt,
        );
      case 'antrophic':
      case 'anthropic':
        return _summarizeAnthropic(
          model: model,
          apiKey: apiKey,
          prompt: prompt,
        );
      case 'grok':
        return _summarizeGrok(
          model: model,
          apiKey: apiKey,
          prompt: prompt,
        );
      default:
        throw Exception('Proveedor no soportado: $provider');
    }
  }

  String _buildPrompt(
    String transcript, {
    String? title,
    String? channel,
  }) {
    final header = StringBuffer(
      'Resume el siguiente vídeo en español.\n'
      'El resultado debe estar pensado para un narrador, con coherencia y '
      'fluidez para ser leído en voz alta.\n'
      'Devuelve exclusivamente un JSON válido (sin markdown ni texto extra).\n'
      'Estructura requerida:\n'
      '{\n'
      '  "resumen_inicial": "Un párrafo breve con el resumen general.",\n'
      '  "contenido_principal": "Texto completo del resumen, sin omitir '
      'conceptos importantes.",\n'
      '  "preguntas": ["Pregunta 1", "Pregunta 2", "Pregunta 3"]\n'
      '}\n'
      'Las preguntas deben servir para profundizar en el tema.\n'
      'Incluye exactamente 3 preguntas.\n',
    );
    if (title != null && title.isNotEmpty) {
      header.writeln('Titulo: $title');
    }
    if (channel != null && channel.isNotEmpty) {
      header.writeln('Canal: $channel');
    }
    header.writeln('Requisitos:');
    header.writeln('- Mantén los términos clave.');
    header.writeln('- No omitas conceptos importantes.');
    header.writeln('\nTranscripción:\n$transcript');
    return header.toString();
  }

  Future<String> _summarizeOpenAi({
    required String model,
    required String apiKey,
    required String prompt,
  }) async {
    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final payload = <String, dynamic>{
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': 'Eres un asistente que resume transcripciones.',
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
    };
    final temperature = _openAiTemperatureForModel(model);
    if (temperature != null) {
      payload['temperature'] = temperature;
    }
    final body = jsonEncode(payload);
    _logRequest('openai', uri, headers, body);
    final response = await _client.post(
      uri,
      headers: headers,
      body: body,
    );
    _logResponse('openai', response);
    if (response.statusCode != 200) {
      throw Exception(_extractError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _recordCostFromOpenAi(model, data);
    final choices = data['choices'] as List?;
    final message = choices?.isNotEmpty == true
        ? (choices!.first as Map<String, dynamic>)['message']
        : null;
    final content =
        (message as Map<String, dynamic>?)?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw Exception('Respuesta vacia del proveedor.');
    }
    return content.trim();
  }

  double? _openAiTemperatureForModel(String model) {
    final normalized = model.trim().toLowerCase();
    if (normalized.startsWith('gpt-5')) {
      // These models only support the default temperature (1).
      return null;
    }
    return 0.2;
  }

  void _recordCostFromOpenAi(String model, Map<String, dynamic> data) {
    final usage = data['usage'] as Map<String, dynamic>?;
    final inputTokens = (usage?['prompt_tokens'] as num?)?.toInt() ?? 0;
    final outputTokens =
        (usage?['completion_tokens'] as num?)?.toInt() ?? 0;
    _recordCost(model, inputTokens: inputTokens, outputTokens: outputTokens);
  }

  void _recordCostFromGemini(String model, Map<String, dynamic> data) {
    final usage = data['usageMetadata'] as Map<String, dynamic>?;
    final inputTokens =
        (usage?['promptTokenCount'] as num?)?.toInt() ?? 0;
    final outputTokens =
        (usage?['candidatesTokenCount'] as num?)?.toInt() ?? 0;
    if (inputTokens == 0 && outputTokens == 0) {
      final total = (usage?['totalTokenCount'] as num?)?.toInt() ?? 0;
      if (total > 0) {
        _recordCost(model, inputTokens: total, outputTokens: 0);
        return;
      }
    }
    _recordCost(model, inputTokens: inputTokens, outputTokens: outputTokens);
  }

  void _recordCostFromAnthropic(String model, Map<String, dynamic> data) {
    final usage = data['usage'] as Map<String, dynamic>?;
    final inputTokens = (usage?['input_tokens'] as num?)?.toInt() ?? 0;
    final outputTokens = (usage?['output_tokens'] as num?)?.toInt() ?? 0;
    _recordCost(model, inputTokens: inputTokens, outputTokens: outputTokens);
  }

  void _recordCost(
    String model, {
    required int inputTokens,
    required int outputTokens,
  }) {
    if (_costTracker == null) return;
    if (inputTokens <= 0 && outputTokens <= 0) return;
    final pricing = _pricingByModel[model.trim().toLowerCase()];
    if (pricing == null) return;
    final microCost = ((inputTokens * pricing.inputPerMillion) +
            (outputTokens * pricing.outputPerMillion))
        .round();
    if (microCost <= 0) return;
    _costTracker!.addCostMicro(
      microCost,
      label: model,
    );
  }

  Future<String> _summarizeGemini({
    required String model,
    required String apiKey,
    required String prompt,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$apiKey',
    );
    final headers = {
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
      },
    });
    _logRequest('gemini', uri, headers, body);
    final response = await _client.post(
      uri,
      headers: headers,
      body: body,
    );
    _logResponse('gemini', response);
    if (response.statusCode != 200) {
      throw Exception(_extractError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _recordCostFromGemini(model, data);
    final candidates = data['candidates'] as List?;
    final content = candidates?.isNotEmpty == true
        ? (candidates!.first as Map<String, dynamic>)['content']
        : null;
    final parts = (content as Map<String, dynamic>?)?['parts'] as List?;
    final text = parts?.isNotEmpty == true
        ? (parts!.first as Map<String, dynamic>)['text'] as String?
        : null;
    if (text == null || text.isEmpty) {
      throw Exception('Respuesta vacia del proveedor.');
    }
    return text.trim();
  }

  Future<String> _summarizeAnthropic({
    required String model,
    required String apiKey,
    required String prompt,
  }) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    final headers = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({
      'model': model,
      'temperature': 0.2,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        },
      ],
    });
    _logRequest('anthropic', uri, headers, body);
    final response = await _client.post(
      uri,
      headers: headers,
      body: body,
    );
    _logResponse('anthropic', response);
    if (response.statusCode != 200) {
      throw Exception(_extractError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _recordCostFromAnthropic(model, data);
    final content = data['content'] as List?;
    final text = content?.isNotEmpty == true
        ? (content!.first as Map<String, dynamic>)['text'] as String?
        : null;
    if (text == null || text.isEmpty) {
      throw Exception('Respuesta vacia del proveedor.');
    }
    return text.trim();
  }

  Future<String> _summarizeGrok({
    required String model,
    required String apiKey,
    required String prompt,
  }) async {
    final uri = Uri.parse('https://api.x.ai/v1/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': 'Eres un asistente que resume transcripciones.',
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
      'temperature': 0.2,
    });
    _logRequest('grok', uri, headers, body);
    final response = await _client.post(
      uri,
      headers: headers,
      body: body,
    );
    _logResponse('grok', response);
    if (response.statusCode != 200) {
      throw Exception(_extractError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _recordCostFromOpenAi(model, data);
    final choices = data['choices'] as List?;
    final message = choices?.isNotEmpty == true
        ? (choices!.first as Map<String, dynamic>)['message']
        : null;
    final content =
        (message as Map<String, dynamic>?)?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw Exception('Respuesta vacia del proveedor.');
    }
    return content.trim();
  }

  String _extractError(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {}
    return 'Error ${response.statusCode}: ${response.body}';
  }

  void _logRequest(
    String provider,
    Uri uri,
    Map<String, String> headers,
    String body,
  ) {
    // Intentionally no-op: avoid logging prompts/transcripts.
    return;
  }

  void _logResponse(String provider, http.Response response) {
    if (!kDebugMode) return;
    _logLong('[AI:$provider] OUTPUT ${response.body}');
  }

  void _logLong(String message) {
    const chunkSize = 800;
    for (var i = 0; i < message.length; i += chunkSize) {
      final end = math.min(i + chunkSize, message.length);
      debugPrint(message.substring(i, end));
    }
  }

  void dispose() {
    _client.close();
  }
}

class _ModelPricing {
  const _ModelPricing(this.inputPerMillion, this.outputPerMillion);

  final double inputPerMillion;
  final double outputPerMillion;
}
