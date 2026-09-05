import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class CreditPage extends StatefulWidget {
  const CreditPage({super.key, required this.recID, required this.delivery});

  final String recID;
  final Delivery delivery;

  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> {
  DeliveryService db = DeliveryService();
  TextEditingController dropdownController = TextEditingController();
  List<DropdownMenuEntry<String>> listStatus = [];

  @override
  void initState() {
    super.initState();
    dropdownController.text = widget.delivery.creditStatus;
    listStatus.add(
      DropdownMenuEntry(value: CreditStatus.unpaid, label: CreditStatus.unpaid),
    );
    listStatus.add(
      DropdownMenuEntry(value: CreditStatus.paid, label: CreditStatus.paid),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Credit'),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 20,
            children: [
              Row(
                children: [
                  KForms.textTitle('Hapi Store'),
                  Spacer(),
                  KForms.textDescriptionString(widget.delivery.storeName),
                ],
              ),

              Row(
                children: [
                  KForms.textTitle('Credit Amount'),
                  Spacer(),
                  KForms.textDescriptionAmount(widget.delivery.creditAmount),
                ],
              ),

              Row(
                children: [
                  KForms.textTitle('Credit Date'),
                  Spacer(),
                  KForms.textDescriptionTimestampDateOnly(
                    widget.delivery.deliveryDate!,
                  ),
                ],
              ),

              KForms.dropdown('Status', listStatus, dropdownController),

              KForms.regularButton(
                'Update',
                KButtonStyle.save,
                () => KForms.alertDialogConfirm(
                  ConfirmTitle.update,
                  ConfirmMessage.update,
                  context,
                  onUpdate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void onUpdate() {
    Delivery updatedDelivery = widget.delivery.copyWith(
      storeName: widget.delivery.storeName,
      remarks: widget.delivery.remarks,
      transactionStatus: widget.delivery.transactionStatus,
      orderAmount: widget.delivery.orderAmount,
      returnAmount: widget.delivery.returnAmount,
      creditAmount: widget.delivery.creditAmount,
      cashAmount: widget.delivery.cashAmount,
      onlineAmount: widget.delivery.onlineAmount,
      deliveryDate: widget.delivery.deliveryDate,
      creditStatus: dropdownController.text,
      createdBy: widget.delivery.createdBy,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: widget.delivery.createdDate,
      lastupdatedDate: Timestamp.now(),
    );
    db.updateDelivery(widget.recID, updatedDelivery);
    ShowMessage.success(
      context,
      'Successfully updated the delivery record!\n[${updatedDelivery.storeName}]',
    );
    Navigator.pop(context); // go back to previous page
  }
}
