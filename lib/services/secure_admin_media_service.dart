import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'admin_verification_api_service.dart';

class SecureAdminMediaService {
  SecureAdminMediaService._();

  static Future<File> downloadVideo({
    required String adminKey,
    required String protectedUrl,
  }) async {
    final url = AdminVerificationApiService.resolveUrl(protectedUrl);
    if (url.isEmpty) {
      throw StateError('Verification video URL is missing.');
    }

    final headers = await AdminVerificationApiService.protectedMediaHeaders(
      adminKey: adminKey,
    );

    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw StateError(
        'Video download failed (${response.statusCode}): ${response.body}',
      );
    }

    final directory = await getTemporaryDirectory();
    final folder = Directory('${directory.path}/nisa_admin_verification');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final file = File(
      '${folder.path}/verification_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  static Future<void> deleteIfExists(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Temporary sensitive media cleanup must not crash the UI.
    }
  }
}
