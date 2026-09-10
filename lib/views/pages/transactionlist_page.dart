import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/delivery_page.dart';
import 'package:flutter_app/views/widgets/container_widget.dart';
import 'package:flutter_app/views/widgets/hapistore_dropdown.dart';
import 'package:intl/intl.dart';

class TransactionListPage extends StatefulWidget {
  const TransactionListPage({super.key, required this.storeName});
  final String storeName;

  @override
  State<TransactionListPage> createState() => _TransactionListPageState();
}

class _TransactionListPageState extends State<TransactionListPage> {
  DeliveryService db = DeliveryService();
  TextEditingController dropdownHapiStore = TextEditingController();
  TextEditingController dropdownMonthsAgo = TextEditingController();
  final List<DropdownMenuEntry<String>> listDropdownMonthsAgo = [
    DropdownMenuEntry(value: MonthsAgo.months1, label: MonthsAgo.months1),
    DropdownMenuEntry(value: MonthsAgo.months3, label: MonthsAgo.months3),
    DropdownMenuEntry(value: MonthsAgo.months6, label: MonthsAgo.months6),
  ];

  @override
  void dispose() {
    dropdownHapiStore.dispose();
    dropdownMonthsAgo.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    dropdownHapiStore.text = widget.storeName;
    dropdownMonthsAgo.text = MonthsAgo.months1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Transaction List'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              hapistoreDropdown(dropdownHapiStore, onChanged: () => setState(() {})),
              KForms.dropdown('Month', listDropdownMonthsAgo, dropdownMonthsAgo, onSelected: () => setState(() {})),
              _transactionListView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transactionListView() {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListDeliveryByStoreNameAndDateRange(dropdownHapiStore.text, dropdownMonthsAgo.text),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Text("Loading..."));
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No results found"));
          }

          List listTransaction = snapshot.data?.docs;

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listTransaction.length,
            itemBuilder: (context, index) {
              Delivery delivery = listTransaction[index].data();
              String deliveryID = listTransaction[index].id;

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) {
                        return DeliveryPage(deliveryID: deliveryID, delivery: delivery);
                      },
                    ),
                  );
                },
                child: ContainerWidget(
                  title: DateFormat('MMMM dd, yyyy').format(delivery.deliveryDate!.toDate()),
                  description1: delivery.transactionStatus,
                  description2: Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
