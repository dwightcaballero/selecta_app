import 'package:flutter/material.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/views/pages/sidebar/other_product_form_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OtherProduct Model Tests', () {
    test('Calculates margin and marginPercent correctly', () {
      final product = OtherProduct(
        productName: 'CORNETTO CLASSIC',
        imageUrl: '',
        buyingPrice: 20.0,
        sellingPrice: 25.0,
        isActive: true,
        stockQuantity: 15,
        reservedQuantity: 3,
        lowStockThreshold: 10,
      );

      expect(product.margin, 5.0);
      expect(product.marginPercent, 25.0);
      expect(product.availableQuantity, 12);
      expect(product.isOutOfStock, false);
      expect(product.isLowStock, false);
    });

    test('Identifies low stock and out of stock states', () {
      final lowStock = OtherProduct(
        productName: 'CHOCO ROLL',
        imageUrl: '',
        buyingPrice: 10.0,
        sellingPrice: 15.0,
        stockQuantity: 5,
        lowStockThreshold: 10,
      );
      expect(lowStock.isLowStock, true);
      expect(lowStock.isOutOfStock, false);

      final outOfStock = OtherProduct(
        productName: 'ICE CANDY',
        imageUrl: '',
        buyingPrice: 5.0,
        sellingPrice: 10.0,
        stockQuantity: 0,
        lowStockThreshold: 5,
      );
      expect(outOfStock.isOutOfStock, true);
      expect(outOfStock.isLowStock, false);
    });
  });

  group('OtherProductFormPage Editable Form Tests', () {
    testWidgets('Dealer can edit existing product with Save Changes and Delete buttons', (tester) async {
      final product = OtherProduct(
        productName: 'P20 CORNETTO DISK CHOCO',
        imageUrl: '',
        buyingPrice: 16.5,
        sellingPrice: 20.0,
        isActive: true,
        stockQuantity: 24,
        lowStockThreshold: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OtherProductFormPage(
            productId: 'test_product_1',
            existingProduct: product,
            userRole: 'Dealer',
          ),
        ),
      );
      await tester.pump();

      // Appbar should indicate Edit Product
      expect(find.text('Edit Product'), findsOneWidget);
      expect(find.text('Update product details'), findsOneWidget);

      // Form fields populated
      expect(find.text('P20 CORNETTO DISK CHOCO'), findsOneWidget);
      expect(find.text('16.50'), findsOneWidget);
      expect(find.text('20.00'), findsOneWidget);

      // Save Changes button exists
      expect(find.text('Save Changes'), findsOneWidget);

      // Delete button exists in app bar for editing
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('Dealer can add new product with Add Product button and no delete button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OtherProductFormPage(
            userRole: 'Dealer',
          ),
        ),
      );
      await tester.pump();

      // Appbar should indicate Add Product
      expect(find.text('Add Product'), findsNWidgets(2)); // in appbar and in button
      expect(find.text('New catalog entry'), findsOneWidget);

      // No delete button when creating new
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('Admin edit mode renders Save Changes and Delete buttons', (tester) async {
      final product = OtherProduct(
        productName: 'P20 CORNETTO DISK CHOCO',
        imageUrl: '',
        buyingPrice: 16.5,
        sellingPrice: 20.0,
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OtherProductFormPage(
            productId: 'test_product_1',
            existingProduct: product,
            userRole: 'Admin',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Edit Product'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });
  });
}
