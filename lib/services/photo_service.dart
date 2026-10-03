import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../config/server_config.dart';

class UploadedProfilePhoto {
  final String url;
  final int order;
  final int photosCount;
  final String? profilePhoto;

  const UploadedProfilePhoto({
    required this.url,
    required this.order,
    required this.photosCount,
    this.profilePhoto,
  });
}

class PhotoService {
  PhotoService._();

  static final ImagePicker _picker = ImagePicker();
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static const int maxPhotos = 5;

  static Future<File?> pickFromGallery() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (image == null) return null;
    return File(image.path);
  }

  static Future<File?> pickFromCamera() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (image == null) return null;
    return File(image.path);
  }

  static String resolvePhotoUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';

    final trimmed = url.trim();

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    // Some older records contain a server URL without a leading slash.
    if (trimmed.startsWith('photos/')) {
      return '${ServerConfig.baseUrl}/$trimmed';
    }

    if (trimmed.startsWith('gs://')) {
      return '';
    }

    if (trimmed.startsWith('/')) {
      return '${ServerConfig.baseUrl}$trimmed';
    }

    return '${ServerConfig.baseUrl}/$trimmed';
  }

  static MediaType _mediaTypeForFile(File file) {
    final path = file.path.toLowerCase();

    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }

    if (path.endsWith('.png')) {
      return MediaType('image', 'png');
    }

    if (path.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }

    // Android camera/gallery sometimes returns a cached file without a clear
    // extension even when the image is JPEG. image_picker re-encodes using
    // imageQuality, so JPEG is the safest default for unknown gallery/camera
    // paths.
    return MediaType('image', 'jpeg');
  }

  static Future<http.Response> _sendPhotoUpload({
    required File file,
    required String token,
    required int order,
  }) async {
    Object? lastNetworkError;

    // A Tailscale Funnel can briefly close a TLS connection while the local
    // server is restarting. Rebuild the multipart request for every attempt;
    // MultipartRequest bodies cannot be safely reused after send().
    for (var attempt = 0; attempt < 3; attempt++) {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ServerConfig.baseUrl}/api/profile/photo/upload'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['order'] = order.toString();
      request.files.add(
        await http.MultipartFile.fromPath(
          'photo',
          file.path,
          contentType: _mediaTypeForFile(file),
        ),
      );

      try {
        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 60),
        );
        return await http.Response.fromStream(streamedResponse);
      } on HandshakeException catch (error) {
        lastNetworkError = error;
      } on SocketException catch (error) {
        lastNetworkError = error;
      } on TimeoutException catch (error) {
        lastNetworkError = error;
      } on HttpException catch (error) {
        lastNetworkError = error;
      }

      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }

    throw StateError(
      'The secure Nisa server connection was interrupted. '
      'Please check that the Nisa server and Tailscale Funnel are running, '
      'then try again. (${lastNetworkError.runtimeType})',
    );
  }

  static Future<UploadedProfilePhoto> uploadPhoto({
    required File file,
    int order = 0,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in.');
    }

    if (order < 0 || order >= maxPhotos) {
      throw ArgumentError('Photo order must be between 0 and 4.');
    }

    final exists = await file.exists();

    if (!exists) {
      throw StateError('Selected photo file was not found.');
    }

    final token = await user.getIdToken(true);

    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain Firebase token.');
    }

    final response = await _sendPhotoUpload(
      file: file,
      token: token,
      order: order,
    );

    Map<String, dynamic>? data;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data?['detail'];
      throw StateError(
        detail is String
            ? detail
            : 'Photo upload failed (${response.statusCode}).',
      );
    }

    final photo = data?['photo'];

    if (photo is! Map<String, dynamic>) {
      throw StateError('Invalid photo upload response.');
    }

    return UploadedProfilePhoto(
      url: photo['url'] as String? ?? '',
      order: photo['order'] is num ? (photo['order'] as num).toInt() : order,
      photosCount: data?['photosCount'] is num
          ? (data!['photosCount'] as num).toInt()
          : 1,
      profilePhoto: data?['profilePhoto'] as String?,
    );
  }

  static Future<void> deletePhoto(int order) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in.');
    }

    final token = await user.getIdToken(true);

    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain Firebase token.');
    }

    final response = await http
        .delete(
          Uri.parse('${ServerConfig.baseUrl}/api/profile/photo/$order'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic>? data;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data?['detail'];
      throw StateError(
        detail is String
            ? detail
            : 'Could not delete photo (${response.statusCode}).',
      );
    }
  }

  static Future<void> reorderPhotos(List<String> urls) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in.');
    }

    final token = await user.getIdToken(true);

    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain Firebase token.');
    }

    final response = await http
        .patch(
          Uri.parse('${ServerConfig.baseUrl}/api/profile/photo/order'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'urls': urls}),
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic>? data;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data?['detail'];
      throw StateError(
        detail is String
            ? detail
            : 'Could not reorder photos (${response.statusCode}).',
      );
    }
  }
}
