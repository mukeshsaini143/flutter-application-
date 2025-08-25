import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

/// Very simple in-memory "database"
final Map<String, String> users = {}; // username -> passwordHash

const jwtSecret = 'dev_secret_change_me';

String hashPassword(String password) =>
    sha256.convert(utf8.encode(password)).toString();

String generateToken(String username) {
  final jwt = JWT({'username': username});
  return jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(hours: 2));
}

Map<String, String> _jsonHeaders([Map<String, String>? extra]) => {
      'content-type': 'application/json',
      if (extra != null) ...extra,
    };

Response jsonOk(Object data, {int status = 200}) =>
    Response(status, body: jsonEncode(data), headers: _jsonHeaders());

Response jsonError(String message, {int status = 400}) =>
    jsonOk({'message': message}, status: status);

Handler buildRouter() {
  final router = Router();

  // Health check
  router.get('/health', (Request req) => jsonOk({'status': 'ok'}));

  // Register
  router.post('/register', (Request req) async {
    final body = await req.readAsString();
    if (body.isEmpty) return jsonError('Empty body', status: 400);

    final data = jsonDecode(body) as Map<String, dynamic>;
    final username = (data['username'] as String?)?.trim();
    final password = data['password'] as String?;

    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return jsonError('Missing fields', status: 400);
    }
    if (users.containsKey(username)) {
      return jsonError('User already exists', status: 400);
    }

    users[username] = hashPassword(password);
    return jsonOk({'message': 'User registered'});
  });

  // Login
  router.post('/login', (Request req) async {
    final body = await req.readAsString();
    if (body.isEmpty) return jsonError('Empty body', status: 400);

    final data = jsonDecode(body) as Map<String, dynamic>;
    final username = (data['username'] as String?)?.trim();
    final password = data['password'] as String?;

    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return jsonError('Missing fields', status: 400);
    }
    final stored = users[username];
    if (stored == null || stored != hashPassword(password)) {
      return jsonError('Invalid credentials', status: 401);
    }

    final token = generateToken(username);
    return jsonOk({'token': token});
  });

  // Profile (protected)
  router.get('/profile', (Request req) {
    final auth = req.headers['authorization'];
    if (auth == null || !auth.startsWith('Bearer ')) {
      return jsonError('Missing token', status: 401);
    }
    final token = auth.substring(7);
    try {
      final jwt = JWT.verify(token, SecretKey(jwtSecret));
      final username = jwt.payload['username'] as String;
      return jsonOk({'username': username, 'message': 'Welcome $username'});
    } catch (_) {
      return jsonError('Invalid/expired token', status: 401);
    }
  });

  return router;
}

Future<void> main() async {
  final router = buildRouter();

  // Middlewares: logging, CORS, JSON default headers
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders()) // allows requests from emulator / web
      .addHandler(router);

const port = 3000;
final server = await serve(handler, InternetAddress.anyIPv4, port);
print('✅ Dart Auth API running on http://0.0.0.0:$port');
}