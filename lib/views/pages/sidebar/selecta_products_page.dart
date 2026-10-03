import 'package:flutter/material.dart';
import 'package:selecta_ops/views/pages/sidebar/products_page.dart';

/// Backward-compatible wrapper redirecting to [ProductsPage] Tab 0 (Selecta Products).
class SelectaProductsPage extends StatelessWidget {
  final String userRole;

  const SelectaProductsPage({super.key, this.userRole = 'Dealer'});

  @override
  Widget build(BuildContext context) {
    return ProductsPage(
      userRole: userRole,
      initialIndex: 0,
    );
  }
}
