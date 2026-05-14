import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../lib/handlers.dart';
import '../lib/store.dart';

Middleware _cors() => (Handler inner) {
      return (Request req) async {
        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await inner(req);
        return response.change(headers: {
          ...response.headers,
          ..._corsHeaders,
        });
      };
    };

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

Future<void> main(List<String> args) async {
  final store = DataStore();
  await store.initialize();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(buildRouter(store).call);

  final port = int.tryParse(
        Platform.environment['PORT'] ?? (args.isNotEmpty ? args[0] : '8000'),
      ) ??
      8000;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';

  final server = await shelf_io.serve(handler, host, port);
  // ignore: avoid_print
  print('Santexnika backend ishga tushdi: http://$host:${server.port}');
}
