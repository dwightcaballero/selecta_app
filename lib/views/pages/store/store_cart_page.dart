import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_cart_controller.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/views/pages/store/store_order_detail_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Shopping Cart view for Store self-ordering.
/// Validates cut-off times and minimum order values, displays estimated totals,
/// and allows submitting directly to the store's dealer.
class StoreCartPage extends StatefulWidget {
  const StoreCartPage({super.key});

  @override
  State<StoreCartPage> createState() => _StoreCartPageState();
}

class _StoreCartPageState extends State<StoreCartPage> {
  final StoreCartController _cart = StoreCartController();
  final StoreOrderController _orderController = StoreOrderController();
  final ConfigurationService _configService = ConfigurationService();
  final TextEditingController _remarksController = TextEditingController();

  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder(Configuration config, Users user) async {
    final storeId = user.storeId;
    final storeName = user.storeName;
    final dealerName = user.dealerName;

    if (storeId.isEmpty) {
      ShowMessage.error(context, 'Store profile not properly linked. Please contact your dealer.');
      return;
    }

    if (_cart.isEmpty) {
      ShowMessage.warning(context, 'Your cart is empty.');
      return;
    }

    // Check minimum order value
    if (config.hasStoreMinimumOrderValue && _cart.subtotal < config.storeMinimumOrderValue!) {
      final diff = config.storeMinimumOrderValue! - _cart.subtotal;
      ShowMessage.warning(
        context,
        'Minimum order value is ${_currency.format(config.storeMinimumOrderValue)}. '
        'Please add ${_currency.format(diff)} more to proceed.',
      );
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Order Submission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submit this order for $storeName to your dealer $dealerName?'),
            const SizedBox(height: 12),
            Text(
              'Total Items: ${_cart.totalItemCount}\nEstimated Total: ${_currency.format(_cart.subtotal)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Final prices and quantities will be confirmed by your dealer upon approval.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Review Cart')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit Order'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final items = _cart.items.map((i) => i.toStoreOrderItem()).toList();
      final result = await _orderController.submitOrder(
        storeId: storeId,
        storeName: storeName,
        items: items,
        remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
      );
      final newOrder = result.order;

      _cart.clearCart();

      if (mounted) {
        ShowMessage.success(context, 'Order #${newOrder.orderNumber} successfully submitted!');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => StoreOrderDetailPage(order: newOrder),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to submit order: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();

        return StreamBuilder<Configuration?>(
          stream: _configService.getConfigurationStream(),
          builder: (context, configSnapshot) {
            final config = configSnapshot.data ?? Configuration.empty();
            final isAfterCutoff = config.isAfterCutoff(DateTime.now());

            return Scaffold(
              appBar: CustomAppbar(
                title: 'Order Cart',
                subtitle: _cart.isNotEmpty ? '${_cart.totalItemCount} items selected' : 'Empty Cart',
                actions: [
                  if (_cart.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
                      tooltip: 'Clear Cart',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear Cart?'),
                            content: const Text('Are you sure you want to remove all items from your cart?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          _cart.clearCart();
                          if (context.mounted) {
                            ShowMessage.info(context, 'Cart cleared');
                          }
                        }
                      },
                    ),
                ],
              ),
              body: _cart.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.shopping_cart_outlined, size: 40, color: colorScheme.outline),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Your cart is empty',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Browse the product catalog to add ice cream to your order.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13.5),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.icecream_rounded, size: 18),
                              label: const Text('Browse Products', style: TextStyle(fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Cut-off Warning Banner
                        if (isAfterCutoff)
                          Container(
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF332200) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFFDE68A),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.schedule_rounded, color: Color(0xFFD97706), size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Daily cut-off was at ${config.storeCutoffTime}. This order may be scheduled for the following delivery cycle.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Minimum Order Value Banner
                        if (config.hasStoreMinimumOrderValue && _cart.subtotal < config.storeMinimumOrderValue!)
                          Container(
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF3D1A1A) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFFEF4444) : const Color(0xFFFECACA),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Minimum order is ${_currency.format(config.storeMinimumOrderValue)}. Add ${_currency.format(config.storeMinimumOrderValue! - _cart.subtotal)} more to checkout.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Cart Items List
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _cart.items.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _cart.items[index];

                              return Container(
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E2430) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Top Tier: Thumbnail + Full Name + Packaging + Remove ──
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: CachedProductImage(
                                            imageUrl: item.product.imageUrl,
                                            size: 56,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.product.productName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14.5,
                                                ),
                                              ),
                                              if (item.product.flavor.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.product.flavor,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.surfaceContainerHighest,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isDark ? const Color(0xFF384152) : const Color(0xFFCBD5E1),
                                                  ),
                                                ),
                                                child: Text(
                                                  item.packaging,
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          tooltip: 'Remove',
                                          onPressed: () => _cart.removeItem(item.product.id, item.packaging),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Divider(
                                      height: 1,
                                      thickness: 0.8,
                                      color: isDark ? const Color(0xFF2E3644) : const Color(0xFFF1F5F9),
                                    ),
                                    const SizedBox(height: 10),

                                    // ── Bottom Tier: Unit Price & Stepper + Line Total ──
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Unit Price
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Unit Price',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            Text(
                                              _currency.format(item.unitPrice),
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),

                                        // Stepper & Subtotal
                                        Row(
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                color: colorScheme.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isDark ? const Color(0xFF384152) : const Color(0xFFCBD5E1),
                                                ),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.remove_rounded, size: 16),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                    onPressed: () {
                                                      if (item.quantity > 1) {
                                                        _cart.setQuantity(item.product.id, item.packaging, item.quantity - 1);
                                                      } else {
                                                        _cart.removeItem(item.product.id, item.packaging);
                                                      }
                                                    },
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    child: Text(
                                                      '${item.quantity}',
                                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.add_rounded, size: 16),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                    onPressed: () {
                                                      _cart.setQuantity(item.product.id, item.packaging, item.quantity + 1);
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  'Total',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                Text(
                                                  _currency.format(item.totalPrice),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                    color: colorScheme.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Bottom Summary & Checkout Panel
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E2430) : Colors.white,
                            border: Border(
                              top: BorderSide(
                                color: isDark ? const Color(0xFF2E3644) : const Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, -3),
                              ),
                            ],
                          ),
                          child: SafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Remarks input
                                TextField(
                                  controller: _remarksController,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'Delivery Notes (Optional)',
                                    labelStyle: const TextStyle(fontSize: 12.5),
                                    hintText: 'Special instructions, preferred delivery time, etc.',
                                    hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                                    prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Estimated Total Info
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Estimated Total',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                        ),
                                        Text(
                                          '${_cart.totalItemCount} items (${_cart.lineCount} products)',
                                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _currency.format(_cart.subtotal),
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colorScheme.primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Estimated total — final prices & items will be verified upon dealer approval.',
                                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Submit Button
                                SizedBox(
                                  width: double.infinity,
                                  child: AsyncFilledButton(
                                    onPressed: _isSubmitting ||
                                            (config.hasStoreMinimumOrderValue && _cart.subtotal < config.storeMinimumOrderValue!)
                                        ? null
                                        : () => _submitOrder(config, user),
                                    loadingLabel: 'Submitting Order...',
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: Text(
                                      'Submit Order (${_cart.totalItemCount} items)',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                                    ),
                                  ),
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
      },
    );
  }
}
