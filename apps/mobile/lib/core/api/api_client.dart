import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/token_store.dart';
import 'api_exception.dart';

/// Resolves the API origin for the current platform.
/// Override with: flutter run --dart-define=API_BASE_URL=https://api.dayflow.app
String apiBaseUrl() {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (kIsWeb) return 'http://localhost:4000';
  if (Platform.isAndroid) return 'http://10.0.2.2:4000'; // emulator loopback
  return 'http://localhost:4000';
}

typedef SessionExpiredHandler = void Function();

/// Thin typed wrapper over Dio with bearer injection and single-flight
/// refresh-on-401. All repositories go through this.
class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: '${apiBaseUrl()}/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = TokenStore.instance.accessToken;
        if (token != null && options.headers['Authorization'] == null && options.extra['noAuth'] != true) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final response = error.response;
        final alreadyRetried = error.requestOptions.extra['retried'] == true;
        final isAuthCall = error.requestOptions.path.startsWith('/auth/');
        if (response?.statusCode == 401 && !alreadyRetried && !isAuthCall) {
          final refreshed = await _refreshSession();
          if (refreshed) {
            try {
              final opts = error.requestOptions..extra['retried'] = true;
              opts.headers['Authorization'] = 'Bearer ${TokenStore.instance.accessToken}';
              final retry = await _dio.fetch<dynamic>(opts);
              return handler.resolve(retry);
            } catch (e) {
              return handler.next(e is DioException ? e : error);
            }
          } else {
            onSessionExpired?.call();
          }
        }
        handler.next(error);
      },
    ));
  }

  static final instance = ApiClient._();

  late final Dio _dio;
  Future<bool>? _refreshing;

  /// Set by the auth controller so an unrecoverable 401 signs the user out.
  SessionExpiredHandler? onSessionExpired;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<List<dynamic>> getList(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<dynamic>(path, queryParameters: query);
      return (response.data as List<dynamic>?) ?? const [];
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> post(String path, {Object? body, bool noAuth = false}) =>
      _run(() => _dio.post<dynamic>(path, data: body, options: Options(extra: {'noAuth': noAuth})));

  Future<Map<String, dynamic>> patch(String path, {Object? body}) => _run(() => _dio.patch<dynamic>(path, data: body));

  Future<Map<String, dynamic>> put(String path, {Object? body}) => _run(() => _dio.put<dynamic>(path, data: body));

  Future<Map<String, dynamic>> delete(String path) => _run(() => _dio.delete<dynamic>(path));

  /// Multipart upload. [fields] ride along as form fields.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
  }) =>
      _run(() async {
        final form = FormData.fromMap({
          ...fields,
          'file': MultipartFile.fromBytes(bytes, filename: filename),
        });
        return _dio.post<dynamic>(path, data: form);
      });

  /// Plain-text GET (CSV export and similar non-JSON payloads).
  Future<String> getText(String path) async {
    try {
      final response = await _dio.get<String>(path, options: Options(responseType: ResponseType.plain));
      return response.data ?? '';
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      final data = response.data;
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Single-flight token refresh — concurrent 401s share one attempt.
  Future<bool> _refreshSession() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await TokenStore.instance.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await _dio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'noAuth': true}),
      );
      final data = response.data as Map<String, dynamic>;
      await TokenStore.instance.save(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      await TokenStore.instance.clear();
      return false;
    }
  }
}
