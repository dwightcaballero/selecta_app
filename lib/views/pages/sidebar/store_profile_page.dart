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
import 'package:selecta_ops/views/pages/sidebar/proof_of_visit_gallery_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
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

  void _bookOrderForStore() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookOrderPage(initialStoreName: _store.storeName),
      ),
    );
  }

  void _editStore() async {
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

    return Scaffold(
      appBar: CustomAppbar(
        title: _store.storeName,
        subtitle: _store.storeAddress.isNotEmpty ? _store.storeAddress : 'Store 360° Profile',
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Store',
            onPressed: _editStore,
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
                    Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined, size: 20)),
                    Tab(text: 'Orders', icon: Icon(Icons.shopping_bag_outlined, size: 20)),
                    Tab(text: 'Credit / AR', icon: Icon(Icons.credit_card_outlined, size: 20)),
                    Tab(text: 'Assets', icon: Icon(Icons.kitchen_outlined, size: 20)),
                    Tab(text: 'Visit Photos', icon: Icon(Icons.photo_library_outlined, size: 20)),
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP PROFILE HEADER & QUICK CONTACT BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProfileHeader(ColorScheme colorScheme, bool isDark) {
    final hasContact = _store.storeContact.trim().isNotEmpty;
    final hasPjp = _store.pjpSchedule != null && _store.pjpSchedule!.isNotEmpty && _store.pjpSchedule != 'None';
    final hasGps = _store.latitude != null && _store.longitude != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Store Name + Icon Card
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? colorScheme.primary.withValues(alpha: 0.4) : colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(Icons.storefront_rounded, size: 28, color: colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _store.storeName,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _store.storeAddress.isNotEmpty ? _store.storeAddress : 'No street address specified',
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
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

          const SizedBox(height: 12),

          // Operational Status Badges (PJP Day, GPS, Opening Date)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (hasPjp)
                _buildBadge(
                  icon: Icons.calendar_today_rounded,
                  label: 'PJP: ${_store.pjpSchedule}',
                  color: isDark ? Colors.blue.shade400 : Colors.blue.shade700,
                  bgColor: isDark ? Colors.blue.shade900.withValues(alpha: 0.4) : Colors.blue.shade50,
                  borderColor: isDark ? Colors.blue.shade700 : Colors.blue.shade200,
                ),
              if (hasGps)
                _buildBadge(
                  icon: Icons.gps_fixed_rounded,
                  label: 'GPS Tagged',
                  color: isDark ? Colors.green.shade400 : Colors.green.shade700,
                  bgColor: isDark ? Colors.green.shade900.withValues(alpha: 0.4) : Colors.green.shade50,
                  borderColor: isDark ? Colors.green.shade700 : Colors.green.shade200,
                ),
              if (_store.openingDate != null)
                _buildBadge(
                  icon: Icons.event_available_rounded,
                  label: 'Opened ${DateFormat('MMM yyyy').format(_store.openingDate!.toDate())}',
                  color: colorScheme.onSurfaceVariant,
                  bgColor: isDark ? const Color(0xFF28303F) : const Color(0xFFE2E8F0),
                  borderColor: isDark ? const Color(0xFF384152) : const Color(0xFFCBD5E1),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // 1-Tap Field Action Row (Call, SMS, Directions, Book)
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
                  icon: Icons.navigation_rounded,
                  label: 'Navigate',
                  color: Colors.orange.shade800,
                  onTap: _openDirections,
                ),
              ),
              if (_isDealer) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionPill(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    color: Colors.purple,
                    onTap: _editStore,
                  ),
                ),
              ],
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
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color)),
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
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isEnabled ? color.withValues(alpha: isDark ? 0.22 : 0.1) : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEnabled ? color.withValues(alpha: isDark ? 0.45 : 0.25) : Colors.grey.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isEnabled ? color : Colors.grey),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isEnabled ? color : Colors.grey,
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
          padding: const EdgeInsets.all(16),
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
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Store Information Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Store & Operational Details',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      _buildDetailRow('Store Code / ID', _effectiveStoreId.isNotEmpty ? _effectiveStoreId : 'Pending Sync', Icons.tag),
                      const Divider(height: 16),
                      _buildDetailRow('Contact Number', _store.storeContact.isNotEmpty ? _store.storeContact : 'Not specified', Icons.phone_outlined),
                      const Divider(height: 16),
                      _buildDetailRow('PJP Schedule', _store.pjpSchedule ?? 'Unassigned', Icons.calendar_today_outlined),
                      const Divider(height: 16),
                      _buildDetailRow(
                        'Last Visit Date',
                        _store.lastPjpVisit != null ? DateFormat('EEEE, d MMM yyyy').format(_store.lastPjpVisit!.toDate()) : 'No visits recorded yet',
                        Icons.history_rounded,
                      ),
                      const Divider(height: 16),
                      _buildDetailRow(
                        'Last Order Date',
                        lastOrderDate != null ? DateFormat('EEEE, d MMM yyyy').format(lastOrderDate) : 'No orders recorded yet',
                        Icons.local_shipping_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: accentColor),
            ),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              const SizedBox(height: 1),
              Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
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
          .collection(DELIVERY_COLLECTION_REF)
          .where('storeName', isEqualTo: _store.storeName)
          .where('placement', isNull: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState('No Freezer Registered', 'No freezer or asset placement record was found for this store.');
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final delivery = Delivery.fromJson(data);
            final placement = delivery.placement;

            if (placement == null) return const SizedBox.shrink();

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withValues(alpha: isDark ? 0.25 : 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.kitchen_rounded, size: 24, color: Colors.cyan),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                placement.isFinished ? 'Selecta Cabinet (12/12 Completed)' : 'Selecta Cabinet Placement',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Progress: ${placement.progressCount}/12 Items Assigned',
                                style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildDetailRow(
                      'Placement Status',
                      placement.isFinished ? 'Completed (All 12 Slots Placed)' : 'In Progress (${placement.progressCount}/12)',
                      Icons.verified_outlined,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Placement Date',
                      delivery.deliveryDate != null ? DateFormat('d MMMM yyyy').format(delivery.deliveryDate!.toDate()) : 'N/A',
                      Icons.calendar_month_outlined,
                    ),
                    if (placement.placedProductNames.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        'Assigned SKUs',
                        placement.placedProductNames.join(', '),
                        Icons.inventory_2_outlined,
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
        child: FilledButton.icon(
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
                    label: const Text('All Stores Gallery', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProofOfVisitGalleryPage(initialStoreFilter: _store.storeName),
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
