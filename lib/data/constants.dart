import 'package:flutter/material.dart';

class KConstants {
  static const themeModeKey = 'themeModeKey';
}

class KTextStyle {
  static const titleTextStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);

  static const descriptionTextStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);

  static const descriptionRedTextStyle = TextStyle(fontSize: 15, color: Color(0xFFEF4444), fontWeight: FontWeight.w500);

  static const descriptionGreenTextStyle = TextStyle(fontSize: 15, color: Color(0xFF10B981), fontWeight: FontWeight.w500);

  static const descriptionOrangeTextStyle = TextStyle(fontSize: 15, color: Color(0xFFF59E0B), fontWeight: FontWeight.w500);
}

class KButtonStyle {
  static final save = FilledButton.styleFrom(
    minimumSize: const Size(double.infinity, 50.0),
    backgroundColor: const Color(0xFF10B981),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
  static final delete = FilledButton.styleFrom(
    minimumSize: const Size(double.infinity, 50.0),
    backgroundColor: const Color(0xFFEF4444),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
  static final normal = FilledButton.styleFrom(
    minimumSize: const Size(double.infinity, 50.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
  static final alertYes = FilledButton.styleFrom(
    backgroundColor: const Color(0xFF10B981),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
  static final alertNo = FilledButton.styleFrom(
    backgroundColor: const Color(0xFFEF4444),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

class DeliveryStatus {
  static const pendingPicklist = "Pending Picklist";
  static const pending = "Pending";
  static const delivered = "Delivered";
  static const returned = "Returned";
  static const voided = "Voided";
}

class CreditStatus {
  static const paid = "Paid";
  static const unpaid = "Unpaid";
}

class ScanningStatus {
  static const scanned = "Scanned";
  static const pending = "Pending";
  static const notScanned = "Not Scanned";
  static const pullout = "Pullout";
  static const unassigned = "Unassigned";
}

class BadOrderStatus {
  static const storePullout = "Store Pullout";
  static const warehousePullout = "Warehouse Pullout";
  static const settled = "Settled";

  static const List<String> all = [storePullout, warehousePullout, settled];
}

class ConfirmMessage {
  static const save = "Do you really want to save this record?";
  static const update = "Do you really want to update this record?";
  static const delete = "Do you really want to delete this record?";
}

class ConfirmTitle {
  static const save = "Save Record";
  static const update = "Update Record";
  static const delete = "Delete Record";
}

class BusinessRole {
  static const dealer = "Dealer";
  static const salesman = "Salesman";
}

class SharedPrefKeys {
  static const role = 'role';
}

class LogAction {
  static const create = "Create";
  static const update = "Update";
  static const delete = "Delete";
}

class MonthsAgo {
  static const months1 = "This Month";
  static const months3 = "Past 3 Months";
  static const months6 = "Past 6 Months";
}

class PjpScheduleDays {
  static const monday = 'Monday';
  static const tuesday = 'Tuesday';
  static const wednesday = 'Wednesday';
  static const thursday = 'Thursday';
  static const friday = 'Friday';
  static const saturday = 'Saturday';
  static const sunday = 'Sunday';

  static const List<String> all = [monday, tuesday, wednesday, thursday, friday, saturday, sunday];
}

class AppPages {
  static const bookOrder = "Book Order";
  static const picklist = "Picklist";
  static const delivery = "Delivery";
  static const scanning = "Scanning";
  static const returnPage = "Return";
  static const credit = "Credit";
  static const pjp = "PJP";
  static const pjpList = "PJP List";
  static const placement = "Placement";
  static const tasks = "Tasks";
  static const purchaseOrder = "Purchase Order";
  static const expenses = "Expenses";
  static const hapiStore = "Hapi Store";
  static const badOrder = "Bad Order";
  static const breakdown = "Breakdown";
  static const configuration = "Configuration";
  static const register = "Register";
  static const prospectScouting = "Prospect Scouting";
}

class ProductTag {
  static const String bestSeller = "Best Seller";
  static const String newProduct = "New Product";
  static const String none = "";

  static const List<String> all = [none, bestSeller, newProduct];

  static bool isBestSeller(String? tag) {
    if (tag == null) return false;
    final t = tag.trim().toLowerCase();
    return t == 'best seller' || t == 'best sellers' || t == 'bestseller' || t == 'bestsellers';
  }

  static bool isNewProduct(String? tag) {
    if (tag == null) return false;
    final t = tag.trim().toLowerCase();
    return t == 'new product' || t == 'new products' || t == 'newproduct' || t == 'newproducts';
  }
}

// ₱
