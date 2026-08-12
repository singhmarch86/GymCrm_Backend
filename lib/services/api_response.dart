import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Thrown by [unwrapJson] instead of letting a raw [FormatException] or
/// other parsing error reach the UI. [message] is always safe to show
/// directly to a user.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Checks the HTTP status before decoding the body, so a non-2xx response
/// (which is often plain text — e.g. Go's default "404 page not found")
/// never reaches `jsonDecode` and surfaces as an unreadable FormatException.
///
/// Every service method should route its response through this instead of
/// calling `jsonDecode(response.body)` directly.
Map<String, dynamic> unwrapJson(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    // A 204 has no body by definition, and several endpoints legitimately
    // return one. Decoding an empty string throws a FormatException that no
    // caller expects on the success path — the very bug class this function
    // exists to prevent, so it is handled here rather than in each caller.
    if (response.statusCode == 204 || response.body.trim().isEmpty) {
      return const {};
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String message;
  try {
    final body = jsonDecode(response.body);
    message = (body is Map && body['error'] is Map)
        ? (body['error']['message']?.toString() ?? _defaultMessage(response.statusCode))
        : _defaultMessage(response.statusCode);
  } catch (_) {
    message = _defaultMessage(response.statusCode);
  }

  throw ApiException(message, statusCode: response.statusCode);
}

/// Wraps a network call so connection failures (server down, DNS, timeout)
/// also come back as a friendly [ApiException] instead of a raw
/// [SocketException]/[http.ClientException].
Future<http.Response> guardRequest(Future<http.Response> Function() request) async {
  try {
    return await request();
  } on SocketException {
    throw const ApiException('Could not reach the server. Check your connection and try again.');
  } on HttpException {
    throw const ApiException('The server returned an unexpected response.');
  } on FormatException {
    throw const ApiException('The server returned an unexpected response.');
  }
}

String _defaultMessage(int statusCode) {
  switch (statusCode) {
    case 400:
      return 'That request was invalid. Please check the form and try again.';
    case 401:
      return 'Your session has expired. Please log in again.';
    case 403:
      return "You don't have permission to do that.";
    case 404:
      return 'That item could not be found.';
    case 409:
      return 'That conflicts with existing data.';
    default:
      if (statusCode >= 500) {
        return 'Something went wrong on the server. Please try again shortly.';
      }
      return 'Something went wrong (error $statusCode).';
  }
}
