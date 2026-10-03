import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/server_config.dart';

class EmailOtpService {
  static Future<bool> accountExists(String email) async {
    final response = await http.post(
      Uri.parse('${ServerConfig.baseUrl}/api/auth/account-exists'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim()}),
    );
    if (response.statusCode != 200) throw StateError(_message(response));
    return jsonDecode(response.body)['exists'] == true;
  }

  static Future<void> request(String email) async {
    final response = await http.post(
      Uri.parse('${ServerConfig.baseUrl}/api/auth/email-otp/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim()}),
    );
    if (response.statusCode != 200) {
      throw StateError(_message(response));
    }
  }

  static Future<bool> verify(String email, String code) async {
    final response = await http.post(
      Uri.parse('${ServerConfig.baseUrl}/api/auth/email-otp/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'code': code.trim()}),
    );
    if (response.statusCode != 200) throw StateError(_message(response));
    return jsonDecode(response.body)['verified'] == true;
  }

  static String _message(http.Response response) {
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Email verification failed.';
    } catch (_) {
      return 'Email verification failed.';
    }
  }
}
