import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/import_batch.dart';
import 'api_config.dart';
import 'api_response.dart';
import 'token_manager.dart';

/// CSV import. See docs/FR-05-data-import.md in the backend repo.
///
/// [validate] never changes real data — it only parses and judges. Records are
/// created solely by [commit], and only for rows that passed.
class ImportService {
  Future<Map<String, String>> _headers() => TokenManager.authHeaders();

  Future<ImportBatch> validate({
    required String entityType,
    required String content,
    String filename = '',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/imports'),
        headers: headers,
        body: jsonEncode({
          'entity_type': entityType,
          'filename': filename,
          'content': content,
        }),
      ),
    );
    return ImportBatch.fromJson(unwrapJson(response)['data']);
  }

  /// Writes the records. [duplicatePolicy] is 'skip' (leave existing records
  /// alone) or 'update' (overwrite them from the file).
  Future<ImportBatch> commit(
    int batchId, {
    String duplicatePolicy = 'skip',
  }) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.post(
        Uri.parse('$kBaseUrl/api/v1/imports/$batchId/commit'),
        headers: headers,
        body: jsonEncode({'duplicate_policy': duplicatePolicy}),
      ),
    );
    return ImportBatch.fromJson(unwrapJson(response)['data']);
  }

  Future<ImportBatch> getBatch(int batchId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/imports/$batchId'),
        headers: headers,
      ),
    );
    return ImportBatch.fromJson(unwrapJson(response)['data']);
  }

  Future<List<ImportBatch>> history() async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.get(Uri.parse('$kBaseUrl/api/v1/imports'), headers: headers),
    );
    final List list = unwrapJson(response)['data'] as List? ?? [];
    return list.map((e) => ImportBatch.fromJson(e)).toList();
  }

  /// Throws away an uncommitted batch. Nothing was written, so nothing is lost.
  Future<void> discard(int batchId) async {
    final headers = await _headers();
    final response = await guardRequest(
      () => http.delete(
        Uri.parse('$kBaseUrl/api/v1/imports/$batchId'),
        headers: headers,
      ),
    );
    unwrapJson(response);
  }

  /// A starter CSV showing the columns we expect. Many other spellings are
  /// accepted too — the server maps aliases.
  Future<String> template(String entityType) async {
    final headers = await _headers();
    final uri = Uri.parse(
      '$kBaseUrl/api/v1/imports/template',
    ).replace(queryParameters: {'entity': entityType});
    final response = await guardRequest(() => http.get(uri, headers: headers));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw const ApiException('Could not load the template.');
  }
}
