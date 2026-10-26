import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/proof_of_visit_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/credit_page.dart';
import 'package:selecta_ops/views/pages/dashboard/delivery_page.dart';
import 'package:selecta_ops/views/pages/sidebar/hapistore_page.dart';
import 'package:selecta_ops/views/pages/dashboard/pjphistory_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/services/store_auth_service.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/models/scanning.dart';
import 'package:selecta_ops/services/scanning_services.dart';
import 'package:selecta_ops/views/pages/dashboard/scanning_page.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Comprehensive Per-Store 360° Profile Screen.
///
/// Provides field agents, salesmen, and dealers with a unified 360-degree view
/// of a customer account:
/// - Store identity, contact, address, PJP schedule, GPS location.
/// - One-tap quick actions: Call, SMS, Directions, Book Order, Settle Credit, Edit.
/// - Live analytics: Total lifetime revenue, order count, unpaid credit balance.
/// - Tabbed operational history: Orders & Deliveries, Credit Ledger, Freezer Assets, PJP Activity.
class StoreProfilePage extends StatefulWidget {
  final String? hapiStoreID;
  final Hapistore? hapistore;
  final String? storeName;

  const StoreProfilePage({
    super.key,
    this.hapiStoreID,
    this.hapistore,
    this.storeName,
  });

  @override
  State<StoreProfilePage> createState() => _StoreProfilePageState();
}

