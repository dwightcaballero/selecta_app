import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/expenses.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/expenses_services.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.recID, required this.expense});

  final String recID;
  final Expenses expense;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final ExpensesService db = ExpensesService();
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  TextEditingController txtDescription = TextEditingController();
  TextEditingController txtAmount = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Expenses'),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                KForms.txtFormString('Description', txtDescription),
                KForms.txtFormMoney(
                  'Cash Amount',
                  txtAmount,
                  (bool hasFocus, TextEditingController controller) => onFocusChange(hasFocus, controller),
                ),
                KForms.datePicker('Expense Date', _selectedDate, onChangeDate),

                // If user opens an existing store, show update and delete button
                if (widget.recID.isNotEmpty) ...[
                  KForms.lastUpdatedByDetails(
                    widget.expense.createdBy,
                    widget.expense.createdDate,
                    widget.expense.lastUpdatedBy,
                    widget.expense.lastupdatedDate,
                  ),

                  Column(
                    spacing: 5,
                    children: [
                      KForms.regularButton(
                        'Delete',
                        KButtonStyle.delete,
                        () => KForms.alertDialogConfirm(ConfirmTitle.delete, ConfirmMessage.delete, context, onDelete),
                      ),
                      KForms.regularButton(
                        'Update',
                        KButtonStyle.save,
                        () => KForms.alertDialogConfirm(ConfirmTitle.update, ConfirmMessage.update, context, onUpdate),
                      ),
                    ],
                  ),
                ]
                // If user creates a new store, show save button
                else ...[
                  KForms.regularButton(
                    'Save',
                    KButtonStyle.save,
                    () => KForms.alertDialogConfirm(ConfirmTitle.save, ConfirmMessage.save, context, onSave),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onSave() async {
    if (_formKey.currentState!.validate()) {
      // save expense record
      Expenses newRecord = Expenses(
        description: txtDescription.text,
        expenseAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
        expenseDate: Timestamp.fromDate(_selectedDate),
        createdBy: authService.value.currentUser!.displayName!,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
      );
      db.addExpenses(newRecord);

      if (mounted) {
        ShowMessage.success(context, 'Successfully created a new expenses record!\n[${txtDescription.text}]');
        Navigator.pop(context); // go back to previous page
      }
    } else {
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onUpdate() async {
    if (_formKey.currentState!.validate()) {
      // update record
      Expenses expenses = widget.expense.copyWith(
        description: txtDescription.text,
        expenseAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
        expenseDate: Timestamp.fromDate(_selectedDate),
        createdBy: widget.expense.createdBy,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: widget.expense.createdDate,
        lastupdatedDate: Timestamp.now(),
      );
      db.updateExpenses(widget.recID, expenses);

      if (mounted) {
        ShowMessage.success(context, 'Successfully updated the expenses record!\n[${expenses.description}]');
        Navigator.pop(context); // go back to previous page
      }
    } else {
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onDelete() async {
    db.deleteExpenses(widget.recID);

    if (mounted) {
      ShowMessage.success(context, 'Successfully deleted expenses record!\n[${widget.expense.description}]');
      Navigator.pop(context); // go back to previous page
    }
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedDate = dateTime;
      });
    }
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text));
      } else {
        setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    }
  }

  void prefetchData() async {
    if (widget.recID.isNotEmpty) {
      txtDescription.text = widget.expense.description;
      txtAmount.text = Helperfunctions.formatDoubleAmountForDisplay(widget.expense.expenseAmount);
      _selectedDate = widget.expense.expenseDate.toDate();
    }

    setState(() {});
  }

  @override
  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  void dispose() {
    super.dispose();

    txtDescription.dispose();
    txtAmount.dispose();
  }
}
