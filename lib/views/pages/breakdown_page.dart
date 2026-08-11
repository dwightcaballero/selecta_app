import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/breakdown.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/breakdown_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class BreakdownPage extends StatefulWidget {
  const BreakdownPage({super.key, required this.breakdownID, required this.breakdown});
  final String breakdownID;
  final Breakdown breakdown;

  @override
  State<BreakdownPage> createState() => _BreakdownPageState();
}

class _BreakdownPageState extends State<BreakdownPage> {
  TextEditingController txt1000 = TextEditingController();
  TextEditingController txt500 = TextEditingController();
  TextEditingController txt200 = TextEditingController();
  TextEditingController txt100 = TextEditingController();
  TextEditingController txt50 = TextEditingController();
  TextEditingController txtB20 = TextEditingController();
  TextEditingController txtC20 = TextEditingController();
  TextEditingController txt10 = TextEditingController();
  TextEditingController txt5 = TextEditingController();
  TextEditingController txt1 = TextEditingController();
  TextEditingController txtCent = TextEditingController();
  TextEditingController txtBankDeposit = TextEditingController();
  BreakdownTotal breakdownTotal = BreakdownTotal();
  BreakdownService db = BreakdownService();
  bool withBankDeposit = false;

  @override
  void initState() {
    super.initState();

    if(widget.breakdownID.isNotEmpty){
      txt1000.text = widget.breakdown.b1000 != 0? widget.breakdown.b1000.toString() : '';
      txt500.text = widget.breakdown.b500 != 0? widget.breakdown.b500.toString() : '';
      txt200.text = widget.breakdown.b200 != 0? widget.breakdown.b200.toString() : '';
      txt100.text = widget.breakdown.b100 != 0? widget.breakdown.b100.toString() : '';
      txt50.text = widget.breakdown.b50 != 0? widget.breakdown.b50.toString() : '';
      txtB20.text = widget.breakdown.b20 != 0? widget.breakdown.b20.toString() : '';
      txtC20.text = widget.breakdown.c20 != 0? widget.breakdown.c20.toString() : '';
      txt10.text = widget.breakdown.c10 != 0? widget.breakdown.c10.toString() : '';
      txt5.text = widget.breakdown.c5 != 0? widget.breakdown.c5.toString() : '';
      txt1.text = widget.breakdown.c1 != 0? widget.breakdown.c1.toString() : '';
      txtCent.text = widget.breakdown.cent != 0? widget.breakdown.cent.toString() : '';

      if(widget.breakdown.bankDepositAmount > 0){
        txtBankDeposit.text = Helperfunctions.formatDoubleAmountForDisplay(widget.breakdown.bankDepositAmount);
        withBankDeposit = true;
      }

      recompute();
    }
  }

