import 'package:flutter/material.dart';

class KConstants {
  static const themeModeKey = 'themeModeKey';
}

class KTextStyle {
  static const titleTextStyle = TextStyle(color: Colors.blue, fontSize: 18, fontWeight: FontWeight.bold);

  static const descriptionTextStyle = TextStyle(fontSize: 16);

  static const descriptionRedTextStyle = TextStyle(fontSize: 16, color: Colors.red);

  static const descriptionGreenTextStyle = TextStyle(fontSize: 16, color: Colors.green);

  static const descriptionOrangeTextStyle = TextStyle(fontSize: 16, color: Colors.orange);

  static const descriptionTextStyleWithColor = TextStyle(fontSize: 16, color: Colors.orange);
}

class KButtonStyle {
  static final save = FilledButton.styleFrom(minimumSize: Size(double.infinity, 50.0), backgroundColor: Colors.green[300]);
  static final delete = FilledButton.styleFrom(minimumSize: Size(double.infinity, 50.0), backgroundColor: Colors.red[300]);
  static final normal = FilledButton.styleFrom(minimumSize: Size(double.infinity, 50.0));
  static final alertYes = FilledButton.styleFrom(backgroundColor: Colors.green[300]);
  static final alertNo = FilledButton.styleFrom(backgroundColor: Colors.red[300]);
}

class DeliveryStatus {
  static const pending = "Pending";
  static const delivered = "Delivered";
  static const returned = "Returned";
}

class CreditStatus {
  static const paid = "Paid";
  static const unpaid = "Unpaid";
}

class ConfirmMessage {
  static const save = "Do you really want to save this record?";
  static const update = "Do you really want to update this record?";
  static const delete = "Do you really want to save this record?";
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

// ₱
