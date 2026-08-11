import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/expenses.dart';
import 'package:flutter_app/services/expenses_services.dart';
import 'package:flutter_app/views/pages/expenses_page.dart';
import 'package:flutter_app/views/widgets/container_widget.dart';

class ExpenselistPage extends StatefulWidget {
  const ExpenselistPage({super.key});

  @override
  State<ExpenselistPage> createState() => _ExpenselistPageState();
}

class _ExpenselistPageState extends State<ExpenselistPage> {
  final ExpensesService db = ExpensesService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('List of Expenses'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _expensesListView()
            ],
          ),
        ),
      ),
      floatingActionButton: floatingAddButton()
    );
  }

  Widget _expensesListView(){
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListExpenses(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          
          if (snapshot.hasError) return const Center(child: Text('Something went wrong'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Text("Loading..."));
          if (snapshot.data!.docs.isEmpty)return const Center(child: Text("No results found"));

          List listExpenses = snapshot.data?.docs;

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listExpenses.length,
            itemBuilder: (context, index) {
              Expenses expenses = listExpenses[index].data();
              String expensesID = listExpenses[index].id;

              return 
                InkWell(
                  onTap: () => Helperfunctions.navigateTo(context, ExpensesPage(recID: expensesID, expense: expenses)),
                  child: ContainerWidget(
                    title: expenses.description,
                    description1: Helperfunctions.formatTimestampForDisplay(expenses.expenseDate),
                    description2: Helperfunctions.formatDoubleAmountForDisplay(expenses.expenseAmount),
                  ),
                );
            },
          );
        },
      ),
    );
  }

  Widget floatingAddButton(){
    return FloatingActionButton(
      onPressed: () => Helperfunctions.navigateTo(context, ExpensesPage(recID: '', expense: Expenses.empty(),)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add, color: Colors.white,
      ),
    );
  }
}