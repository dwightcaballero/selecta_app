import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/pages/sidebar/selecta_product_form_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SelectaProduct Model Tests', () {
    test('Calculates margin and marginPercent correctly', () {
      const product = SelectaProduct(
        id: 'prod_1',
        productName: 'CORNETTO CHOCOLATE',
        imageUrl: '',
        itemCode: 'SEL-001',
        buyingPrice: 20.0,
        sellingPrice: 28.0,
        category: 'By Piece',
        tag: ProductTag.bestSeller,
        isActive: true,
        stockQuantity: 50,
        reservedQuantity: 10,
        lowStockThreshold: 15,
      );

      expect(product.margin, 8.0);
      expect(product.marginPercent, 40.0);
      expect(product.availableQuantity, 40);
      expect(product.isOutOfStock, false);
      expect(product.isLowStock, false);
      expect(product.tag, ProductTag.bestSeller);
    });

    test('Identifies low stock and out of stock states', () {
      const lowStock = SelectaProduct(
        id: 'prod_2',
        productName: 'MAGNUM CLASSIC',
        imageUrl: '',
        itemCode: 'SEL-002',
        buyingPrice: 50.0,
        sellingPrice: 65.0,
        category: 'By Piece',
        stockQuantity: 8,
        lowStockThreshold: 10,
      );
      expect(lowStock.isLowStock, true);
      expect(lowStock.isOutOfStock, false);

      const outOfStock = SelectaProduct(
        id: 'prod_3',
        productName: 'TWISTER',
        imageUrl: '',
        itemCode: 'SEL-003',
        buyingPrice: 15.0,
        sellingPrice: 20.0,
        category: 'By Piece',
        stockQuantity: 0,
        lowStockThreshold: 10,
      );
      expect(outOfStock.isOutOfStock, true);
      expect(outOfStock.isLowStock, false);
    });
  });

  group('SelectaProductFormPage Read-Only Product Record Tests', () {
    testWidgets('Dealer mode isReadOnly renders complete Product Record without Save or Delete buttons', (tester) async {
      const dealerProduct = SelectaProduct(
        id: 'dealer_sel_1',
        productName: 'SELECTA CORNETTO CHOCO',
        imageUrl: '',
        itemCode: 'SEL-CRN-01',
        buyingPrice: 22.5,
        sellingPrice: 30.0,
        category: 'By Piece',
        tag: ProductTag.bestSeller,
        isActive: true,
        stockQuantity: 48,
        reservedQuantity: 8,
        lowStockThreshold: 12,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SelectaProductFormPage(
            productId: 'dealer_sel_1',
            existingDealerProduct: dealerProduct,
            isReadOnly: true,
            userRole: 'Dealer',
          ),
        ),
      );
      await tester.pump();

      // Appbar title and subtitle for product record
      expect(find.text('Product Details'), findsOneWidget);
      expect(find.text('Selecta product record'), findsOneWidget);

      // Product information displayed
      expect(find.text('SELECTA CORNETTO CHOCO'), findsOneWidget);
      expect(find.text('Item Code'), findsOneWidget);
      expect(find.text('SEL-CRN-01'), findsOneWidget);
      expect(find.text('By Piece'), findsOneWidget);
      expect(find.text('Best Seller'), findsOneWidget);

      // Pricing & Margins
      expect(find.text('₱22.50'), findsOneWidget);
      expect(find.text('₱30.00'), findsOneWidget);
      expect(find.text('Margin'), findsOneWidget);
      expect(find.text('Margin %'), findsOneWidget);

      // Stock & Inventory
      expect(find.text('Stock & Inventory'), findsOneWidget);
      expect(find.text('48'), findsOneWidget); // stockQuantity
      expect(find.text('pcs in stock'), findsOneWidget);
      expect(find.text('Reserved: 8 pcs • Available: 40 pcs'), findsOneWidget);
      expect(find.text('Low Stock Threshold: 12 pcs'), findsOneWidget);
      expect(find.text('In Stock'), findsOneWidget);

      // Availability Status
      expect(find.text('Active in Catalog'), findsOneWidget);

      // Action buttons: Back button present, Save/Delete absent
      expect(find.text('Back to Catalog'), findsOneWidget);
      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Add Product'), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('Admin view mode for master catalog displays admin details', (tester) async {
      const adminProduct = AdminSelectaProduct(
        id: 'admin_sel_1',
        productName: 'SELECTA SUPER CHOCOLATE 1.3L',
        imageUrl: '',
        buyingPrice: 150.0,
        sellingPrice: 195.0,
        category: 'By Case',
        tag: ProductTag.newProduct,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SelectaProductFormPage(
            productId: 'admin_sel_1',
            existingProduct: adminProduct,
            isReadOnly: true,
            userRole: 'Admin',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Product Details'), findsOneWidget);
      expect(find.text('SELECTA SUPER CHOCOLATE 1.3L'), findsOneWidget);
      expect(find.text('By Case'), findsOneWidget);
      expect(find.text('New Product'), findsOneWidget);
      expect(find.text('₱150.00'), findsOneWidget);
      expect(find.text('₱195.00'), findsOneWidget);

      // Since user is Admin viewing read-only, "Edit Product (Admin)" button is available
      expect(find.text('Edit Product (Admin)'), findsOneWidget);
      expect(find.text('Back to Catalog'), findsOneWidget);
    });
  });
}
