import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FatSecretService {
  static const String consumerKey = 'ae38afc87de34af8bf7afce5eb9e979f';
  static const String consumerSecret = 'f7464f2e13a042da883944a57e40a8ea';

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

  // ─── OAuth Helpers ────────────────────────────────────────────

  String _nonce() {
    final rand = Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _timestamp() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  // Percent encode per OAuth spec
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
    // Step 1: Sort params alphabetically by key
    final sorted = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    // Step 2: Build normalized parameter string
    final paramString = sorted.entries
        .map((e) => '${_encode(e.key)}=${_encode(e.value)}')
        .join('&');

    // Step 3: Build signature base string
    final baseString =
        '${method.toUpperCase()}&${_encode(url)}&${_encode(paramString)}';

    // Step 4: Build signing key
    final signingKey = '${_encode(consumerSecret)}&${_encode(tokenSecret)}';

    print('--- Signature Debug ---');
    print('Param string: $paramString');
    print('Base string: $baseString');
    print('Signing key: $signingKey');

    return _hmacSha1(signingKey, baseString);
  }

  String _buildAuthHeader(Map<String, String> oauthParams) {
    // OAuth header: only oauth_ params, values quoted but not encoded
    final parts = oauthParams.entries
        .where((e) => e.key.startsWith('oauth_'))
        .map((e) => '${e.key}="${e.value}"')
        .join(', ');
    return 'OAuth realm="", $parts';
  }
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
    method: 'GET',  // changed to GET since params are in URL
    url: requestTokenUrl,
    params: Map.from(oauthParams),
    tokenSecret: '',
  );

  oauthParams['oauth_signature'] = signature;

  // Build URL with oauth params as query parameters
  final uri = Uri.parse(requestTokenUrl).replace(
    queryParameters: oauthParams,
  );

  print('Request URL: $uri');

  final response = await http.get(
    uri,
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  );

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
  await _saveTokens(); // <-- add this line

  print('Access Token: $_accessToken');
  print('Access Secret: $_accessSecret');
}
  // ─── API Call: Get Food Entries ───────────────────────────────

  Future<Map<String, dynamic>> getFoodEntries(DateTime date) async {
  if (_accessToken.isEmpty) throw Exception('Not authenticated');

  final dateInt = date.difference(DateTime(1970, 1, 1)).inDays;

  final apiParams = {
    'date': dateInt.toString(),
    'format': 'json',
    'method': 'food_entries.get.v2',
  };

  final oauthParams = {
    'oauth_consumer_key': consumerKey,
    'oauth_nonce': _nonce(),
    'oauth_signature_method': 'HMAC-SHA1',
    'oauth_timestamp': _timestamp(),
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

  print('API Status: ${response.statusCode}');
  print('API Response: ${response.body}');

  if (response.statusCode != 200) {
    throw Exception('API Failed: ${response.body}');
  }

  return jsonDecode(response.body);
}

  Future<bool> testConnection() async {
  if (_accessToken.isEmpty) return false;
  
  try {
    // Use today's date to make a lightweight test call
    final data = await getFoodEntries(DateTime.now());
    print('Connection test passed: $data');
    return true;
  } catch (e) {
    print('Connection test failed: $e');
    return false;
  }
}


// Save tokens to device storage
Future<void> _saveTokens() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('access_token', _accessToken);
  await prefs.setString('access_secret', _accessSecret);
  print('Tokens saved to device');
}

// Load tokens from device storage
Future<bool> loadSavedTokens() async {
  final prefs = await SharedPreferences.getInstance();
  _accessToken = prefs.getString('access_token') ?? '';
  _accessSecret = prefs.getString('access_secret') ?? '';
  print('Loaded token: $_accessToken');
  return _accessToken.isNotEmpty;
}

// Clear tokens (for logout)
Future<void> clearTokens() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('access_token');
  await prefs.remove('access_secret');
  _accessToken = '';
  _accessSecret = '';
  print('Tokens cleared');
}
}