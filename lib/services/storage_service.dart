import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  static const String userIdKey = 'user_id';
  static const String gymIdKey = 'gym_id';
  static const String roleKey = 'role';
  static const String userNameKey = 'user_name';

  static Future<void> saveAuthData({
    required String accessToken,
    required String refreshToken,
    required int userId,
    required int gymId,
    required String role,
    required String userName,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(accessTokenKey, accessToken);
    await prefs.setString(refreshTokenKey, refreshToken);

    await prefs.setInt(userIdKey, userId);
    await prefs.setInt(gymIdKey, gymId);

    await prefs.setString(roleKey, role);
    await prefs.setString(userNameKey, userName);
  }

  /// Replaces just the token pair, leaving the user/gym/role fields intact.
  /// Used by TokenManager after a refresh, where only the tokens change.
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, accessToken);
    await prefs.setString(refreshTokenKey, refreshToken);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(accessTokenKey);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(refreshTokenKey);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(userIdKey);
  }

  static Future<int?> getGymId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(gymIdKey);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(roleKey);
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(userNameKey);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