class _StoreProfilePageState extends State<StoreProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Hapistore _store;
  bool _isDealer = false;
  String _effectiveStoreId = '';
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final shortCurrency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _effectiveStoreId = widget.hapiStoreID ?? '';
    if (widget.hapistore != null) {
      _store = widget.hapistore!;
    } else {
      _store = Hapistore.empty();
      if (widget.storeName != null) {
        _store.storeName = widget.storeName!;
      }
      _fetchStoreDetails();
    }
    _tabController = TabController(length: 5, vsync: this);
    _checkRole();
  }

  Future<void> _fetchStoreDetails() async {
    try {
      if (widget.hapiStoreID != null && widget.hapiStoreID!.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection(HAPISTORE_COLLECTION_REF).doc(widget.hapiStoreID).get();
        if (doc.exists && mounted) {
          setState(() {
            _store = Hapistore.fromSnapshot(doc);
            _effectiveStoreId = doc.id;
          });
        }
      } else if (widget.storeName != null && widget.storeName!.isNotEmpty) {
        final query = await FirebaseFirestore.instance
            .collection(HAPISTORE_COLLECTION_REF)
            .where('storeName', isEqualTo: widget.storeName)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty && mounted) {
          setState(() {
            _store = Hapistore.fromSnapshot(query.docs.first);
            _effectiveStoreId = query.docs.first.id;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkRole() async {
    final dealer = await KVariables.getIsDealer();
    if (mounted) {
      setState(() => _isDealer = dealer);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1-TAP ACTION HANDLERS (Call, SMS, Directions, Book Order, Settle Credit)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _makePhoneCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      ShowMessage.error(context, 'No phone number available for this store.');
      return;
    }
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) ShowMessage.error(context, 'Could not initiate phone call.');
    }
  }

  Future<void> _sendSms(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      ShowMessage.error(context, 'No contact number available.');
      return;
    }
    final uri = Uri.parse('sms:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) ShowMessage.error(context, 'Could not open messaging app.');
    }
  }

  Future<void> _openDirections() async {
    if (_store.latitude != null && _store.longitude != null) {
      final lat = _store.latitude!;
      final lng = _store.longitude!;
      final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (_store.storeAddress.isNotEmpty) {
      final query = Uri.encodeComponent('${_store.storeName}, ${_store.storeAddress}');
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (mounted) {
      ShowMessage.alert(
        context,
        title: 'Location Unavailable',
        message: 'No GPS coordinates or valid address registered for this store.',
        icon: Icons.location_off_outlined,
      );
    }
  }

  Future<void> _bookOrderForStore() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookOrderPage(initialStoreName: _store.storeName),
      ),
    );
  }

  Future<void> _editStore() async {
    if (_effectiveStoreId.isEmpty) {
      ShowMessage.error(context, 'Store record not loaded yet.');
      return;
    }
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HapiStorePage(hapiStoreID: _effectiveStoreId, hapistore: _store),
      ),
    );
    if (updated == true && mounted) {
      // Reload store data
      final doc = await FirebaseFirestore.instance.collection(HAPISTORE_COLLECTION_REF).doc(_effectiveStoreId).get();
      if (doc.exists && mounted) {
        setState(() {
          _store = Hapistore.fromSnapshot(doc);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: _store.storeName,
          subtitle: _store.storeAddress.isNotEmpty ? _store.storeAddress : 'Store 360° Profile',
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF28303F) : Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF384152) : Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 19),
                    tooltip: 'Edit Store',
                    padding: EdgeInsets.zero,
                    onPressed: _editStore,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: _buildProfileHeader(colorScheme, isDark),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: isDark ? colorScheme.primary : colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    indicatorColor: colorScheme.primary,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dashboard_outlined, size: 17),
                            SizedBox(width: 6),
                            Text('Overview'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_bag_outlined, size: 17),
                            SizedBox(width: 6),
                            Text('Orders'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.credit_card_outlined, size: 17),
                            SizedBox(width: 6),
                            Text('Credit / AR'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.kitchen_outlined, size: 17),
                            SizedBox(width: 6),
                            Text('Assets'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 17),
                            SizedBox(width: 6),
                            Text('Visit Photos'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  colorScheme.surface,
                  isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(colorScheme, isDark),
              _buildOrdersTab(colorScheme, isDark),
              _buildCreditTab(colorScheme, isDark),
              _buildAssetsTab(colorScheme, isDark),
              _buildPhotosTab(colorScheme, isDark),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomActionBar(colorScheme, isDark),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP PROFILE HEADER & QUICK CONTACT BAR
  // ═══════════════════════════════════════════════════════════════════════════

  String _getStoreInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'ST';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }

  Widget _buildProfileHeader(ColorScheme colorScheme, bool isDark) {
    final hasContact = _store.storeContact.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.5),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Store Name + Squircle Initials Card
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [colorScheme.primary.withValues(alpha: 0.4), colorScheme.primary.withValues(alpha: 0.18)]
                        : [colorScheme.primary.withValues(alpha: 0.18), colorScheme.primary.withValues(alpha: 0.06)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: isDark ? 0.45 : 0.25),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _getStoreInitials(_store.storeName),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _store.storeName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, size: 15, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _store.storeAddress.isNotEmpty ? _store.storeAddress : 'No street address specified',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Operational Status Badges (Opening Date)
          if (_store.openingDate != null) ...[
            const SizedBox(height: 10),
            _buildBadge(
              icon: Icons.event_available_rounded,
              label: 'Opened ${DateFormat('MMM yyyy').format(_store.openingDate!.toDate())}',
              color: colorScheme.onSurfaceVariant,
              bgColor: isDark ? const Color(0xFF28303F) : const Color(0xFFF1F5F9),
              borderColor: isDark ? const Color(0xFF384152) : const Color(0xFFCBD5E1),
            ),
          ],

          const SizedBox(height: 12),

          // 1-Tap Field Action Row (Call, SMS, Navigate)
          Row(
            children: [
              Expanded(
                child: _buildActionPill(
                  icon: Icons.phone_rounded,
                  label: 'Call',
                  color: Colors.green,
                  onTap: hasContact ? () => _makePhoneCall(_store.storeContact) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionPill(
                  icon: Icons.sms_outlined,
                  label: 'SMS',
                  color: Colors.blue,
                  onTap: hasContact ? () => _sendSms(_store.storeContact) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionPill(
                  icon: Icons.near_me_outlined,
                  label: 'Navigate',
                  color: Colors.orange.shade800,
                  onTap: _openDirections,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isEnabled
                ? color.withValues(alpha: isDark ? 0.22 : 0.08)
                : Colors.grey.withValues(alpha: isDark ? 0.15 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEnabled
                  ? color.withValues(alpha: isDark ? 0.45 : 0.25)
                  : Colors.grey.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isEnabled ? color : Colors.grey),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isEnabled ? color : Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: OVERVIEW & KEY PERFORMANCE INDICATORS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab(ColorScheme colorScheme, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where('storeName', isEqualTo: _store.storeName)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        double lifetimeSales = 0;
        double outstandingCredit = 0;
        int totalOrders = docs.length;
        DateTime? lastOrderDate;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final amt = (data['orderAmount'] as num?)?.toDouble() ?? 0.0;
          final cred = (data['creditAmount'] as num?)?.toDouble() ?? 0.0;
          final credStatus = (data['creditStatus'] as String?) ?? '';
          final date = (data['deliveryDate'] as Timestamp?)?.toDate();

          lifetimeSales += amt;
          if (credStatus == CreditStatus.unpaid && cred > 0) {
            outstandingCredit += cred;
          }
          if (date != null && (lastOrderDate == null || date.isAfter(lastOrderDate))) {
            lastOrderDate = date;
          }
        }

        final avgOrder = totalOrders > 0 ? lifetimeSales / totalOrders : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 360 KPI Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Lifetime Sales',
                      value: shortCurrency.format(lifetimeSales),
                      icon: Icons.payments_rounded,
                      accentColor: Colors.green,
                      isDark: isDark,
                      badgeText: 'Revenue',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Unpaid Credit',
                      value: shortCurrency.format(outstandingCredit),
                      icon: Icons.credit_card_rounded,
                      accentColor: outstandingCredit > 0 ? Colors.red : Colors.grey,
                      isDark: isDark,
                      badgeText: outstandingCredit > 0 ? 'Overdue' : 'No Overdue',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Total Orders',
                      value: '$totalOrders',
                      icon: Icons.receipt_long_rounded,
                      accentColor: colorScheme.primary,
                      isDark: isDark,
                      badgeText: 'Delivered',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Avg Order Size',
                      value: shortCurrency.format(avgOrder),
                      icon: Icons.analytics_outlined,
                      accentColor: Colors.purple,
                      isDark: isDark,
                      badgeText: 'Per Order',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Store Information Card
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.55),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Store & Operational Details',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    _buildDetailRow(
                      'Store Code / ID',
                      _effectiveStoreId.isNotEmpty ? _effectiveStoreId : 'Pending Sync',
                      Icons.tag,
                      isCopyable: _effectiveStoreId.isNotEmpty,
                      isMonospace: true,
                    ),
                    Divider(height: 20, color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4)),
                    _buildDetailRow(
                      'Contact Number',
                      _store.storeContact.isNotEmpty ? _store.storeContact : 'Not specified',
                      Icons.phone_outlined,
                      isCopyable: _store.storeContact.isNotEmpty,
                    ),
                    Divider(height: 20, color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4)),
                    _buildDetailRow(
                      'PJP Schedule',
                      _store.pjpSchedule ?? 'Unassigned',
                      Icons.calendar_today_outlined,
                    ),
                    Divider(height: 20, color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4)),
                    _buildDetailRow(
                      'Last Visit Date',
                      _store.lastPjpVisit != null ? DateFormat('EEEE, d MMM yyyy').format(_store.lastPjpVisit!.toDate()) : 'No visits recorded yet',
                      Icons.history_rounded,
                    ),
                    Divider(height: 20, color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4)),
                    _buildDetailRow(
                      'Last Order Date',
                      lastOrderDate != null ? DateFormat('EEEE, d MMM yyyy').format(lastOrderDate) : 'No orders recorded yet',
                      Icons.local_shipping_outlined,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),
              _buildStoreAccountCard(colorScheme, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStoreAccountCard(ColorScheme colorScheme, bool isDark) {
    final hasAccount = _store.username != null && _store.username!.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Online Ordering & Login',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasAccount) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (_store.orderingEnabled ? Colors.green : Colors.orange)
                          .withValues(alpha: isDark ? 0.25 : 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (_store.orderingEnabled ? Colors.green : Colors.orange)
                            .withValues(alpha: isDark ? 0.45 : 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      _store.orderingEnabled ? 'Active' : 'Disabled',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _store.orderingEnabled ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            if (!hasAccount) ...[
              Text(
                'This store does not have an online ordering login yet. Create a store username to allow the store owner to browse products and submit orders directly.',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _effectiveStoreId.isEmpty ? null : _showCreateStoreLoginDialog,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Create Store Login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Store Username',
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '@${_store.username}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: _store.username!));
                                ShowMessage.info(context, 'Username copied to clipboard.');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.copy_rounded, size: 15, color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isDealer) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _showResetPasswordDialog,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.lock_reset_rounded, size: 16),
                      label: const Text('Reset Password', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ],
              ),
              const Divider(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Store Self-Ordering', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _store.orderingEnabled
                      ? 'Store can place orders through their portal.'
                      : 'Ordering is temporarily paused for this store.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                value: _store.orderingEnabled,
                onChanged: _toggleOrderingEnabled,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleOrderingEnabled(bool value) async {
    try {
      await StoreAuthService().setOrderingEnabled(storeId: _effectiveStoreId, enabled: value);
      if (mounted) {
        setState(() {
          _store = _store.copyWith(orderingEnabled: value);
        });
        ShowMessage.success(context, value ? 'Store ordering enabled.' : 'Store ordering disabled.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to update ordering status: $e');
    }
  }

  Future<void> _showCreateStoreLoginDialog() async {
    final cleaned = _store.storeName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '')
        .trim();
    final initialSuggestion = cleaned.length >= 4 ? cleaned : 'store_${_effectiveStoreId.substring(0, _effectiveStoreId.length.clamp(0, 6))}';

    final usernameController = TextEditingController(text: initialSuggestion);
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogInnerContext, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1_rounded),
                  SizedBox(width: 8),
                  Text('Create Store Login'),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Provide a unique username for "${_store.storeName}". The store owner will use this to sign in.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixText: '@',
                        border: OutlineInputBorder(),
                        helperText: '4-20 chars: lowercase letters, numbers, ., _, -',
                      ),
                      validator: (val) => StoreAuthService.validateUsername(val),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSubmitting = true);
                          try {
                            final currentUser = await KVariables.getUser();
                            final currentDealer = currentUser?.dealerName ?? '';
                            final result = await StoreAuthService().createStoreAccount(
                              storeId: _effectiveStoreId,
                              storeName: _store.storeName,
                              username: usernameController.text.trim().toLowerCase(),
                              dealerName: currentDealer,
                            );

                            if (mounted) {
                              setState(() {
                                _store = _store.copyWith(
                                  username: result.user.username,
                                  storeUserUid: result.uid,
                                  orderingEnabled: true,
                                );
                              });
                            }

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            if (mounted) {
                              _showPasswordCredentialsDialog(
                                username: result.user.username,
                                temporaryPassword: result.temporaryPassword,
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (mounted) {
                              ShowMessage.error(context, 'Failed to create login: $e');
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create Account'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showResetPasswordDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Store Password?'),
        content: Text(
          'This will generate a new temporary password for "@${_store.username}". '
          'The store owner will be required to change their password upon their next login.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: const AlertDialog(
          content: Row(
            children: [
              SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(width: 20),
              Expanded(child: Text('Resetting password...')),
            ],
          ),
        ),
      ),
    );

    String? tempPassword;
    Object? error;
    try {
      tempPassword = await StoreAuthService().resetStorePassword(
        storeId: _effectiveStoreId,
        storeName: _store.storeName,
        username: _store.username!,
      );
    } catch (e) {
      error = e;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (error != null) {
      ShowMessage.error(context, 'Failed to reset password: $error');
      return;
    }

    _showPasswordCredentialsDialog(
      username: _store.username!,
      temporaryPassword: tempPassword!,
      isReset: true,
    );
  }

  void _showPasswordCredentialsDialog({
    required String username,
    required String temporaryPassword,
    bool isReset = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(isReset ? Icons.lock_reset_rounded : Icons.check_circle_rounded, color: Colors.green),
            const SizedBox(width: 8),
            Text(isReset ? 'Password Reset' : 'Store Account Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isReset
                  ? 'A temporary password has been generated. Please provide these credentials to the store owner:'
                  : 'The store account is ready. Please share these credentials with the store owner:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Username: @$username', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text('Temporary Password: $temporaryPassword', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Important: The store will be prompted to create their own secure password immediately upon logging in.',
              style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Credentials'),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: 'Selecta Ops Store Login:\nUsername: $username\nTemporary Password: $temporaryPassword',
              ));
              ShowMessage.info(context, 'Credentials copied to clipboard.');
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    String? badgeText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: accentColor),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.22 : 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: accentColor.withValues(alpha: isDark ? 0.45 : 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon, {
    bool isCopyable = false,
    bool isMonospace = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              if (isMonospace)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF28303F) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark ? const Color(0xFF384152) : const Color(0xFFCBD5E1),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '# $value',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (isCopyable) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: value));
                          ShowMessage.info(context, 'Copied $label to clipboard');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.copy_rounded, size: 13, color: colorScheme.primary),
                        ),
                      ),
                    ],
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (isCopyable)
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: value));
                          ShowMessage.info(context, 'Copied $label to clipboard');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.copy_rounded, size: 14, color: colorScheme.primary),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: ORDERS & DELIVERIES HISTORY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOrdersTab(ColorScheme colorScheme, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where('storeName', isEqualTo: _store.storeName)
          .orderBy('deliveryDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState('No Orders Yet', 'This store has no recorded delivery transactions.');
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final delivery = Delivery.fromJson(data);
            final deliveryId = doc.id;
            final isDelivered = delivery.transactionStatus == DeliveryStatus.delivered;

            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeliveryPage(
                        deliveryID: deliveryId,
                        delivery: delivery,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            delivery.deliveryDate != null
                                ? DateFormat('d MMM yyyy • h:mm a').format(delivery.deliveryDate!.toDate())
                                : 'No date',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isDelivered ? Colors.green : Colors.orange).withValues(alpha: isDark ? 0.25 : 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              delivery.transactionStatus,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDelivered ? (isDark ? Colors.green.shade300 : Colors.green.shade800) : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            currencyFormat.format(delivery.orderAmount),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${delivery.items.length} item${delivery.items.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Payment breakdown tags (Cash, Online, Credit)
                      Wrap(
                        spacing: 6,
                        children: [
                          if (delivery.cashAmount > 0)
                            _buildPaymentChip('Cash: ₱${delivery.cashAmount.toStringAsFixed(0)}', Colors.green, isDark),
                          if (delivery.onlineAmount > 0)
                            _buildPaymentChip('Online: ₱${delivery.onlineAmount.toStringAsFixed(0)}', Colors.blue, isDark),
                          if (delivery.creditAmount > 0)
                            _buildPaymentChip(
                              'Credit: ₱${delivery.creditAmount.toStringAsFixed(0)} (${delivery.creditStatus})',
                              delivery.creditStatus == CreditStatus.unpaid ? Colors.red : Colors.teal,
                              isDark,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentChip(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: CREDIT & ACCOUNTS RECEIVABLE LEDGER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCreditTab(ColorScheme colorScheme, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where('storeName', isEqualTo: _store.storeName)
          .where('creditAmount', isGreaterThan: 0)
          .orderBy('creditAmount')
          .orderBy('deliveryDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState('No Credit History', 'This store has never had any outstanding credits.');
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final delivery = Delivery.fromJson(data);
            final deliveryId = doc.id;
            final isUnpaid = delivery.creditStatus == CreditStatus.unpaid;

            // Compute aging in days
            int agingDays = 0;
            if (delivery.deliveryDate != null) {
              agingDays = DateTime.now().difference(delivery.deliveryDate!.toDate()).inDays;
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currencyFormat.format(delivery.creditAmount),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isUnpaid ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isUnpaid ? Colors.red : Colors.green).withValues(alpha: isDark ? 0.25 : 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isUnpaid ? 'UNPAID ($agingDays days)' : 'SETTLED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isUnpaid ? (isDark ? Colors.red.shade300 : Colors.red.shade700) : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Delivery: ${delivery.deliveryDate != null ? DateFormat('d MMM yyyy').format(delivery.deliveryDate!.toDate()) : "N/A"}',
                      style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                    ),
                    if (delivery.remarks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Note: ${delivery.remarks}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                    if (isUnpaid) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.payments_outlined, size: 16),
                          label: const Text('Settle Credit', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreditPage(
                                  recID: deliveryId,
                                  delivery: delivery,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4: ASSETS & FREEZER PLACEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAssetsTab(ColorScheme colorScheme, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(SCANNING_COLLECTION_REF)
          .where('storeName', isEqualTo: _store.storeName)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawDocs = snapshot.data?.docs ?? [];
        final scannings = rawDocs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final s = Scanning.fromJson(data).copyWith(id: doc.id);
          return ScanningServices.normalizeMonthlyScanning(s);
        }).where((s) => s.barcode.isNotEmpty && s.status != ScanningStatus.pullout).toList();

        if (scannings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: isDark ? 0.2 : 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.kitchen_rounded, size: 48, color: Colors.cyan),
                  ),
                  const SizedBox(height: 16),
                  const Text('No Freezer Registered', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'No active Selecta freezer asset is registered to ${_store.storeName}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan & Register Freezer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScanningPage(
                            initialBarcode: '',
                            initialStoreName: _store.storeName,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${scannings.length} ${scannings.length == 1 ? 'Freezer Registered' : 'Freezers Registered'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Freezer', style: TextStyle(fontSize: 12.5)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScanningPage(
                          initialBarcode: '',
                          initialStoreName: _store.storeName,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...scannings.map((freezer) {
              final isScannedThisMonth = freezer.status == ScanningStatus.scanned;
              final hasImage = freezer.imageUrl.isNotEmpty;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Colors.cyan.withValues(alpha: isDark ? 0.25 : 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.kitchen_rounded, size: 22, color: Colors.cyan),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Barcode: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF28303F) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isDark ? const Color(0xFF384152) : const Color(0xFFCBD5E1),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          freezer.barcode,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'monospace',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Assigned to ${_store.storeName}',
                                  style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: isScannedThisMonth
                                  ? (isDark ? Colors.green.shade900.withValues(alpha: 0.35) : Colors.green.shade50)
                                  : (isDark ? Colors.orange.shade900.withValues(alpha: 0.35) : Colors.orange.shade50),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isScannedThisMonth
                                    ? (isDark ? Colors.green.shade700 : Colors.green.shade300)
                                    : (isDark ? Colors.orange.shade700 : Colors.orange.shade300),
                                width: 0.9,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isScannedThisMonth ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                                  size: 12,
                                  color: isScannedThisMonth
                                      ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                                      : (isDark ? Colors.orange.shade300 : Colors.orange.shade800),
                                ),
                                const SizedBox(width: 3.5),
                                Text(
                                  isScannedThisMonth ? 'Scanned' : 'Needs Scan',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isScannedThisMonth
                                        ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                                        : (isDark ? Colors.orange.shade300 : Colors.orange.shade800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      _buildDetailRow(
                        'Monthly Audit Status',
                        isScannedThisMonth ? 'Verified for this month' : 'Pending monthly verification scan',
                        Icons.fact_check_outlined,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        'Last Verified Date',
                        freezer.scannedDate != null
                            ? DateFormat('EEEE, d MMM yyyy • h:mm a').format(freezer.scannedDate!.toDate())
                            : 'No recent scan recorded',
                        Icons.history_rounded,
                      ),
                      if (freezer.scannedBy.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          'Verified By',
                          freezer.scannedBy,
                          Icons.person_outline,
                        ),
                      ],
                      if (hasImage) ...[
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImageViewerPage(
                                  image: null,
                                  networkImagePath: freezer.imageUrl,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                Image.network(
                                  freezer.imageUrl,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                ),
                                Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text('View Photo', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_note_rounded, size: 16),
                          label: const Text('Manage / Re-scan Freezer'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ScanningPage(
                                  initialBarcode: freezer.barcode,
                                  initialStoreName: _store.storeName,
                                  isEditing: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM FLOATING ACTION BAR: DIRECT ORDER BOOKING
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomActionBar(ColorScheme colorScheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.5))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AsyncFilledButton.icon(
          onPressed: _bookOrderForStore,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
          label: const Text(
            'Book New Order for this Store',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 5: VISIT PHOTOS & PROOF OF VISIT GALLERY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPhotosTab(ColorScheme colorScheme, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(PROOF_OF_VISIT_COLLECTION)
          .where('storeName', isEqualTo: _store.storeName)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(
            'No Visit Photos',
            'No photographic proof of visit has been captured yet for ${_store.storeName}.',
          );
        }

        final visits = docs.map((d) => ProofOfVisit.fromJson(d.data() as Map<String, dynamic>, id: d.id)).toList();
        visits.sort((a, b) => b.visitDate.compareTo(a.visitDate));

        final dateFormat = DateFormat('MMM d, yyyy • h:mm a');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${visits.length} Visit Photos Recorded',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Full Visit History', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PjpHistoryPage(initialSearchQuery: _store.storeName),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.8,
                ),
                itemCount: visits.length,
                itemBuilder: (context, index) {
                  final visit = visits[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CachedProductImage(
                            imageUrl: visit.imageUrl,
                            size: double.infinity,
                            borderRadius: 0,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateFormat.format(visit.visitDate.toDate()),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              if (visit.takenBy.isNotEmpty)
                                Text(
                                  'By ${visit.takenBy}',
                                  style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                                ),
                              if (visit.notes.isNotEmpty)
                                Text(
                                  visit.notes,
                                  style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  final Color bottomBorderColor;

  _SliverTabBarDelegate(this.tabBar, this.backgroundColor, this.bottomBorderColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(bottom: BorderSide(color: bottomBorderColor, width: 1)),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
