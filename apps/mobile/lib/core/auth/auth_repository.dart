import '../api/api_client.dart';
import '../models/models.dart';
import 'token_store.dart';

sealed class OtpVerifyResult {
  const OtpVerifyResult();
}

class OtpNewUser extends OtpVerifyResult {
  const OtpNewUser(this.signupToken);
  final String signupToken;
}

class OtpExistingUser extends OtpVerifyResult {
  const OtpExistingUser(this.selectToken, this.accounts);
  final String selectToken;
  final List<AccountSummary> accounts;
}

/// Result of a password login: either straight in, or pick an account first.
sealed class PasswordLoginResult {
  const PasswordLoginResult();
}

class PasswordLoginSignedIn extends PasswordLoginResult {
  const PasswordLoginSignedIn(this.me);
  final Me me;
}

class PasswordLoginChooseAccount extends PasswordLoginResult {
  const PasswordLoginChooseAccount(this.selectToken, this.accounts);
  final String selectToken;
  final List<AccountSummary> accounts;
}

/// All authentication + session API calls.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<({int resendAfterSec, String? devCode})> requestOtp(String email, {required bool signup}) async {
    final json = await _api.post(
      '/auth/otp/request',
      body: {'email': email, 'purpose': signup ? 'signup' : 'login'},
      noAuth: true,
    );
    return (resendAfterSec: json['resendAfterSec'] as int? ?? 30, devCode: json['devCode'] as String?);
  }

  Future<OtpVerifyResult> verifyOtp(String email, String code) async {
    final json = await _api.post('/auth/otp/verify', body: {'email': email, 'code': code}, noAuth: true);
    if (json['status'] == 'new_user') {
      return OtpNewUser(json['signupToken'] as String);
    }
    return OtpExistingUser(
      json['selectToken'] as String,
      (json['accounts'] as List<dynamic>? ?? const [])
          .map((a) => AccountSummary.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Me> completeSignup({
    required String signupToken,
    required String fullName,
    required String password,
    String? useFor,
    String? manageCategory,
    String? workCategory,
  }) async {
    final json = await _api.post('/auth/signup/complete', noAuth: true, body: {
      'signupToken': signupToken,
      'fullName': fullName,
      'password': password,
      'useFor': ?useFor,
      'manageCategory': ?manageCategory,
      'workCategory': ?workCategory,
    });
    return _storeSession(json);
  }

  /// Logs in with email + password. The server nests the session one level
  /// deeper than the OTP endpoints do.
  Future<PasswordLoginResult> passwordLogin(String email, String password) async {
    final json = await _api.post(
      '/auth/login/password',
      noAuth: true,
      body: {'email': email, 'password': password},
    );
    if (json['status'] == 'choose') {
      return PasswordLoginChooseAccount(
        json['selectToken'] as String,
        (json['accounts'] as List<dynamic>? ?? const [])
            .map((a) => AccountSummary.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
    }
    final session = json['session'] as Map<String, dynamic>;
    return PasswordLoginSignedIn(await _storeSession(session));
  }

  Future<Me> selectAccount({required String selectToken, required String accountId}) async {
    final json = await _api.post('/auth/login/select', noAuth: true, body: {
      'selectToken': selectToken,
      'accountId': accountId,
    });
    return _storeSession(json);
  }

  Future<Me> switchAccount(String accountId) async {
    final json = await _api.post('/auth/switch', body: {'accountId': accountId});
    return _storeSession(json);
  }

  Future<Me> fetchMe() async {
    final json = await _api.get('/me');
    return Me.fromJson(json);
  }

  Future<Me?> restoreSession() async {
    await TokenStore.instance.restore();
    final refresh = await TokenStore.instance.readRefreshToken();
    if (refresh == null) return null;
    try {
      final json = await _api.post('/auth/refresh', body: {'refreshToken': refresh}, noAuth: true);
      return await _storeSession(json);
    } catch (_) {
      await TokenStore.instance.clear();
      return null;
    }
  }

  Future<void> logout() async {
    final refresh = await TokenStore.instance.readRefreshToken();
    if (refresh != null) {
      try {
        await _api.post('/auth/logout', body: {'refreshToken': refresh});
      } catch (_) {
        // Best effort — clear locally regardless.
      }
    }
    await TokenStore.instance.clear();
  }

  Future<Me> markChecklistStep(String step) async {
    final json = await _api.post('/me/checklist', body: {'step': step});
    return Me.fromJson(json);
  }

  Future<Me> _storeSession(Map<String, dynamic> json) async {
    await TokenStore.instance.save(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
    return Me.fromJson(json);
  }
}
