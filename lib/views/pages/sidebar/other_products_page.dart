import 'package:flutter/material.dart';
import 'package:selecta_ops/views/pages/sidebar/products_page.dart';

/// Backward-compatible wrapper redirecting to [ProductsPage] Tab 1 (Other Products).
class OtherProductsPage extends StatelessWidget {
  final String userRole;

  const OtherProductsPage({
    super.key,
    this.userRole = 'Dealer',
  });

  @override
  Widget build(BuildContext context) {
    return ProductsPage(
      userRole: userRole,
      initialIndex: 1,
    );
  }
}
