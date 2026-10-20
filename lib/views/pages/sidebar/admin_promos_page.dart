import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/promo.dart';
import 'package:selecta_ops/services/promo_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Admin & Dealer screen to manage promotional campaigns, bundle rules,
/// reward definitions, per-store limits, and funding sources.
class AdminPromosPage extends StatefulWidget {
  const AdminPromosPage({super.key});

  @override
  State<AdminPromosPage> createState() => _AdminPromosPageState();
}

class _AdminPromosPageState extends State<AdminPromosPage> {
  final PromoService _promoService = PromoService();
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  String _filter = 'all'; // 'all' | 'active' | 'inactive'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isTablet = ScreenSize.isTabletLandscape(context);

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Promotions & Bundles',
        subtitle: 'Manage promo campaigns, bundles & rewards',
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Create Promotion',
            onPressed: () => _openPromoEditor(null),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPromoEditor(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Promo', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: colorScheme.surface,
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search promo name, supplier, or product...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilterChip(
                        selected: _filter == 'all',
                        label: const Center(child: Text('All Promos')),
                        onSelected: (_) => setState(() => _filter = 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterChip(
                        selected: _filter == 'active',
                        label: const Center(child: Text('Active')),
                        selectedColor: const Color(0xFFDCFCE7),
                        onSelected: (_) => setState(() => _filter = 'active'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterChip(
                        selected: _filter == 'inactive',
                        label: const Center(child: Text('Inactive')),
                        onSelected: (_) => setState(() => _filter = 'inactive'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Promos List Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('promos').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error loading promotions: ${snapshot.error}', style: TextStyle(color: colorScheme.error)),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                final now = DateTime.now();
                var promos = docs.map((doc) => Promo.fromSnapshot(doc)).toList();

                // Client-side filtering
                promos = promos.where((p) {
                  if (_filter == 'active') {
                    if (!p.isValidAt(now)) return false;
                  } else if (_filter == 'inactive') {
                    if (p.isValidAt(now)) return false;
                  }

                  if (_searchQuery.isNotEmpty) {
                    final query = _searchQuery;
                    final nameMatch = p.name.toLowerCase().contains(query);
                    final descMatch = p.description.toLowerCase().contains(query);
                    final suppMatch = (p.supplierName ?? '').toLowerCase().contains(query);
                    final rulesMatch = p.rules.any((r) => r.productName.toLowerCase().contains(query));
                    if (!nameMatch && !descMatch && !suppMatch && !rulesMatch) return false;
                  }
                  return true;
                }).toList();

                // Sort by priority descending, then name
                promos.sort((a, b) {
                  final priorityComp = b.priority.compareTo(a.priority);
                  if (priorityComp != 0) return priorityComp;
                  return a.name.compareTo(b.name);
                });

                if (promos.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_offer_outlined, size: 56, color: colorScheme.outline),
                          const SizedBox(height: 14),
                          const Text('No Promotions Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No promos match your current filters.'
                                : 'Create your first promo campaign to boost sales with bundles & discounts.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () => _openPromoEditor(null),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Create Promo'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, isTablet ? 32 : 88),
                  itemCount: promos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final promo = promos[index];
                    return _buildPromoCard(promo, now, colorScheme);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard(Promo promo, DateTime now, ColorScheme colorScheme) {
    final isCurrentlyValid = promo.isValidAt(now);
    final isExpired = promo.endDate != null && now.isAfter(promo.endDate!.toDate());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCurrentlyValid
              ? const Color(0xFF86EFAC)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: isCurrentlyValid ? 1.5 : 1.0,
        ),
      ),
      color: isCurrentlyValid ? const Color(0xFFF9FFF9) : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Title + Status + Action
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCurrentlyValid ? const Color(0xFFDCFCE7) : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    promo.reward.isFreeReward ? Icons.card_giftcard_rounded : Icons.local_offer_rounded,
                    color: isCurrentlyValid ? const Color(0xFF16A34A) : colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      if (promo.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          promo.description,
                          style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Status Switch
                Switch.adaptive(
                  value: promo.isActive,
                  onChanged: (val) async {
                    try {
                      await FirebaseFirestore.instance.collection('promos').doc(promo.id).update({
                        'isActive': val,
                        'lastUpdatedDate': FieldValue.serverTimestamp(),
                      });
                    } catch (e) {
                      if (mounted) ShowMessage.error(context, 'Failed to update promo status: $e');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Metadata Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Validity Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isExpired
                        ? Colors.red.shade50
                        : (isCurrentlyValid ? const Color(0xFFDCFCE7) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isExpired
                        ? 'Expired'
                        : (promo.isActive ? 'Active' : 'Paused'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isExpired
                          ? Colors.red.shade800
                          : (isCurrentlyValid ? const Color(0xFF166534) : Colors.grey.shade700),
                    ),
                  ),
                ),
                // Funding Source
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: promo.fundedBy == 'supplier' ? const Color(0xFFFAF5FF) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: promo.fundedBy == 'supplier' ? const Color(0xFFE9D5FF) : const Color(0xFFBFDBFE),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    promo.fundedBy == 'supplier'
                        ? 'Supplier: ${promo.supplierName ?? 'Supplier'}${promo.supplierRefundable ? ' • Claimable' : ''}'
                        : 'Dealer Funded',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: promo.fundedBy == 'supplier' ? const Color(0xFF6B21A8) : const Color(0xFF1E40AF),
                    ),
                  ),
                ),
                // Per-Store Limit
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    promo.limitPerStore != null
                        ? '${promo.limitPerStore}x per store'
                        : 'Unlimited applications',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                  ),
                ),
                if (promo.startDate != null || promo.endDate != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${promo.startDate != null ? _dateFormat.format(promo.startDate!.toDate()) : 'Now'} - ${promo.endDate != null ? _dateFormat.format(promo.endDate!.toDate()) : 'Ongoing'}',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Bundle Requirements Section
            Text(
              'BUNDLE REQUIREMENTS (${promo.rules.length} items):',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            ...promo.rules.map((rule) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF16A34A)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Buy ${rule.requiredQty}x ${rule.productName.isNotEmpty ? rule.productName : rule.productId}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),

            // Reward Summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, size: 18, color: Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatRewardSummary(promo.reward),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Actions row (Edit / Delete)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _openPromoEditor(promo),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Promo'),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                  tooltip: 'Delete Promotion',
                  onPressed: () async {
                    final confirmed = await ShowMessage.confirm(
                      context,
                      title: 'Delete Promotion?',
                      message: 'Are you sure you want to delete "${promo.name}"? This action cannot be undone.',
                      confirmText: 'Delete',
                      isDestructive: true,
                    );
                    if (confirmed && mounted) {
                      try {
                        await _promoService.deletePromo(promo.id);
                        if (mounted) ShowMessage.success(context, 'Promotion deleted');
                      } catch (e) {
                        if (mounted) ShowMessage.error(context, 'Failed to delete promo: $e');
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatRewardSummary(PromoReward reward) {
    if (reward.isFreeReward) {
      final items = reward.freeItems.map((f) => '${f.quantity}x ${f.productName.isNotEmpty ? f.productName : f.productId}').join(', ');
      return 'Free Item: $items (Auto-injected into Cart with Price ₱0.00)';
    } else if (reward.isPercentage) {
      return 'Discount: ${reward.percent ?? 0}% OFF qualifying items';
    } else {
      return 'Fixed Discount: ${_currencyFormat.format(reward.amount ?? 0)} OFF bundle';
    }
  }

  void _openPromoEditor(Promo? promo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PromoEditorModal(
        existingPromo: promo,
        onSaved: () {
          Navigator.pop(context);
          ShowMessage.success(context, promo == null ? 'Promotion created successfully' : 'Promotion updated');
        },
      ),
    );
  }
}

/// Modal editor for creating or modifying a promotion campaign.
class _PromoEditorModal extends StatefulWidget {
  final Promo? existingPromo;
  final VoidCallback onSaved;

  const _PromoEditorModal({this.existingPromo, required this.onSaved});

  @override
  State<_PromoEditorModal> createState() => _PromoEditorModalState();
}

class _PromoEditorModalState extends State<_PromoEditorModal> {
  final _formKey = GlobalKey<FormState>();
  final PromoService _promoService = PromoService();
  final InventoryController _inventoryController = InventoryController();

  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _priorityController;
  late TextEditingController _limitPerStoreController;
  late TextEditingController _supplierNameController;
  late TextEditingController _rewardAmountController;
  late TextEditingController _rewardPercentController;

  bool _isActive = true;
  bool _repeatPerSet = true;
  String _fundedBy = 'dealer'; // 'dealer' | 'supplier'
  bool _supplierRefundable = false;
  String _rewardType = 'fixed'; // 'fixed' | 'percentage' | 'free_item'
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSaving = false;

  final List<_RuleDraft> _rules = [];
  final List<_FreeItemDraft> _freeItems = [];
  List<InventoryItem> _allInventory = [];

  @override
  void initState() {
    super.initState();
    final p = widget.existingPromo;
    _nameController = TextEditingController(text: p?.name ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _priorityController = TextEditingController(text: (p?.priority ?? 0).toString());
    _limitPerStoreController = TextEditingController(text: p?.limitPerStore?.toString() ?? '');
    _supplierNameController = TextEditingController(text: p?.supplierName ?? '');
    _rewardAmountController = TextEditingController(text: p?.reward.amount?.toString() ?? '50.00');
    _rewardPercentController = TextEditingController(text: p?.reward.percent?.toString() ?? '10');

    if (p != null) {
      _isActive = p.isActive;
      _repeatPerSet = p.repeatPerSet;
      _fundedBy = p.fundedBy;
      _supplierRefundable = p.supplierRefundable;
      _rewardType = p.reward.type;
      _startDate = p.startDate?.toDate();
      _endDate = p.endDate?.toDate();
      for (final r in p.rules) {
        _rules.add(_RuleDraft(
          productId: r.productId,
          productName: r.productName,
          productSource: r.productSource,
          requiredQty: r.requiredQty,
        ));
      }
      for (final f in p.reward.freeItems) {
        _freeItems.add(_FreeItemDraft(
          productId: f.productId,
          productName: f.productName,
          productSource: f.productSource,
          quantity: f.quantity,
          imageUrl: f.imageUrl,
        ));
      }
    } else {
      // Default dates: today until 30 days later
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 30));
    }

    _loadInventory();
  }

  Future<void> _loadInventory() async {
    try {
      final inv = await _inventoryController.getActiveInventoryStream().first;
      if (mounted) {
        setState(() => _allInventory = inv);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priorityController.dispose();
    _limitPerStoreController.dispose();
    _supplierNameController.dispose();
    _rewardAmountController.dispose();
    _rewardPercentController.dispose();
    super.dispose();
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    String? hintText,
    String? prefixText,
    String? suffixText,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      helperText: helperText,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingPromo != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Promotion' : 'Create Promotion'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSaving ? null : _savePromo,
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 48),
          children: [
            // Promotion Name
            TextFormField(
              controller: _nameController,
              decoration: _buildInputDecoration(
                labelText: 'Promotion Name *',
                hintText: 'e.g. Magnum Summer Bundle, Buy 2 Free 1',
              ),
              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a promo name' : null,
            ),
            const SizedBox(height: 12),

            // Description
            TextFormField(
              controller: _descController,
              maxLines: 2,
              decoration: _buildInputDecoration(
                labelText: 'Description / Mechanics',
                hintText: 'e.g. Buy 2 Cornetto + 1 Magnum to get ₱50 off or a free cone',
              ),
            ),
            const SizedBox(height: 14),

            // Side-by-side Date Range Selection
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickStartDate,
                    child: InputDecorator(
                      decoration: _buildInputDecoration(
                        labelText: 'Start Date',
                        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                      ),
                      child: Text(
                        _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : 'Ongoing',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickEndDate,
                    child: InputDecorator(
                      decoration: _buildInputDecoration(
                        labelText: 'End Date',
                        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                      ),
                      child: Text(
                        _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : 'Ongoing',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Funding Source & Per-Store Limit
            DropdownButtonFormField<String>(
              isExpanded: true,
              isDense: true,
              initialValue: _fundedBy,
              decoration: _buildInputDecoration(labelText: 'Funded By'),
              items: const [
                DropdownMenuItem(
                  value: 'dealer',
                  child: Text('Dealer Funded', overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(
                  value: 'supplier',
                  child: Text('Supplier Funded', overflow: TextOverflow.ellipsis),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _fundedBy = val);
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _limitPerStoreController,
              keyboardType: TextInputType.number,
              decoration: _buildInputDecoration(
                labelText: 'Per-Store Limit',
                hintText: 'e.g. 1, 2, 5...',
                helperText: 'Leave empty for unlimited redemptions per store',
              ),
            ),
            if (_fundedBy == 'supplier') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _supplierNameController,
                decoration: _buildInputDecoration(
                  labelText: 'Supplier Name',
                  hintText: 'e.g. Unilever RFM Ice Cream Inc.',
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: const Text('Supplier Reimbursement Claimable', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Track this discount under Supplier Receivables for claiming', style: TextStyle(fontSize: 12)),
                  value: _supplierRefundable,
                  onChanged: (val) => setState(() => _supplierRefundable = val),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Bundle Configuration Header
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'Bundle Requirements',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _rules.isEmpty ? Colors.amber.shade100 : Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_rules.length} ${_rules.length == 1 ? 'item' : 'items'}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _rules.isEmpty ? Colors.amber.shade900 : Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _showAddRuleDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Product'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_rules.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Add at least 1 required product rule to activate this bundle promotion.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _rules.length,
                itemBuilder: (context, idx) {
                  final rule = _rules[idx];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(rule.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Required Quantity: ${rule.requiredQty} units (${rule.productSource})'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => setState(() => _rules.removeAt(idx)),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),

            // Reward Definition
            const Text('Promotion Reward', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
              segments: const [
                ButtonSegment(
                  value: 'fixed',
                  label: Text('₱ Discount', textAlign: TextAlign.center, maxLines: 1),
                ),
                ButtonSegment(
                  value: 'percentage',
                  label: Text('% Discount', textAlign: TextAlign.center, maxLines: 1),
                ),
                ButtonSegment(
                  value: 'free_item',
                  label: Text('Free Product', textAlign: TextAlign.center, maxLines: 1),
                ),
              ],
              selected: {_rewardType},
              onSelectionChanged: (set) => setState(() => _rewardType = set.first),
            ),
            const SizedBox(height: 12),

            if (_rewardType == 'fixed')
              TextFormField(
                controller: _rewardAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _buildInputDecoration(
                  labelText: 'Discount Amount (₱) *',
                  hintText: 'e.g. 50.00',
                  prefixText: '₱ ',
                ),
                validator: (val) {
                  if (_rewardType != 'fixed') return null;
                  final num = double.tryParse(val ?? '');
                  if (num == null || num <= 0) return 'Enter a valid discount amount';
                  return null;
                },
              )
            else if (_rewardType == 'percentage')
              TextFormField(
                controller: _rewardPercentController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _buildInputDecoration(
                  labelText: 'Discount Percentage (%) *',
                  hintText: 'e.g. 10',
                  suffixText: '%',
                ),
                validator: (val) {
                  if (_rewardType != 'percentage') return null;
                  final num = double.tryParse(val ?? '');
                  if (num == null || num <= 0 || num > 100) return 'Enter percentage between 1 and 100';
                  return null;
                },
              )
            else ...[
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Free Reward Product(s)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _showAddFreeItemDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Reward Item'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_freeItems.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Text(
                    'Please select at least 1 free reward product.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                  ),
                )
              else
                ..._freeItems.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.green.shade200),
                    ),
                    color: const Color(0xFFF0FDF4),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.card_giftcard, color: Color(0xFF16A34A)),
                      title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Quantity: ${item.quantity} free (Auto-injected with Price ₱0.00)'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => setState(() => _freeItems.removeAt(idx)),
                      ),
                    ),
                  );
                }),
            ],
            const SizedBox(height: 16),

            // Repeat per set switch
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                title: const Text('Repeat Per Set', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text(
                  'Multiply reward when store buys multiples of the required bundle (e.g. 2 sets = 2x discount)',
                  style: TextStyle(fontSize: 12),
                ),
                value: _repeatPerSet,
                onChanged: (val) => setState(() => _repeatPerSet = val),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  void _showAddRuleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _SearchableProductPickerDialog(
        title: 'Add Bundle Product Rule',
        actionLabel: 'Add to Bundle',
        items: _allInventory,
        onConfirm: (selectedItem, qty) {
          setState(() {
            _rules.add(_RuleDraft(
              productId: selectedItem.id,
              productName: selectedItem.productName,
              productSource: selectedItem.source == InventoryProductSource.selecta ? 'selecta' : 'other',
              requiredQty: qty,
            ));
          });
        },
      ),
    );
  }

  void _showAddFreeItemDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _SearchableProductPickerDialog(
        title: 'Select Free Reward Product',
        actionLabel: 'Add Free Item',
        items: _allInventory,
        onConfirm: (selectedItem, qty) {
          setState(() {
            _freeItems.add(_FreeItemDraft(
              productId: selectedItem.id,
              productName: selectedItem.productName,
              productSource: selectedItem.source == InventoryProductSource.selecta ? 'selecta' : 'other',
              quantity: qty,
              imageUrl: selectedItem.imageUrl,
            ));
          });
        },
      ),
    );
  }

  Future<void> _savePromo() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rules.isEmpty) {
      ShowMessage.warning(context, 'Please add at least 1 bundle requirement rule.');
      return;
    }
    if (_rewardType == 'free_item' && _freeItems.isEmpty) {
      ShowMessage.warning(context, 'Please add at least 1 free reward product.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final docId = widget.existingPromo?.id ?? FirebaseFirestore.instance.collection('promos').doc().id;

      PromoReward reward;
      if (_rewardType == 'fixed') {
        reward = PromoReward(
          type: 'fixed',
          amount: double.tryParse(_rewardAmountController.text.trim()) ?? 0.0,
        );
      } else if (_rewardType == 'percentage') {
        reward = PromoReward(
          type: 'percentage',
          percent: double.tryParse(_rewardPercentController.text.trim()) ?? 0.0,
        );
      } else {
        reward = PromoReward(
          type: 'free_item',
          freeItems: _freeItems
              .map((f) => PromoFreeItem(
                    productId: f.productId,
                    productName: f.productName,
                    productSource: f.productSource,
                    quantity: f.quantity,
                    imageUrl: f.imageUrl,
                  ))
              .toList(),
        );
      }

      final limitVal = int.tryParse(_limitPerStoreController.text.trim());

      final promo = Promo(
        id: docId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        isActive: _isActive,
        startDate: _startDate != null ? Timestamp.fromDate(_startDate!) : null,
        endDate: _endDate != null ? Timestamp.fromDate(_endDate!) : null,
        priority: int.tryParse(_priorityController.text.trim()) ?? 0,
        rules: _rules
            .map((r) => PromoRule(
                  productId: r.productId,
                  productName: r.productName,
                  productSource: r.productSource,
                  requiredQty: r.requiredQty,
                ))
            .toList(),
        reward: reward,
        repeatPerSet: _repeatPerSet,
        limitPerStore: limitVal,
        fundedBy: _fundedBy,
        supplierName: _fundedBy == 'supplier' ? _supplierNameController.text.trim() : null,
        supplierRefundable: _fundedBy == 'supplier' && _supplierRefundable,
        createdDate: widget.existingPromo?.createdDate ?? Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      await _promoService.savePromo(promo);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ShowMessage.error(context, 'Failed to save promo: $e');
      }
    }
  }
}

class _RuleDraft {
  final String productId;
  final String productName;
  final String productSource;
  final int requiredQty;
  _RuleDraft({required this.productId, required this.productName, required this.productSource, required this.requiredQty});
}

class _FreeItemDraft {
  final String productId;
  final String productName;
  final String productSource;
  final int quantity;
  final String imageUrl;
  _FreeItemDraft({required this.productId, required this.productName, required this.productSource, required this.quantity, this.imageUrl = ''});
}

/// Searchable Product Picker Modal with brand filter chips, instant search, and quantity stepper.
class _SearchableProductPickerDialog extends StatefulWidget {
  final String title;
  final String actionLabel;
  final List<InventoryItem> items;
  final void Function(InventoryItem item, int quantity) onConfirm;

  const _SearchableProductPickerDialog({
    required this.title,
    required this.actionLabel,
    required this.items,
    required this.onConfirm,
  });

  @override
  State<_SearchableProductPickerDialog> createState() => _SearchableProductPickerDialogState();
}

class _SearchableProductPickerDialogState extends State<_SearchableProductPickerDialog> {
  String _searchQuery = '';
  String _brandFilter = 'all'; // 'all', 'selecta', 'other'
  InventoryItem? _selectedItem;
  int _quantity = 1;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) {
      if (_brandFilter == 'selecta' && item.source != InventoryProductSource.selecta) return false;
      if (_brandFilter == 'other' && item.source != InventoryProductSource.other) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = item.productName.toLowerCase().contains(q);
        final matchesCode = item.itemCode.toLowerCase().contains(q);
        if (!matchesName && !matchesCode) return false;
      }
      return true;
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar
              SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search product name or SKU...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Filter Chips
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _brandFilter == 'all',
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _brandFilter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Selecta'),
                    selected: _brandFilter == 'selecta',
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _brandFilter = 'selecta'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Other'),
                    selected: _brandFilter == 'other',
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _brandFilter = 'other'),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} items',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),

              // Product List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No products matching "$_searchQuery"',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, index) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = filtered[idx];
                          final isSelected = _selectedItem?.id == item.id;
                          final isSelecta = item.source == InventoryProductSource.selecta;

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            selected: isSelected,
                            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            title: Text(
                              item.productName,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelecta ? Colors.red.shade50 : Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelecta ? Colors.red.shade200 : Colors.blueGrey.shade200,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    isSelecta ? 'Selecta' : 'Other',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isSelecta ? Colors.red.shade800 : Colors.blueGrey.shade800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₱${item.sellingPrice.toStringAsFixed(2)} • Stock: ${item.stockQuantity}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20)
                                : null,
                            onTap: () => setState(() => _selectedItem = item),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Quantity Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Quantity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _selectedItem == null
                          ? null
                          : () {
                              widget.onConfirm(_selectedItem!, _quantity);
                              Navigator.pop(context);
                            },
                      child: Text(widget.actionLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