  @override
  void dispose() {
    super.dispose();

    txt1000.dispose();
    txt500.dispose();
    txt200.dispose();
    txt100.dispose();
    txt50.dispose();
    txtB20.dispose();
    txtC20.dispose();
    txt10.dispose();
    txt5.dispose();
    txt1.dispose();
    txtCent.dispose();
    txtBankDeposit.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Breakdown'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            spacing: 15,
            children: [

              KForms.lefRightLabel('Breakdown Date', Helperfunctions.formatTimestampForDisplay(widget.breakdown.breakdownDate)),

              Divider(),

              Row(
                children: [
                  Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: KForms.textTitle('Amount'),),),
                  Expanded(flex: 2, child: KForms.textTitle('Quanity')),
                  Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: KForms.textTitle('Subtotal'))),
                ],
              ),
              
              breakdownRow('₱1,000  x   ', txt1000, Helperfunctions.formatDoubleAmountForDisplay(txt1000.text.isEmpty? 0 : double.parse(txt1000.text)*1000)),
              breakdownRow('₱500  x   ', txt500, Helperfunctions.formatDoubleAmountForDisplay(txt500.text.isEmpty? 0 : double.parse(txt500.text)*500)),
              breakdownRow('₱200  x   ', txt200, Helperfunctions.formatDoubleAmountForDisplay(txt200.text.isEmpty? 0 : double.parse(txt200.text)*200)),
              breakdownRow('₱100  x   ', txt100, Helperfunctions.formatDoubleAmountForDisplay(txt100.text.isEmpty? 0 : double.parse(txt100.text)*100)),
              breakdownRow('₱50  x   ', txt50, Helperfunctions.formatDoubleAmountForDisplay(txt50.text.isEmpty? 0 : double.parse(txt50.text)*50)),
              breakdownRow('₱20 Bill x   ', txtB20, Helperfunctions.formatDoubleAmountForDisplay(txtB20.text.isEmpty? 0 : double.parse(txtB20.text)*20)),
              breakdownRow('₱20 Coin x   ', txtC20, Helperfunctions.formatDoubleAmountForDisplay(txtC20.text.isEmpty? 0 : double.parse(txtC20.text)*20)),
              breakdownRow('₱10  x   ', txt10, Helperfunctions.formatDoubleAmountForDisplay(txt10.text.isEmpty? 0 : double.parse(txt10.text)*10)),
              breakdownRow('₱5  x   ', txt5, Helperfunctions.formatDoubleAmountForDisplay(txt5.text.isEmpty? 0 : double.parse(txt5.text)*5)),
              breakdownRow('₱1  x   ', txt1, Helperfunctions.formatDoubleAmountForDisplay(txt1.text.isEmpty? 0 : double.parse(txt1.text)*1)),
              breakdownRow('Centavo   ', txtCent, Helperfunctions.formatDoubleAmountForDisplay(txtCent.text.isEmpty? 0 : double.parse(txtCent.text)*.01)),
              
              Divider(),

              KForms.lefRightLabel('Total Cash Amount : ', Helperfunctions.formatDoubleAmountForDisplay(widget.breakdown.breakdownAmount)),
              KForms.lefRightLabel('Expected Amount : ', Helperfunctions.formatDoubleAmountForDisplay(widget.breakdown.expectedAmount)),
              KForms.lefRightLabel('Discrepancy : ', Helperfunctions.formatDoubleAmountForDisplay(widget.breakdown.discrepancy), rightLabelColor: Colors.red),
              KForms.switchYesNo('With Bank Deposit?', withBankDeposit, () {withBankDeposit = !withBankDeposit; recompute();}),

              if (withBankDeposit)...[
                KForms.txtFormMoney('Bank Deposit Amount', txtBankDeposit, (bool hasFocus, TextEditingController controller) => onFocusChange(hasFocus, controller)),
              ],

              //If user opens an existing record, 
              if (widget.breakdownID.isNotEmpty)...[
                KForms.lastUpdatedByDetails(widget.breakdown.createdBy, widget.breakdown.createdDate,widget.breakdown.lastUpdatedBy, widget.breakdown.lastupdatedDate),
                KForms.regularButton('Update', KButtonStyle.save, () => KForms.alertDialogConfirm(ConfirmTitle.update, ConfirmMessage.update, context, onUpdate))
              ]
          
              // If user creates a new record, show save button
              else ...[
                KForms.regularButton('Save', KButtonStyle.save, () => KForms.alertDialogConfirm(ConfirmTitle.save, ConfirmMessage.save, context, onSave))
              ],
            ],
          ),
        ),
      ),
    );
  }

  void onSave(){
    recompute();
    Breakdown newRecord = Breakdown(
      breakdownDate: widget.breakdown.breakdownDate,
      bankDepositAmount: txtBankDeposit.text.isEmpty? 0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text),
      breakdownAmount: widget.breakdown.breakdownAmount,
      expectedAmount: widget.breakdown.expectedAmount,
      discrepancy: widget.breakdown.discrepancy,
      cent: txtCent.text.isEmpty? 0 : int.parse(txtCent.text),
      b1000: txt1000.text.isEmpty? 0 : int.parse(txt1000.text),
      b500: txt500.text.isEmpty? 0 : int.parse(txt500.text),
      b200: txt200.text.isEmpty? 0 : int.parse(txt200.text),
      b100: txt100.text.isEmpty? 0 : int.parse(txt100.text),
      b50: txt50.text.isEmpty? 0 : int.parse(txt50.text),
      b20: txtB20.text.isEmpty? 0 : int.parse(txtB20.text),
      c20: txtC20.text.isEmpty? 0 : int.parse(txtC20.text),
      c10: txt10.text.isEmpty? 0 : int.parse(txt10.text),
      c5: txt5.text.isEmpty? 0 : int.parse(txt5.text),
      c1: txt1.text.isEmpty? 0 : int.parse(txt1.text),

      createdBy: authService.value.currentUser!.displayName!,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: Timestamp.now(), 
      lastupdatedDate: Timestamp.now());

      db.addBreakdown(newRecord);
      ShowMessage.success(context, 'Successfully created a new breakdown record!');
      Navigator.pop(context); // go back to previous page
  }

  void onUpdate(){
    recompute();
    Breakdown newRecord = widget.breakdown.copyWith(
      breakdownDate: widget.breakdown.breakdownDate,
      breakdownAmount: widget.breakdown.breakdownAmount,
      expectedAmount: widget.breakdown.expectedAmount,
      discrepancy: widget.breakdown.discrepancy,
      bankDepositAmount: txtBankDeposit.text.isEmpty? 0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text),
      cent: txtCent.text.isEmpty? 0 : int.parse(txtCent.text),
      b1000: txt1000.text.isEmpty? 0 : int.parse(txt1000.text),
      b500: txt500.text.isEmpty? 0 : int.parse(txt500.text),
      b200: txt200.text.isEmpty? 0 : int.parse(txt200.text),
      b100: txt100.text.isEmpty? 0 : int.parse(txt100.text),
      b50: txt50.text.isEmpty? 0 : int.parse(txt50.text),
      b20: txtB20.text.isEmpty? 0 : int.parse(txtB20.text),
      c20: txtC20.text.isEmpty? 0 : int.parse(txtC20.text),
      c10: txt10.text.isEmpty? 0 : int.parse(txt10.text),
      c5: txt5.text.isEmpty? 0 : int.parse(txt5.text),
      c1: txt1.text.isEmpty? 0 : int.parse(txt1.text),

      createdBy: widget.breakdown.createdBy,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: widget.breakdown.createdDate,
      lastupdatedDate: Timestamp.now());

      db.updateBreakdown(widget.breakdownID, newRecord);
      ShowMessage.success(context, 'Successfully updated breakdown record!');
      Navigator.pop(context); // go back to previous page
  }

  void recompute(){
    if (withBankDeposit){
      widget.breakdown.bankDepositAmount = txtBankDeposit.text.isEmpty? 0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text);
    }
    else{
      widget.breakdown.bankDepositAmount = 0;
      txtBankDeposit.text = '';
    }
    
    breakdownTotal.total1000 = txt1000.text.isEmpty? 0 : double.parse(txt1000.text)*1000;
    breakdownTotal.total500 = txt500.text.isEmpty? 0 : double.parse(txt500.text)*500;
    breakdownTotal.total200 = txt200.text.isEmpty? 0 : double.parse(txt200.text)*200;
    breakdownTotal.total100 = txt100.text.isEmpty? 0 : double.parse(txt100.text)*100;
    breakdownTotal.total50 = txt50.text.isEmpty? 0 : double.parse(txt50.text)*50;
    breakdownTotal.totalB20 = txtB20.text.isEmpty? 0 : double.parse(txtB20.text)*20;
    breakdownTotal.totalC20 = txtC20.text.isEmpty? 0 : double.parse(txtC20.text)*20;
    breakdownTotal.total10 = txt10.text.isEmpty? 0 : double.parse(txt10.text)*10;
    breakdownTotal.total5 = txt5.text.isEmpty? 0 : double.parse(txt5.text)*5;
    breakdownTotal.total1 = txt1.text.isEmpty? 0 : double.parse(txt1.text)*1;
    breakdownTotal.totalCent = txtCent.text.isEmpty? 0 : double.parse(txtCent.text)*.01;

    widget.breakdown.breakdownAmount = 
      breakdownTotal.total1000 +
      breakdownTotal.total500 +
      breakdownTotal.total200 +
      breakdownTotal.total100 +
      breakdownTotal.total50 +
      breakdownTotal.totalB20 +
      breakdownTotal.totalC20 +
      breakdownTotal.total10 +
      breakdownTotal.total5 +
      breakdownTotal.total1 +
      breakdownTotal.totalCent;

    widget.breakdown.discrepancy = 
      ( widget.breakdown.bankDepositAmount 
      + widget.breakdown.breakdownAmount ) 
      - widget.breakdown.expectedAmount;

    setState(() {});
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty){
      if (!hasFocus){
        recompute();
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text) );
      }
      else{
       setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    }
    else{
      if (!hasFocus){
        setState(() => recompute());  
      }
    }
  }

  Widget breakdownRow (String denomination, TextEditingController controller, String subtotal){
    return Row(
      children: [
        Expanded(flex: 2, child: Align(alignment: Alignment.centerRight ,child: KForms.textDescriptionString(denomination),),),
        Expanded(flex: 2, child: KForms.txtFormNumber('', controller, isRequired: false, onEditingComplete: recompute),),
        Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: KForms.textDescriptionString(subtotal)))
      ],
    );
  }

}

class BreakdownTotal {
  double total1000 = 0;
  double total500 = 0;
  double total200 = 0;
  double total100 = 0;
  double total50 = 0;
  double totalB20 = 0;
  double totalC20 = 0;
  double total10 = 0;
  double total5 = 0;
  double total1 = 0;
  double totalCent = 0;
}