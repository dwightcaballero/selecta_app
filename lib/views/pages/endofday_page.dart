import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/breakdown.dart';
import 'package:flutter_app/dto/endofday_dto.dart';
import 'package:flutter_app/services/breakdown_service.dart';
import 'package:flutter_app/services/endofday_services.dart';
import 'package:flutter_app/views/pages/breakdown_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class EndofdayPage extends StatefulWidget {
  const EndofdayPage({super.key});

  @override
  State<EndofdayPage> createState() => _EndofdayPageState();
}

class _EndofdayPageState extends State<EndofdayPage> {
  DateTime _selectedDate = DateTime.now();
  final EndofdayServices db = EndofdayServices();
  final BreakdownService dbBS = BreakdownService();
  EndOfDayDTO endOfDayData = EndOfDayDTO.empty();
  Breakdown? breakdown = Breakdown.empty();
  String breakdownID = '';
  bool _isLoading = true;
  bool _isDealer = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('End of Day Report'),
      body: _isLoading
          ? KForms.loadingScreen()
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  spacing: 20,
                  children: [
                    KForms.datePicker('Delivery Date', _selectedDate, onChangeDate, isEnabled: _isDealer),
                    KForms.lefRightLabel('Total no. of Deliveries : ', endOfDayData.totaldelivery.toString()),
                    KForms.lefRightLabel('Pending : ', endOfDayData.pendingstatus.toString(), withLeftIndent: true),
                    KForms.lefRightLabel('Delivered : ', endOfDayData.deliveredstatus.toString(), withLeftIndent: true),
                    KForms.lefRightLabel('Returned : ', endOfDayData.returnedstatus.toString(), withLeftIndent: true),

                    Divider(),

                    KForms.lefRightLabel('Total Order Amount : ', Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.totalorderamount)),
                    KForms.lefRightLabel(
                      'Total Delivered Amount : ',
                      Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.totaldeliveredamount),
                    ),
                    KForms.lefRightLabel('Cash : ', Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.cashamount), withLeftIndent: true),
                    KForms.lefRightLabel('Online : ', Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.onlineamount), withLeftIndent: true),
                    KForms.lefRightLabel(
                      'Credit : ',
                      Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.creditamount),
                      withLeftIndent: true,
                      rightLabelColor: Colors.orange,
                    ),
                    KForms.lefRightLabel(
                      'Total Returned Amount : ',
                      Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.returnedAmount),
                      rightLabelColor: Colors.red,
                    ),
                    KForms.lefRightLabel(
                      'Total Bad Order Amount : ',
                      Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.badorderAmount),
                      rightLabelColor: Colors.red,
                    ),
                    KForms.lefRightLabel(
                      'Total Expense Amount : ',
                      Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.expenseAmount),
                      rightLabelColor: Colors.red,
                    ),
                    KForms.lefRightLabel('Expected Cash-On-Hand : ', Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.expectedcashonhand)),

                    if (endOfDayData.actualcashonhand != 0) ...[
                      Divider(),
                      KForms.lefRightLabel('Salesman Cash-On-Hand : ', Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.actualcashonhand)),
                      KForms.lefRightLabel(
                        'Discrepancy : ',
                        Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.discrepancy),
                        rightLabelColor: Colors.red,
                      ),
                      KForms.lefRightLabel('Bank Deposit : ', Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.bankdeposit)),
                    ],

                    KForms.regularButton('View Cash Breakdown', KButtonStyle.normal, validateBeforeBreakdown),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  void onChangeDate() async {
    setState(() => _isLoading = true);
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      _selectedDate = dateTime;
      fetchInitialData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  void fetchInitialData() async {
    setState(() => _isLoading = true);

    _isDealer = await KVariables.getIsDealer();
    endOfDayData = await db.getListDeliveryForEndOfDay(_selectedDate);
    breakdown = await dbBS.getDocumentsBySpecificDate(_selectedDate) ?? Breakdown.empty();
    breakdownID = await dbBS.getIDofBreakdown(_selectedDate);

    breakdown!.breakdownDate = Timestamp.fromDate(_selectedDate);
    breakdown!.expectedAmount = endOfDayData.expectedcashonhand;

    setState(() => _isLoading = false);
  }

  void validateBeforeBreakdown() async {
    if (endOfDayData.pendingstatus > 0) {
      ShowMessage.error(context, 'There should be no transaction that is pending for delivery');
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BreakdownPage(breakdown: breakdown!, breakdownID: breakdownID),
        ),
      );
      fetchInitialData();
    }
  }
}
