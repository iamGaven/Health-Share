import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FatSecretService {
  static String get consumerKey => dotenv.env['FATSECRET_CONSUMER_KEY'] ?? '';
  static String get consumerSecret => dotenv.env['FATSECRET_CONSUMER_SECRET'] ?? '';

  static const String requestTokenUrl =
      'https://authentication.fatsecret.com/oauth/request_token';
  static const String authorizeUrl =
      'https://authentication.fatsecret.com/oauth/authorize';
  static const String accessTokenUrl =
      'https://authentication.fatsecret.com/oauth/access_token';
  static const String apiUrl =
      'https://platform.fatsecret.com/rest/server.api';

  String _tempToken = '';
  String _tempSecret = '';
  String _accessToken = '';
  String _accessSecret = '';
  bool _isCalling = false;

  // ─── OAuth Helpers ────────────────────────────────────────────

  String _nonce() {
    final rand = Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _timestamp() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  String _encode(String value) {
    return Uri.encodeComponent(value)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }

  String _hmacSha1(String key, String message) {
    final hmac = Hmac(sha1, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(message));
    return base64.encode(digest.bytes);
  }

  String _buildSignature({
    required String method,
    required String url,
    required Map<String, String> params,
    required String tokenSecret,
  }) {
    final sorted = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    final paramString = sorted.entries
        .map((e) => '${_encode(e.key)}=${_encode(e.value)}')
        .join('&');

    final baseString =
        '${method.toUpperCase()}&${_encode(url)}&${_encode(paramString)}';

    final signingKey = '${_encode(consumerSecret)}&${_encode(tokenSecret)}';

    print('--- Signature Debug ---');
    print('Param string: $paramString');
    print('Base string: $baseString');
    print('Signing key: $signingKey');

    return _hmacSha1(signingKey, baseString);
  }

  String _buildAuthHeader(Map<String, String> oauthParams) {
    final parts = oauthParams.entries
        .where((e) => e.key.startsWith('oauth_'))
        .map((e) => '${e.key}="${e.value}"')
        .join(', ');
    return 'OAuth realm="", $parts';
  }

  // ─── Auth ─────────────────────────────────────────────────────

  Future<String> getAuthorizationUrl() async {
    final oauthParams = {
      'oauth_callback': 'oob',
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': _nonce(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': _timestamp(),
      'oauth_version': '1.0',
    };

    final signature = _buildSignature(
      method: 'GET',
      url: requestTokenUrl,
      params: Map.from(oauthParams),
      tokenSecret: '',
    );

    oauthParams['oauth_signature'] = signature;

    final uri = Uri.parse(requestTokenUrl).replace(
      queryParameters: oauthParams,
    );

    print('Request URL: $uri');

    final response = await http.get(uri, headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    });

    print('Step 1 Status: ${response.statusCode}');
    print('Step 1 Response: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('Step 1 Failed: ${response.body}');
    }

    final responseParams = Uri.splitQueryString(response.body);
    _tempToken = responseParams['oauth_token'] ?? '';
    _tempSecret = responseParams['oauth_token_secret'] ?? '';

    print('Temp Token: $_tempToken');
    print('Temp Secret: $_tempSecret');

    return '$authorizeUrl?oauth_token=$_tempToken';
  }

  Future<void> exchangePinForAccessToken(String pin) async {
    final params = {
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': _nonce(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': _timestamp(),
      'oauth_token': _tempToken,
      'oauth_verifier': pin,
      'oauth_version': '1.0',
    };

    params['oauth_signature'] = _buildSignature(
      method: 'GET',
      url: accessTokenUrl,
      params: Map.from(params),
      tokenSecret: _tempSecret,
    );

    final uri = Uri.parse(accessTokenUrl).replace(queryParameters: params);

    print('Step 3 URL: $uri');

    final response = await http.get(uri, headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    });

    print('Step 3 Status: ${response.statusCode}');
    print('Step 3 Response: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('Step 3 Failed: ${response.body}');
    }

    final responseParams = Uri.splitQueryString(response.body);
    _accessToken = responseParams['oauth_token'] ?? '';
    _accessSecret = responseParams['oauth_token_secret'] ?? '';
    await _saveTokens();

    print('Access Token: $_accessToken');
    print('Access Secret: $_accessSecret');
  }

  // ─── API Call: Get Food Entries ───────────────────────────────
Future<Map<String, dynamic>> getFoodEntries(DateTime date) async {
  if (_accessToken.isEmpty) throw Exception('Not authenticated');

  // Wait if another call is already in progress
  while (_isCalling) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  _isCalling = true;

  try {
    return await _doGetFoodEntries(date);
  } finally {
    // Always release the lock, even on error
    _isCalling = false;
  }
}

Future<Map<String, dynamic>> _doGetFoodEntries(DateTime date) async {
  final dateInt = date.difference(DateTime(1970, 1, 1)).inDays;

  // 2. Retry loop — up to 3 attempts with increasing delay
  for (int attempt = 1; attempt <= 3; attempt++) {
    final apiParams = {
      'date': dateInt.toString(),
      'format': 'json',
      'method': 'food_entries.get.v2',
    };

    final oauthParams = {
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': _nonce(),           // fresh nonce each attempt
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': _timestamp(),   // fresh timestamp each attempt
      'oauth_token': _accessToken,
      'oauth_version': '1.0',
    };

    final allParams = {...apiParams, ...oauthParams};

    final signature = _buildSignature(
      method: 'POST',
      url: apiUrl,
      params: allParams,
      tokenSecret: _accessSecret,
    );

    oauthParams['oauth_signature'] = signature;

    final body = apiParams.entries
        .map((e) => '${_encode(e.key)}=${_encode(e.value)}')
        .join('&');

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': _buildAuthHeader(oauthParams),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('API Failed: ${response.body}');
    }

    final decoded = jsonDecode(response.body);

    // 3. Check for invalid signature error specifically and retry
    if (decoded['error'] != null) {
      final code = decoded['error']['code'];
      final message = decoded['error']['message'] ?? '';

      if (code == 8 && attempt < 3) {
        // Invalid signature — wait longer each retry so timestamps diverge
        final waitMs = attempt * 1200;
        print('Attempt $attempt: Invalid signature, retrying in ${waitMs}ms...');
        await Future.delayed(Duration(milliseconds: waitMs));
        continue; // retry
      }

      throw Exception('FatSecret error ${code}: $message');
    }

    return decoded; // success
  }

  throw Exception('getFoodEntries failed after 3 attempts');
}

  // ─── Connection Test ──────────────────────────────────────────

  Future<bool> testConnection() async {
    if (_accessToken.isEmpty) return false;
    try {
      final data = await getFoodEntries(DateTime.now());
      print('Connection test passed: $data');
      return true;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }

  // ─── Token Storage ────────────────────────────────────────────

  Future<void> _saveTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', _accessToken);
    await prefs.setString('access_secret', _accessSecret);
    print('Tokens saved to device');
  }

  Future<bool> loadSavedTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token') ?? '';
    _accessSecret = prefs.getString('access_secret') ?? '';
    print('Loaded token: $_accessToken');
    return _accessToken.isNotEmpty;
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('access_secret');
    _accessToken = '';
    _accessSecret = '';
    print('Tokens cleared');
  }
}