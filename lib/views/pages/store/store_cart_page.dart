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
import 'package:selecta_ops/views/widgets/async_button.dart';

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
          ElevatedButton(
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
    final colorScheme = Theme.of(context).colorScheme;

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
              appBar: AppBar(
                title: const Text('Your Order Cart'),
                actions: [
                  if (_cart.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        _cart.clearCart();
                        ShowMessage.info(context, 'Cart cleared');
                      },
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      label: const Text('Clear'),
                    ),
                ],
              ),
              body: _cart.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_cart_outlined, size: 72, color: colorScheme.outlineVariant),
                          const SizedBox(height: 16),
                          const Text('Your cart is empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Browse the catalog to add items to your order', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Browse Products'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Cut-off Warning Banner
                        if (isAfterCutoff)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            color: Colors.amber.withValues(alpha: 0.15),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule_rounded, color: Colors.amber, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Daily cut-off was at ${config.storeCutoffTime}. This order may be processed for the next delivery cycle.',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.brown),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Minimum Order Value Banner
                        if (config.hasStoreMinimumOrderValue && _cart.subtotal < config.storeMinimumOrderValue!)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            color: Colors.orange.withValues(alpha: 0.15),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Minimum order is ${_currency.format(config.storeMinimumOrderValue)}. Add ${_currency.format(config.storeMinimumOrderValue! - _cart.subtotal)} more to checkout.',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepOrange),
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
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _cart.items[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.product.productName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          if (item.product.flavor.isNotEmpty)
                                            Text(
                                              item.product.flavor,
                                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                            ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.surfaceContainerHighest,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  item.packaging,
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${_currency.format(item.unitPrice)} / ${item.packaging.toLowerCase()}',
                                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Stepper
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, size: 22),
                                          onPressed: () {
                                            if (item.quantity > 1) {
                                              _cart.setQuantity(item.product.id, item.packaging, item.quantity - 1);
                                            } else {
                                              _cart.removeItem(item.product.id, item.packaging);
                                            }
                                          },
                                        ),
                                        Text(
                                          '${item.quantity}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, size: 22),
                                          onPressed: () {
                                            _cart.setQuantity(item.product.id, item.packaging, item.quantity + 1);
                                          },
                                        ),
                                      ],
                                    ),

                                    // Item total
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        _currency.format(item.totalPrice),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Bottom Summary & Checkout Panel
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, -2),
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
                                  decoration: InputDecoration(
                                    labelText: 'Delivery Instructions / Notes (Optional)',
                                    hintText: 'e.g. Please deliver before 2 PM',
                                    prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Estimated Total Info
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Estimated Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    Text(
                                      _currency.format(_cart.subtotal),
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colorScheme.primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '* Estimated total - final price and availability will be confirmed by your dealer upon approval.',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
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
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: Text(
                                      'Submit Order (${_cart.totalItemCount} items)',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
