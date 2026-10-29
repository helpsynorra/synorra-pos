import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/inventory_item.dart';
import '../models/void_request.dart';
import '../models/restock_record.dart';
import '../models/staff_user.dart';
import '../models/login_activity.dart';

class SupabaseService {
  String? _activeAdminApiUrl;
  String? _posApiToken;

  bool get isInitialized => true;
  String? get activeAdminApiUrl => _activeAdminApiUrl;
  bool get hasPosApiToken => _posApiToken?.isNotEmpty == true;
  bool get isPosApiTokenExpired {
    final token = _posApiToken;
    if (token == null || token.isEmpty) return true;
    try {
      final payload = token.split('.').first;
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      ) as Map;
      final expiry = decoded['exp'];
      return expiry is! num ||
          expiry <= DateTime.now().millisecondsSinceEpoch / 1000;
    } catch (_) {
      return true;
    }
  }

  void setPosApiToken(String? token) {
    _posApiToken = token;
  }

  Map<String, String> get _restHeaders => const {
        'apikey': SupabaseConfig.publishableKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<bool> initialize({
    String? url,
    String? anonKey,
    String? adminApiUrl,
  }) async {
    _activeAdminApiUrl = adminApiUrl ?? SupabaseConfig.adminApiBaseUrl;
    return true;
  }

  Map<String, String> _posApiHeaders({bool authenticated = true}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authenticated && _posApiToken != null)
          'Authorization': 'Bearer $_posApiToken',
      };

  Uri get _posApiUri => Uri.parse(
        _activeAdminApiUrl ?? SupabaseConfig.adminApiBaseUrl,
      );

  Future<Map<String, dynamic>> _postPosApi(
    Map<String, dynamic> payload, {
    bool authenticated = true,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final response = await http
        .post(
          _posApiUri,
          headers: _posApiHeaders(authenticated: authenticated),
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          decoded['error']?.toString() ?? 'POS API request failed.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _getPosApi() async {
    final response = await http
        .get(_posApiUri, headers: _posApiHeaders())
        .timeout(const Duration(seconds: 20));
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          decoded['error']?.toString() ?? 'POS API request failed.');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> _restSelect(String queryPath) async {
    final uri = Uri.parse('${SupabaseConfig.restBaseUrl}/$queryPath');
    final response = await http
        .get(uri, headers: _restHeaders)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    throw Exception(
        'Supabase SELECT failed (${response.statusCode}): ${response.body}');
  }

  /// Authenticates staff through the Vercel POS API and keeps its signed token.
  Future<Map<String, dynamic>> authenticateStaff(
    String username,
    String password, {
    String email = '',
    bool persistSessionToken = true,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final cleanUsername = username.trim().toLowerCase();

    if ((cleanUsername.isEmpty && email.trim().isEmpty) || password.isEmpty) {
      return {
        'ok': false,
        'error': 'Please enter your email and current password'
      };
    }

    try {
      final result = await _postPosApi(
        {
          'action': 'auth',
          'username': cleanUsername,
          'email': email.trim().toLowerCase(),
          'password': password,
        },
        authenticated: false,
        timeout: timeout,
      );
      if (result['ok'] == true && result['requiresPasswordChange'] == true) {
        return {'ok': true, 'requiresPasswordChange': true};
      }
      if (result['ok'] != true || result['user'] is! Map) {
        debugPrint(
          'POS API auth rejected (API: $_posApiUri): '
          '${result['error'] ?? 'Invalid login credentials'}',
        );
        return {
          'ok': false,
          'error': result['error'] ?? 'Invalid login credentials'
        };
      }
      final token = result['token']?.toString() ?? '';
      if (token.isEmpty) {
        return {
          'ok': false,
          'error': 'The POS API did not return a session token.'
        };
      }
      if (persistSessionToken) _posApiToken = token;
      return {
        'ok': true,
        'user': StaffUser.fromJson(
            Map<String, dynamic>.from(result['user'] as Map)),
        'token': token,
      };
    } on TimeoutException catch (e) {
      debugPrint('POS API auth network error (API: $_posApiUri): $e');
      return {
        'ok': false,
        'error': 'Unable to verify credentials while offline',
        'offline': true,
      };
    } on http.ClientException catch (e) {
      debugPrint('POS API auth network error (API: $_posApiUri): $e');
      return {
        'ok': false,
        'error': 'Unable to verify credentials while offline',
        'offline': true,
      };
    } on SocketException catch (e) {
      debugPrint('POS API auth network error (API: $_posApiUri): $e');
      return {
        'ok': false,
        'error': 'Unable to verify credentials while offline',
        'offline': true,
      };
    } on HandshakeException catch (e) {
      debugPrint('POS API auth network error (API: $_posApiUri): $e');
      return {
        'ok': false,
        'error': 'Unable to verify credentials while offline',
        'offline': true,
      };
    } catch (e) {
      debugPrint('POS API auth error (API: $_posApiUri): $e');
      final error = e.toString().replaceFirst('Exception: ', '').trim();
      return {
        'ok': false,
        'error': error.isEmpty ? 'Unable to verify credentials' : error,
      };
    }
  }

  /// First sign-in for an Owner account created by the host. It verifies the
  /// issued username/password and attaches the Owner's email to that account.
  Future<Map<String, dynamic>> authenticateNewOwner({
    required String email,
    required String username,
    required String password,
    required bool legalAccepted,
    bool persistSessionToken = true,
  }) async {
    if (email.trim().isEmpty ||
        username.trim().isEmpty ||
        password.isEmpty ||
        !legalAccepted) {
      return {
        'ok': false,
        'error': 'Complete the required registration fields and legal consent.',
      };
    }

    try {
      final result = await _postPosApi(
        {
          'action': 'new_owner_login',
          'email': email.trim().toLowerCase(),
          'username': username.trim().toLowerCase(),
          'password': password,
          'legalAccepted': legalAccepted,
        },
        authenticated: false,
      );
      if (result['ok'] == true && result['requiresPasswordChange'] == true) {
        return {'ok': true, 'requiresPasswordChange': true};
      }
      if (result['ok'] != true || result['user'] is! Map) {
        return {
          'ok': false,
          'error': result['error'] ?? 'Invalid Owner credentials',
        };
      }
      final token = result['token']?.toString() ?? '';
      if (token.isEmpty) {
        return {
          'ok': false,
          'error': 'The POS API did not return a session token.'
        };
      }
      if (persistSessionToken) _posApiToken = token;
      return {
        'ok': true,
        'user': StaffUser.fromJson(
          Map<String, dynamic>.from(result['user'] as Map),
        ),
        'token': token,
      };
    } on TimeoutException catch (e) {
      debugPrint('New Owner login network error (API: $_posApiUri): $e');
      return {
        'ok': false,
        'error': 'Internet is required for New Login.',
        'offline': true
      };
    } on http.ClientException catch (e) {
      debugPrint('New Owner login network error (API: $_posApiUri): $e');
      return {
        'ok': false,
        'error': 'Internet is required for New Login.',
        'offline': true
      };
    } catch (e) {
      debugPrint('New Owner login error (API: $_posApiUri): $e');
      return {'ok': false, 'error': 'Unable to verify Owner credentials'};
    }
  }

  Future<Map<String, dynamic>> changeCashierPassword({
    required String email,
    required String password,
    required String newPassword,
  }) async {
    try {
      final result = await _postPosApi(
        {
          'action': 'change_cashier_password',
          'email': email.trim().toLowerCase(),
          'password': password,
          'newPassword': newPassword,
        },
        authenticated: false,
      );
      if (result['ok'] != true || result['user'] is! Map) {
        return {
          'ok': false,
          'error': result['error'] ?? 'Could not change password.'
        };
      }
      final token = result['token']?.toString() ?? '';
      if (token.isEmpty) {
        return {
          'ok': false,
          'error': 'The POS API did not return a session token.'
        };
      }
      _posApiToken = token;
      return {
        'ok': true,
        'user': StaffUser.fromJson(
            Map<String, dynamic>.from(result['user'] as Map)),
        'token': token,
      };
    } on TimeoutException {
      return {
        'ok': false,
        'error': 'Connect to the internet to set your new password.'
      };
    } on http.ClientException {
      return {
        'ok': false,
        'error': 'Connect to the internet to set your new password.'
      };
    } catch (e) {
      return {'ok': false, 'error': 'Could not change password: $e'};
    }
  }

  Future<void> deleteOwnerAccount(String password) async {
    final result = await _postPosApi({
      'action': 'delete_owner_account',
      'password': password,
      'confirmation': 'DELETE MY ACCOUNT',
    });
    if (result['ok'] != true) {
      throw Exception(
          result['error']?.toString() ?? 'Unable to delete account.');
    }
  }

  /// Fetches the centralized store through the signed Vercel POS API.
  Future<Map<String, dynamic>?> fetchFullStore() async {
    try {
      return await _getPosApi();
    } catch (e) {
      debugPrint('POS API fetchFullStore error: $e');
      return null;
    }
  }

  @Deprecated('Use fetchFullStore() through the authenticated POS API.')
  Future<Map<String, dynamic>?> fetchFullStoreDirect() async {
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _restSelect(
            '${SupabaseConfig.tablePosState}?select=*&id=eq.${SupabaseConfig.posStateId}'),
        _restSelect(
            '${SupabaseConfig.tableStaffUsers}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableMenuCategories}?select=*&order=name.asc'),
        _restSelect(
            '${SupabaseConfig.tableMenuItems}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableInventoryItems}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableOrders}?select=*&deleted_at=is.null&order=created_at.desc&limit=200'),
        _restSelect(
            '${SupabaseConfig.tableOrderItems}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableUsageLogs}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableRestocks}?select=*&order=created_at.desc'),
        _restSelect(
            '${SupabaseConfig.tableCostings}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableCostingIngredients}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableRecipes}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableRecipeCostings}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableRecipeCostingMenuItems}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableRecipeCostingIngredients}?select=*&order=created_at.asc'),
        _restSelect(
            '${SupabaseConfig.tableLoginActivity}?select=*&order=at.desc&limit=200'),
        _restSelect(
            '${SupabaseConfig.tableVoidRequests}?select=*&order=requested_at.desc&limit=100'),
      ]);

      final posRows = results[0];
      final posRow = posRows.isNotEmpty ? posRows.first : null;
      final staffRows = results[1];
      final catRows = results[2];
      final menuRows = results[3];
      final invRows = results[4];
      final orderRows = results[5];
      final activeOrderIds = orderRows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final orderItemRows = results[6];
      final usageLogRows = results[7];
      final restockRows = results[8];
      final costingRows = results[9];
      final costingIngRows = results[10];
      final recipeRows = results[11];
      final rcRows = results[12];
      final rcMenuRows = results[13];
      final rcIngRows = results[14];
      final loginRows = results[15];
      final voidRows = results[16];

      final catById = <String, String>{};
      final categories = <String>[];
      for (final row in catRows) {
        final id = row['id']?.toString() ?? '';
        final name = row['name']?.toString() ?? '';
        if (id.isNotEmpty && name.isNotEmpty) {
          catById[id] = name;
          if (!categories.any((c) => c.toLowerCase() == name.toLowerCase())) {
            categories.add(name);
          }
        }
      }

      final mappedMenu = menuRows.map((row) {
        final catId = row['category_id']?.toString() ?? '';
        final category =
            catById[catId] ?? row['category']?.toString() ?? 'Other';
        if (category.isNotEmpty &&
            !categories.any((c) => c.toLowerCase() == category.toLowerCase())) {
          categories.add(category);
        }
        return {
          ...row,
          'category': category,
        };
      }).toList();

      final itemsByOrder = <String, List<Map<String, dynamic>>>{};
      for (final item in orderItemRows) {
        final orderId = item['order_id']?.toString() ?? '';
        itemsByOrder.putIfAbsent(orderId, () => []).add(item);
      }

      final mappedOrders = orderRows.map((row) {
        final id = row['id']?.toString() ?? '';
        return {
          ...row,
          'items': itemsByOrder[id] ?? [],
          'isSynced': true,
        };
      }).toList();

      final recipesMap = <String, List<Map<String, dynamic>>>{};
      for (final r in recipeRows) {
        final menuId = r['menu_item_id']?.toString() ?? '';
        if (menuId.isEmpty) continue;
        recipesMap.putIfAbsent(menuId, () => []).add({
          'inventoryItemId': r['inventory_item_id']?.toString() ?? '',
          'name': '',
          'amount': (r['amount'] as num?)?.toDouble() ?? 0.0,
          'unit': r['unit']?.toString() ?? 'pcs',
        });
      }

      final mappedRecipeCostings = rcRows.map((row) {
        final rcId = row['id']?.toString() ?? '';
        return {
          'id': rcId,
          'name': row['name']?.toString() ?? '',
          'menuItems': rcMenuRows
              .where((m) => m['recipe_costing_id']?.toString() == rcId)
              .map((m) => m['menu_item_name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList(),
          'ingredients': rcIngRows
              .where((i) => i['recipe_costing_id']?.toString() == rcId)
              .map((i) => {
                    'inventoryItemId': i['inventory_item_id']?.toString() ?? '',
                    'name': i['name']?.toString() ?? '',
                    'amount': (i['amount'] as num?)?.toDouble() ?? 0.0,
                    'unit': i['unit']?.toString() ?? 'pcs',
                  })
              .toList(),
          'hotCupInventoryItemId': row['hot_cup_inventory_item_id'],
          'icedCupInventoryItemId': row['iced_cup_inventory_item_id'],
          'otherCupInventoryItemId': row['other_cup_inventory_item_id'],
          'extraCupInventoryItemIds':
              row['extra_cup_inventory_item_ids'] ?? const <String>[],
          'cupRecipes': row['cup_recipes'] is Map
              ? Map<String, dynamic>.from(row['cup_recipes'] as Map)
              : <String, dynamic>{},
        };
      }).toList();

      final mappedCostings = costingRows.map((row) {
        final cId = row['id']?.toString() ?? '';
        return {
          'id': cId,
          'productName': row['product_name']?.toString() ?? '',
          'ingredients': costingIngRows
              .where((i) => i['costing_id']?.toString() == cId)
              .map((i) => {
                    'name': i['name']?.toString() ?? '',
                    'amount': (i['amount'] as num?)?.toDouble() ?? 0.0,
                    'unit': i['unit']?.toString() ?? 'pcs',
                    'outputCups': (i['output_cups'] as num?)?.toDouble(),
                  })
              .toList(),
        };
      }).toList();

      final mappedUsageLogs = usageLogRows
          .where((row) {
            final orderId = row['order_id']?.toString() ?? '';
            return orderId.isEmpty || activeOrderIds.contains(orderId);
          })
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'orderId': row['order_id']?.toString() ?? '',
                'orderItemId': row['order_item_id']?.toString() ?? '',
                'inventoryItemId': row['inventory_item_id']?.toString(),
                'date': row['created_at']?.toString() ?? '',
                'itemName': row['item_name_snapshot']?.toString() ?? '',
                'usedAmount': (row['used_amount'] as num?)?.toDouble() ?? 0.0,
                'unit': row['unit']?.toString() ?? 'pcs',
              })
          .toList();

      return {
        'ok': true,
        'pos': posRow != null
            ? {
                'isOpen': posRow['is_open'] == true,
                'openedAt': posRow['opened_at'],
                'openedBy': posRow['opened_by_name'] ?? posRow['opened_by'],
              }
            : {'isOpen': false, 'openedAt': null, 'openedBy': null},
        'users': staffRows,
        'categories': categories,
        'menu': mappedMenu,
        'inventory': invRows,
        'orders': mappedOrders,
        'restocks': restockRows,
        'voidRequests': voidRows,
        'loginActivity': loginRows,
        'recipes': recipesMap,
        'recipeCostings': mappedRecipeCostings,
        'costings': mappedCostings,
        'usageLogs': mappedUsageLogs,
      };
    } catch (e) {
      debugPrint('Direct Supabase fetchFullStore error: $e');
      return null;
    }
  }

  // --- Direct Table Queries ---

  Future<List<MenuItem>?> fetchMenu() async {
    try {
      final catRes = await _restSelect(
          '${SupabaseConfig.tableMenuCategories}?select=id,name');
      final catMap = <String, String>{};
      for (final row in catRes) {
        catMap[row['id'].toString()] = row['name'].toString();
      }

      final res = await _restSelect(
          '${SupabaseConfig.tableMenuItems}?select=*&order=created_at.asc');
      return res.map((map) {
        final catId = map['category_id']?.toString();
        if (catId != null && catMap.containsKey(catId)) {
          map['category'] = catMap[catId];
        }
        return MenuItem.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching menu: $e');
      return null;
    }
  }

  Future<List<String>?> fetchCategories() async {
    try {
      final res = await _restSelect(
          '${SupabaseConfig.tableMenuCategories}?select=name&order=name.asc');
      final list = res.map((e) => e['name'].toString()).toList();
      return ['All', ...list.where((c) => c.toLowerCase() != 'all')];
    } catch (e) {
      debugPrint('Error fetching categories: $e');
      return null;
    }
  }

  Future<List<InventoryItem>?> fetchInventory() async {
    try {
      final res = await _restSelect(
          '${SupabaseConfig.tableInventoryItems}?select=*&order=created_at.asc');
      return res.map((e) => InventoryItem.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error fetching inventory: $e');
      return null;
    }
  }

  Future<List<RestockRecord>?> fetchRestocks() async {
    try {
      final res = await _restSelect(
          '${SupabaseConfig.tableRestocks}?select=*&order=created_at.desc&limit=200');
      return res.map((map) {
        map['isSynced'] = true;
        return RestockRecord.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching restocks: $e');
      return null;
    }
  }

  Future<List<StaffUser>?> fetchStaff() async {
    try {
      final res = await _restSelect(
          '${SupabaseConfig.tableStaffUsers}?select=*&order=created_at.asc');
      return res.map((e) => StaffUser.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error fetching staff: $e');
      return null;
    }
  }

  Future<List<Order>?> fetchRecentOrders() async {
    try {
      final ordersRes = await _restSelect(
          '${SupabaseConfig.tableOrders}?select=*&deleted_at=is.null&order=created_at.desc&limit=100');
      final itemsRes =
          await _restSelect('${SupabaseConfig.tableOrderItems}?select=*');

      final itemsByOrder = <String, List<Map<String, dynamic>>>{};
      for (final item in itemsRes) {
        final orderId = item['order_id']?.toString() ?? '';
        itemsByOrder.putIfAbsent(orderId, () => []).add(item);
      }

      final orders = <Order>[];
      for (final orderMap in ordersRes) {
        orderMap['items'] = itemsByOrder[orderMap['id']] ?? [];
        orderMap['isSynced'] = true;
        orders.add(Order.fromJson(orderMap));
      }
      return orders;
    } catch (e) {
      debugPrint('Error fetching orders: $e');
      return null;
    }
  }

  // --- Transactions & Atomic RPC Operations (Direct Supabase PostgREST) ---

  Future<Map<String, dynamic>> pushOrderAtomic(
    Order order,
    List<Map<String, dynamic>> deductions, {
    String? managerUsername,
    String? managerPassword,
  }) async {
    try {
      final itemsPayload = order.items
          .map((i) => {
                'productId': i.productId,
                'name': i.name,
                'qty': i.qty,
                'price': i.price.round(),
                'serviceMode': order.serviceMode,
                if (i.style != null) 'style': i.style,
                if (i.category != null) 'category': i.category,
                'addons': i.addons.map((a) => a.toJson()).toList(),
              })
          .toList();

      final result = await _postPosApi({
        'action': order.voided ? 'void_checkout' : 'create_order',
        'order': {
          'id': order.id,
          'createdAt': order.createdAt,
          'baristaName': order.baristaName,
          'baristaUserId': order.baristaUserId,
          'items': itemsPayload,
          'subtotal': order.subtotal.round(),
          'discount': order.discount.round(),
          'promoLabel': order.promoLabel,
          'promoItemIndex': order.promoItemIndex,
          'promoItemQty': order.promoItemQty,
          'total': order.total.round(),
          'paymentMethod': order.paymentMethod,
          'serviceMode': order.serviceMode,
          'ticketNo': order.isWaste ? '' : order.ticketNo,
          'paid': order.paid.round(),
          'change': order.change.round(),
          'voided': order.voided,
          'voidReason': order.isWaste
              ? (order.wasteReason ?? order.voidReason)
              : order.voidReason,
          if (order.wasteReason != null) 'wasteReason': order.wasteReason,
        },
        'deductions': deductions,
        'managerUsername': managerUsername,
        'managerPassword': managerPassword,
      });
      return {
        'ok': result['ok'] == true,
        'ticketNo': result['ticketNo']?.toString() ?? order.ticketNo,
        if (result['error'] != null) 'error': result['error'],
      };
    } catch (e) {
      final msg = e.toString();
      debugPrint('POS API order sync failed (${order.id}): $msg');
      return {
        'ok': false,
        'error': msg,
        'retryable': e is http.ClientException || e is TimeoutException,
      };
    }
  }

  Future<Map<String, dynamic>> voidOrderAtomic(
    String orderId,
    String reason,
    String? voidedBy, {
    String? managerUsername,
    String? managerPassword,
  }) async {
    try {
      final res = await _postPosApi({
        'action': 'void_order',
        'orderId': orderId,
        'reason': reason,
        'voidedBy': voidedBy,
        'managerUsername': managerUsername,
        'managerPassword': managerPassword,
      });
      return {
        'ok': res['ok'] == true,
        if (res['voidedBy'] != null) 'voidedBy': res['voidedBy'],
        if (res['voidedByName'] != null) 'voidedByName': res['voidedByName'],
        if (res['error'] != null) 'error': res['error']
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<bool> pushRestockAtomic(RestockRecord record) async {
    try {
      final result = await _postPosApi({
        'action': 'create_restock',
        'restock': {
          'id': record.id,
          'inventoryItemId': record.inventoryItemId,
          'itemName': record.itemName,
          'quantityAdded': record.quantityAdded,
          'date': record.date,
          'purchaseQty': record.purchaseQty,
          'purchaseUnit': record.purchaseUnit,
        },
      });
      return result['ok'] == true;
    } catch (e) {
      final message = e.toString();
      if (message.contains('duplicate key')) return true;
      debugPrint('Restock RPC error: $e');
      return false;
    }
  }

  Future<bool> deleteRestockAtomic(String id) async {
    try {
      final result = await _postPosApi({'action': 'delete_restock', 'id': id});
      return result['ok'] == true;
    } catch (e) {
      if (e.toString().contains('delete_restock_atomic: restock') &&
          e.toString().contains('not found')) {
        return true;
      }
      debugPrint('Delete restock RPC error: $e');
      return false;
    }
  }

  Future<bool> upsertInventoryItem(InventoryItem item) async {
    try {
      final result = await _postPosApi({
        'action': 'upsert_inventory_item',
        'item': {
          'id': item.id,
          'name': item.name,
          'unit': item.unit,
          'cost': item.cost,
          'stock': item.stock,
          'maxStock': item.maxStock,
          'openingStock': item.openingStock,
          'purchaseUnitSize': item.purchaseUnitSize,
          'cupUsageAmount': item.cupUsageAmount,
          'cupsMake': item.cupsMake,
        },
      });
      return result['ok'] == true;
    } catch (e) {
      debugPrint('Upsert inventory error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> deleteInventoryItem(String id) async {
    try {
      return await _postPosApi({'action': 'delete_inventory_item', 'id': id});
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<bool> pushVoidRequest(VoidRequest request) async {
    try {
      final result = await _postPosApi({
        'action': 'create_void_request',
        'request': request.toJson(),
      });
      return result['ok'] == true;
    } catch (e) {
      debugPrint('Push void request error (API: $_posApiUri): $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> pushLoginActivity(
    LoginActivity activity, {
    String? username,
    String? password,
    Uint8List? photoBytes,
  }) async {
    try {
      final result = await _postPosApi({
        'action': const {'barista', 'pos_cashier'}
                .contains(activity.role.trim().toLowerCase())
            ? 'barista_shift_activity'
            : 'login_activity',
        'activity': activity.toJson(),
        if (username != null || password != null)
          'credentials': {
            'username': username ?? '',
            'password': password ?? '',
          },
        if (photoBytes != null) 'photoBase64': base64Encode(photoBytes),
      });
      return result;
    } catch (e) {
      debugPrint('Push login activity error (API: $_posApiUri): $e');
      return {
        'ok': false,
        'error': e.toString().replaceFirst('Exception: ', '')
      };
    }
  }
}
