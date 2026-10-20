import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/promo.dart';

/// Top pinned promotions section on the Book Order page.
///
/// Displays eligible promo cards with bundle requirements, reward chips,
/// "In Cart" / "Applied" status badges, and a one-tap "Add Bundle" shortcut.
class PromoCardsSection extends StatelessWidget {
  final List<Promo> promos;
  final Map<String, int> usedCounts;
  final List<AppliedPromo> appliedPromos;
  final Map<String, int> cartQuantities; // productId -> orderedQty
  final Map<String, int> warehouseStocks; // productId -> available stock
  final ValueChanged<Promo> onAddBundle;
  final NumberFormat currencyFormat;

  const PromoCardsSection({
    super.key,
    required this.promos,
    this.usedCounts = const {},
    this.appliedPromos = const [],
    this.cartQuantities = const {},
    this.warehouseStocks = const {},
    required this.onAddBundle,
    required this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    if (promos.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Filter out promos that reached the per-store purchase limit
    final eligiblePromos = promos.where((p) {
      if (p.limitPerStore != null) {
        final used = usedCounts[p.id] ?? 0;
        if (used >= p.limitPerStore!) return false;
      }
      return true;
    }).toList();

    if (eligiblePromos.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_offer_rounded, size: 18, color: Colors.amber.shade900),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available Promotions & Deals',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Tap "Add Bundle" to quickly add qualifying products to cart.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 146,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: eligiblePromos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final promo = eligiblePromos[index];
                return _buildPromoCard(context, promo);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard(BuildContext context, Promo promo) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Check if this promo is currently applied in the cart
    final appliedMatch = appliedPromos.where((ap) => ap.promoId == promo.id).firstOrNull;
    final isApplied = appliedMatch != null;

    // Check if any rule item or free reward item is OOS in the warehouse
    bool isOOS = false;
    for (final rule in promo.rules) {
      final stock = warehouseStocks[rule.productId] ?? 0;
      if (stock < rule.requiredQty) {
        isOOS = true;
        break;
      }
    }
    if (promo.reward.type == 'freeItem') {
      for (final freeItem in promo.reward.freeItems) {
        final stock = warehouseStocks[freeItem.productId] ?? 0;
        if (stock < freeItem.quantity) {
          isOOS = true;
          break;
        }
      }
    }

    // Format reward text
    String rewardText = '';
    Color rewardColor = Colors.green.shade700;
    if (promo.reward.type == 'fixed') {
      rewardText = '-${currencyFormat.format(promo.reward.amount ?? 0)} OFF';
    } else if (promo.reward.type == 'percent') {
      rewardText = '${promo.reward.percent?.toStringAsFixed(0)}% OFF';
    } else if (promo.reward.type == 'freeItem') {
      final freeName = promo.reward.freeItems.isNotEmpty
          ? promo.reward.freeItems.first.productName
          : 'Free Item';
      rewardText = 'FREE $freeName';
      rewardColor = Colors.deepPurple.shade700;
    }

    // Build human-friendly bundle rules text
    final ruleTexts = promo.rules.map((r) {
      final name = r.productName.isNotEmpty ? r.productName : r.productId;
      return '${r.requiredQty}x $name';
    }).join(' + ');

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isApplied
              ? Colors.green.shade400
              : colorScheme.outlineVariant.withValues(alpha: 0.7),
          width: isApplied ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  promo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: rewardColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rewardText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: rewardColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              'Bundle: $ruleTexts',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isOOS)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Text(
                    'Out of Stock',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade800,
                    ),
                  ),
                )
              else if (isApplied)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 12, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Applied (${appliedMatch.timesApplied}x)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  promo.limitPerStore == 1 ? 'Limit: 1x store' : 'Multiple sets ok',
                  style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                ),
              FilledButton.tonalIcon(
                onPressed: isOOS ? null : () => onAddBundle(promo),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 14),
                label: const Text('Add Bundle', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
