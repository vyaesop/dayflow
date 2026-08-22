import 'package:dio/dio.dart';

/// A user-presentable API failure.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final raw = data['message'];
        final message = raw is List ? raw.join('\n') : raw?.toString();
        if (message != null && message.isNotEmpty) {
          return ApiException(message, statusCode: error.response?.statusCode);
        }
      }
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          const ApiException('Connection timed out. Please try again.'),
        DioExceptionType.connectionError => const ApiException("Can't reach Dayflow. Check your connection."),
        _ => ApiException('Something went wrong. Please try again.', statusCode: error.response?.statusCode),
      };
    }
    return const ApiException('Something went wrong. Please try again.');
  }

  @override
  String toString() => message;
}
