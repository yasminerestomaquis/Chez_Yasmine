import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Client HTTP vers l'API NestJS : ajoute automatiquement le jeton Supabase
/// de la session en cours (`Authorization: Bearer <jwt>`), que NestJS vérifie
/// via SupabaseJwtGuard (voir apps/api/nestjs/src/auth/).
class ApiClient {
  Map<String, String> get _authHeaders {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final response = await http.get(_uri(path, query), headers: _authHeaders);
    return _decode(response);
  }

  /// Comme [get], mais pour une réponse non-JSON (ex. l'export CSV des
  /// rapports, `GET .../reports/summary.csv`) — `_decode` ferait échouer le
  /// `jsonDecode` sur un corps CSV.
  Future<String> getText(String path, {Map<String, String>? query}) async {
    final response = await http.get(_uri(path, query), headers: _authHeaders);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw ApiException(response.statusCode, 'Erreur ${response.statusCode}');
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final response = await http.post(
      _uri(path),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final response = await http.patch(
      _uri(path),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<void> delete(String path) async {
    final response = await http.delete(_uri(path), headers: _authHeaders);
    _decode(response);
  }

  /// Upload multipart d'une image (champ `file`), utilisé par le pipeline
  /// photo produit (voir apps/api/nestjs/src/catalog/product-images.controller.ts).
  Future<dynamic> uploadFile(String path, {required List<int> bytes, required String filename, required String contentType}) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_authHeaders)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: MediaType.parse(contentType)));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    String message = 'Erreur ${response.statusCode}';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        final m = decoded['message'];
        message = m is List ? m.join(', ') : m.toString();
      }
    } catch (_) {
      // corps non-JSON : on garde le message par défaut
    }
    throw ApiException(response.statusCode, message);
  }
}
