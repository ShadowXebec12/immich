// Custom fork: talks to the laptop receiver (immich_custom_receiver.py).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class LaptopDoc {
  final String updatedAt;
  final Object? value;

  const LaptopDoc({required this.updatedAt, required this.value});
}

class LaptopSyncException implements Exception {
  final String message;

  const LaptopSyncException(this.message);

  @override
  String toString() => message;
}

class LaptopSyncApiRepository {
  static const _timeout = Duration(seconds: 8);

  final http.Client _client;

  LaptopSyncApiRepository({http.Client? client}) : _client = client ?? http.Client();

  static Uri _uri(String baseUrl, String path) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const LaptopSyncException('The laptop address is not a valid URL');
    }
    return uri;
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on LaptopSyncException {
      rethrow;
    } on TimeoutException {
      throw const LaptopSyncException('The laptop did not answer in time');
    } catch (error) {
      throw LaptopSyncException('Could not reach the laptop ($error)');
    }
  }

  LaptopDoc _doc(http.Response response) {
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return LaptopDoc(updatedAt: json['updatedAt'] as String, value: json['value']);
  }

  /// Number of documents stored on the laptop. Throws when it cannot be reached.
  Future<int> health(String baseUrl) => _guard(() async {
    final response = await _client.get(_uri(baseUrl, '/health'));
    final json = response.statusCode == 200 ? jsonDecode(response.body) : null;
    if (json is! Map || json['ok'] != true) {
      throw LaptopSyncException('That address answered, but it is not the receiver (HTTP ${response.statusCode})');
    }
    return json['keys'] as int? ?? 0;
  });

  /// The stored document, or null when the laptop has none for [key].
  Future<LaptopDoc?> get(String baseUrl, String key) => _guard(() async {
    final response = await _client.get(_uri(baseUrl, '/data/$key'));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw LaptopSyncException('Laptop refused the read (HTTP ${response.statusCode})');
    }
    return _doc(response);
  });

  /// Stores [value]. Returns null when stored, or the laptop's document when the laptop already
  /// has a newer one (nothing is overwritten in that case).
  Future<LaptopDoc?> put(String baseUrl, String key, {required String updatedAt, required Object? value}) =>
      _guard(() async {
        final response = await _client.put(
          _uri(baseUrl, '/data/$key'),
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: utf8.encode(jsonEncode({'updatedAt': updatedAt, 'value': value})),
        );
        if (response.statusCode == 409) {
          return _doc(response);
        }
        if (response.statusCode != 200) {
          throw LaptopSyncException('Laptop refused the save (HTTP ${response.statusCode})');
        }
        return null;
      });
}
