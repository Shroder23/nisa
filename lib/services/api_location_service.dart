import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'api_auth_service.dart';

/// Explicit, one-shot approximate location sharing for nearby recommendations.
/// The server rounds coordinates before storage and never returns raw values.
class ApiLocationService {
  ApiLocationService._();

  static Future<bool> isSharingEnabled() async {
    final response = await ApiAuthService.get('/api/location/me');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return data?['enabled'] == true;
  }

  static Future<void> updateApproximateLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services and try again.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError(
        'Location permission is needed for nearby recommendations.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is needed for nearby recommendations.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.lowest,
        timeLimit: Duration(seconds: 25),
      ),
    );
    final response = await ApiAuthService.putJson('/api/location/me', {
      'latitude': position.latitude,
      'longitude': position.longitude,
    });
    _checkResponse(response, _decodeMap(response));
  }

  static Future<void> stopSharing() async {
    final response = await ApiAuthService.delete('/api/location/me');
    _checkResponse(response, _decodeMap(response));
  }

  static Map<String, dynamic>? _decodeMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static void _checkResponse(
    http.Response response,
    Map<String, dynamic>? data,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data?['detail']?.toString().trim();
      throw StateError(
        detail == null || detail.isEmpty
            ? 'Could not update location. Please try again.'
            : detail,
      );
    }
  }
}
