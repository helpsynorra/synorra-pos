class SupabaseConfig {
  static const String projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zdkemoxxguiowbmznxtj.supabase.co',
  );
  static String get restBaseUrl => '$projectUrl/rest/v1';

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_9trZUPUbKwKoAvif5vW59A_nghPPg-E',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpka2Vtb3h4Z3Vpb3dibXpueHRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIzMDQ3OTYsImV4cCI6MjEwNzg4MDc5Nn0.bKjLfOwbxKUfUOcxevJQrQVpfMJLbWbmFDxfnGIIl7U',
  );

  static String get supabaseUrl => projectUrl;
  static String get supabaseAnonKey => anonKey;
  static String get supabasePublishableKey => publishableKey;

  static const String _defaultPosApiUrl =
      'https://synorra-pos.click/api/sync';
  static const String _configuredPosApiUrl = String.fromEnvironment(
    'POS_API_URL',
    defaultValue: _defaultPosApiUrl,
  );

  static String get adminApiBaseUrl => normalizePosApiUrl(_configuredPosApiUrl);

  static String normalizePosApiUrl(String? value) {
    final candidate = value?.trim();
    final uri = candidate == null ? null : Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.host == 'https' ||
        uri.host == 'http' ||
        !uri.path.toLowerCase().replaceFirst(RegExp(r'/$'), '').endsWith('/api/sync')) {
      return _defaultPosApiUrl;
    }
    return uri.replace(query: null, fragment: null).toString();
  }

  static final List<String> fallbackApiBaseUrls = [adminApiBaseUrl];

  // Exact Supabase table names matching the web app & migrations
  static const String tablePosState = 'pos_state';
  static const String tableStaffUsers = 'staff_users';
  static const String tableMenuCategories = 'menu_categories';
  static const String tableMenuItems = 'menu_items';
  static const String tablePromotions = 'promotions';
  static const String tableInventoryItems = 'inventory_items';
  static const String tableOrders = 'orders';
  static const String tableOrderItems = 'order_items';
  static const String tableUsageLogs = 'usage_logs';
  static const String tableRestocks = 'restocks';
  static const String tableCostings = 'costings';
  static const String tableCostingIngredients = 'costing_ingredients';
  static const String tableRecipes = 'recipes';
  static const String tableRecipeCostings = 'recipe_costings';
  static const String tableRecipeCostingMenuItems = 'recipe_costing_menu_items';
  static const String tableRecipeCostingIngredients =
      'recipe_costing_ingredients';
  static const String tableLoginActivity = 'login_activity';
  static const String tableOffRequests = 'off_requests';
  static const String tableVoidRequests = 'void_requests';

  // Exact Postgres RPC function names
  static const String rpcCreateOrderAtomic = 'create_order_atomic';
  static const String rpcVoidOrderAtomic = 'void_order_atomic';
  static const String rpcDeleteOrderAtomic = 'delete_order_atomic';
  static const String rpcCreateRestockAtomic = 'create_restock_atomic';
  static const String rpcEditRestockAtomic = 'edit_restock_atomic';
  static const String rpcDeleteRestockAtomic = 'delete_restock_atomic';
  static const String rpcApproveVoidRequestAtomic =
      'approve_void_request_atomic';
  static const String rpcSaveCosting = 'save_costing';
  static const String rpcSaveRecipeCosting = 'save_recipe_costing';
  static const String rpcRenameMenuCategory = 'rename_menu_category';

  static const String posStateId = 'synorra-pos';
}
 
