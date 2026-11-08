import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nisa_e_sakina/services/api_auth_service.dart';

http.Response _response(int status, Map<String, Object?> body) =>
    http.Response(jsonEncode(body), status);

void main() {
  test('only password_setup_required offers the setup/reset path', () {
    final setup = ApiAuthException.fromResponse(
      _response(409, {
        'detail': {
          'code': ApiAuthFailureCode.passwordSetupRequired,
          'message': 'Set or reset your password.',
        },
      }),
    );
    final wrongPassword = ApiAuthException.fromResponse(
      _response(401, {'detail': 'Email or password is incorrect.'}),
    );
    final forbidden = ApiAuthException.fromResponse(
      _response(403, {'detail': 'This account is unavailable.'}),
    );

    expect(ApiAuthFailureCode.requiresPasswordSetup(setup), isTrue);
    expect(ApiAuthFailureCode.requiresPasswordSetup(wrongPassword), isFalse);
    expect(ApiAuthFailureCode.requiresPasswordSetup(forbidden), isFalse);
    expect(wrongPassword.message, 'Email or password is incorrect.');
  });

  test('an unknown or malformed response never triggers password setup', () {
    final noCode = ApiAuthException.fromResponse(
      _response(401, {'detail': 'Email or password is incorrect.'}),
    );
    final malformed = ApiAuthException.fromResponse(
      http.Response('not-json', 401),
    );

    expect(ApiAuthFailureCode.requiresPasswordSetup(noCode), isFalse);
    expect(ApiAuthFailureCode.requiresPasswordSetup(malformed), isFalse);
  });
}
