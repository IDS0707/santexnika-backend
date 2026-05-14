import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'store.dart';

Response _json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: const {'Content-Type': 'application/json; charset=utf-8'},
);

Future<Map<String, dynamic>> _readBody(Request req) async {
  final raw = await req.readAsString();
  if (raw.isEmpty) return {};
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  return {};
}

String _newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

Router buildRouter(DataStore store) {
  final r = Router();

  r.get('/health', (Request _) => _json({'status': 'ok'}));

  r.post('/auth/admin', (Request req) async {
    final body = await _readBody(req);
    final login = (body['login'] as String?)?.trim() ?? '';
    final password = (body['password'] as String?)?.trim() ?? '';
    final ok = await store.read((s) {
      final creds = s['admin_credentials'] as Map<String, dynamic>;
      return creds['login'] == login && creds['password'] == password;
    });
    return ok
        ? _json({'role': 'admin'})
        : _json({'error': 'invalid_credentials'}, status: 401);
  });

  r.post('/auth/driver', (Request req) async {
    final body = await _readBody(req);
    final login = (body['login'] as String?)?.trim() ?? '';
    final password = (body['password'] as String?)?.trim() ?? '';
    final driverId = await store.read<String?>((s) {
      final drivers = (s['drivers'] as List).cast<Map<String, dynamic>>();
      for (final d in drivers) {
        if (d['login'] == login && d['password'] == password) {
          return d['id'] as String;
        }
      }
      return null;
    });
    return driverId == null
        ? _json({'error': 'invalid_credentials'}, status: 401)
        : _json({'driver_id': driverId});
  });

  _crud(r, store, 'categories', 'cat',
      requiredFields: ['name', 'code']);
  _crud(r, store, 'products', 'prd', requiredFields: ['name', 'category_id', 'price', 'stock']);
  _crud(r, store, 'drivers', 'drv',
      requiredFields: ['name', 'phone', 'login', 'password']);

  r.get('/orders', (Request _) async {
    final list = await store.read((s) => s['orders'] as List);
    return _json(list);
  });

  r.post('/orders', (Request req) async {
    final body = await _readBody(req);
    final id = (body['id'] as String?) ?? _newId('ORD');
    final created = await store.write((s) {
      final list = (s['orders'] as List).cast<Map<String, dynamic>>();
      final record = Map<String, dynamic>.from(body);
      record['id'] = id;
      record['created_at'] ??= DateTime.now().toIso8601String();
      record['status'] ??= 'pending';
      list.add(record);
      return record;
    });
    return _json(created, status: 201);
  });

  r.patch('/orders/<id>', (Request req, String id) async {
    final body = await _readBody(req);
    final updated = await store.write((s) {
      final list = (s['orders'] as List).cast<Map<String, dynamic>>();
      final idx = list.indexWhere((o) => o['id'] == id);
      if (idx < 0) return null;
      list[idx] = {...list[idx], ...body};
      return list[idx];
    });
    return updated == null
        ? _json({'error': 'not_found'}, status: 404)
        : _json(updated);
  });

  r.delete('/orders/<id>', (Request _, String id) async {
    final ok = await store.write((s) {
      final list = (s['orders'] as List).cast<Map<String, dynamic>>();
      final before = list.length;
      list.removeWhere((o) => o['id'] == id);
      return list.length < before;
    });
    return ok
        ? _json({'deleted': id})
        : _json({'error': 'not_found'}, status: 404);
  });

  r.get('/applications', (Request _) async {
    final list = await store.read((s) => s['applications'] as List);
    return _json(list);
  });

  r.post('/applications', (Request req) async {
    final body = await _readBody(req);
    final id = (body['id'] as String?) ?? _newId('APP');
    final created = await store.write((s) {
      final list = (s['applications'] as List).cast<Map<String, dynamic>>();
      final record = Map<String, dynamic>.from(body);
      record['id'] = id;
      record['created_at'] ??= DateTime.now().toIso8601String();
      record['status'] ??= 'newRequest';
      list.add(record);
      return record;
    });
    return _json(created, status: 201);
  });

  r.patch('/applications/<id>', (Request req, String id) async {
    final body = await _readBody(req);
    final updated = await store.write((s) {
      final list = (s['applications'] as List).cast<Map<String, dynamic>>();
      final idx = list.indexWhere((o) => o['id'] == id);
      if (idx < 0) return null;
      list[idx] = {...list[idx], ...body};
      return list[idx];
    });
    return updated == null
        ? _json({'error': 'not_found'}, status: 404)
        : _json(updated);
  });

  r.get('/mobile/products', (Request _) async {
    final products = await store.read((s) => s['products'] as List);
    final categories = await store.read((s) => s['categories'] as List);
    final byId = {
      for (final c in categories.cast<Map<String, dynamic>>())
        c['id'] as String: c,
    };

    var counter = 0;
    final mapped = products.cast<Map<String, dynamic>>().map((p) {
      counter++;
      final cat = byId[p['category_id']];
      final catCode = (cat?['code'] ?? cat?['name'] ?? 'umumiy') as String;
      return {
        'id': counter,
        'name': p['name'],
        'category': catCode,
        'price': p['price'],
        'oldPrice': p['old_price'],
        'stock': p['stock'],
        'unit': 'dona',
        'badge': _badgeOrNull(p['badge'] as String?),
        'firm': null,
      };
    }).toList();

    return _json({'items': mapped});
  });

  r.post('/mobile/orders/sync', (Request req) async {
    final body = await _readBody(req);
    final orders = (body['orders'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (orders.isEmpty) return _json({'syncedOrderIds': <String>[]});

    final synced = await store.write<List<String>>((s) {
      final list = (s['orders'] as List).cast<Map<String, dynamic>>();
      final products = (s['products'] as List).cast<Map<String, dynamic>>();
      final saved = <String>[];
      for (final raw in orders) {
        final id = ((raw['id'] ?? raw['orderId']) as String?)?.trim();
        if (id == null || id.isEmpty) continue;
        final existing = list.indexWhere((o) => o['id'] == id);
        final record = _mobileOrderToServer(raw);
        record['id'] = id;
        if (existing >= 0) {
          list[existing] = {...list[existing], ...record};
        } else {
          list.add(record);
          // Yangi buyurtma — mahsulotlar stock'ini kamaytiramiz
          final items = (record['items'] as List).cast<Map<String, dynamic>>();
          for (final it in items) {
            final pidRaw = it['product_id'];
            final qty = (it['quantity'] as num?)?.toInt() ?? 0;
            if (qty <= 0) continue;
            // product_id mobile-dan integer ham, string ham bo'lishi mumkin
            final pIndex = products.indexWhere((p) =>
                p['id'].toString() == pidRaw.toString() ||
                p['sku']?.toString() == pidRaw.toString() ||
                p['name'] == it['name']);
            if (pIndex < 0) continue;
            final currentStock = (products[pIndex]['stock'] as num?)?.toInt() ?? 0;
            final newStock = (currentStock - qty).clamp(0, 1 << 31);
            products[pIndex]['stock'] = newStock;
            final sold = (products[pIndex]['sold_count'] as num?)?.toInt() ?? 0;
            products[pIndex]['sold_count'] = sold + qty;
          }
        }
        saved.add(id);
      }
      return saved;
    });
    return _json({'syncedOrderIds': synced});
  });

  return r;
}

void _crud(
  Router r,
  DataStore store,
  String collection,
  String idPrefix, {
  required List<String> requiredFields,
}) {
  r.get('/$collection', (Request _) async {
    final list = await store.read((s) => s[collection] as List);
    return _json(list);
  });

  r.post('/$collection', (Request req) async {
    final body = await _readBody(req);
    for (final f in requiredFields) {
      if (body[f] == null) {
        return _json({'error': 'missing_field', 'field': f}, status: 400);
      }
    }
    final id = (body['id'] as String?) ?? _newId(idPrefix);
    final created = await store.write((s) {
      final list = (s[collection] as List).cast<Map<String, dynamic>>();
      final record = Map<String, dynamic>.from(body);
      record['id'] = id;
      record['created_at'] ??= DateTime.now().toIso8601String();
      list.add(record);
      return record;
    });
    return _json(created, status: 201);
  });

  r.put('/$collection/<id>', (Request req, String id) async {
    final body = await _readBody(req);
    final updated = await store.write((s) {
      final list = (s[collection] as List).cast<Map<String, dynamic>>();
      final idx = list.indexWhere((o) => o['id'] == id);
      if (idx < 0) return null;
      list[idx] = {...list[idx], ...body, 'id': id};
      return list[idx];
    });
    return updated == null
        ? _json({'error': 'not_found'}, status: 404)
        : _json(updated);
  });

  r.delete('/$collection/<id>', (Request _, String id) async {
    final ok = await store.write((s) {
      final list = (s[collection] as List).cast<Map<String, dynamic>>();
      final before = list.length;
      list.removeWhere((o) => o['id'] == id);
      return list.length < before;
    });
    return ok
        ? _json({'deleted': id})
        : _json({'error': 'not_found'}, status: 404);
  });
}

Map<String, dynamic> _mobileOrderToServer(Map<String, dynamic> raw) {
  return {
    'id': raw['id'],
    'customer_name': raw['customerName'] ?? raw['customer_name'] ?? 'Mehmon',
    'phone': raw['phone'] ?? '',
    'email': raw['email'],
    'address': raw['address'] ?? '',
    'items': (raw['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((it) => {
              'product_id': (it['productId'] ?? it['product_id'] ?? '')
                  .toString(),
              'name': it['name'] ?? '',
              'quantity': it['quantity'] ?? 1,
              'price': it['price'] ?? 0,
            })
        .toList(),
    'total': raw['total'] ?? 0,
    'status': raw['status'] ?? 'pending',
    'created_at':
        raw['createdAt'] ?? raw['created_at'] ?? DateTime.now().toIso8601String(),
    'driver_id': raw['driverId'] ?? raw['driver_id'],
    'latitude': raw['latitude'],
    'longitude': raw['longitude'],
    'source': 'mobile',
  };
}

String? _badgeOrNull(String? b) {
  if (b == null || b == 'none' || b.isEmpty) return null;
  return b;
}
