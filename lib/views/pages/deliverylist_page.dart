import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/delivery_page.dart';
import 'package:flutter_app/views/pages/returnlist_page.dart';

class DeliveryListPage extends StatefulWidget {
  const DeliveryListPage({super.key});

  @override
  State<DeliveryListPage> createState() => _DeliveryListPageState();
}

class _DeliveryListPageState extends State<DeliveryListPage> {
  final DeliveryService db = DeliveryService();
  DateTime _selectedDate = DateTime.now();
  bool isDealer = false;
  int? returnedDeliveryCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('List of Deliveries'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              KForms.datePicker('Delivery Date', _selectedDate, onChangeDate, isEnabled: isDealer),
              _returnedTransactions(),
              _deliveryListView(),
            ],
          ),
        ),
      ),

      floatingActionButton: isDealer ? floatingActionAddButton() : null,
    );
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void prefetchData() async {
    isDealer = await KVariables.getIsDealer();
    returnedDeliveryCount = await DeliveryService.getCountReturnedDeliveriesOnOtherDays();
    setState(() {});
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      showLoading(true);
      _selectedDate = dateTime;
      showLoading(false);
    }
  }

  Widget floatingActionAddButton() {
    return FloatingActionButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) {
              return DeliveryPage(deliveryID: '', delivery: Delivery.empty());
            },
          ),
        );
      },

      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Icon(Icons.add, color: Colors.white),
    );
  }

  Widget _returnedTransactions() {
    if (returnedDeliveryCount == null || returnedDeliveryCount == 0) {
      return SizedBox.shrink();
    }

    return TextButton(
      onPressed: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => ReturnlistPage()));
        prefetchData();
      },
      child: Text(
        '* There is/are $returnedDeliveryCount returned transaction/s on previous dates. Click here to reschedule.',
        style: KTextStyle.descriptionRedTextStyle,
      ),
    );
  }

  Widget _deliveryListView() {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListDeliveryByDate(_selectedDate),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          List listDelivery = snapshot.data?.docs ?? [];
          if (listDelivery.isEmpty) {
            return Center(child: Text("Please add a delivery record!"));
          }

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listDelivery.length,
            itemBuilder: (context, index) {
              Delivery delivery = listDelivery[index].data();
              String deliveryID = listDelivery[index].id;

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
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(top: 5.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(delivery.storeName, style: KTextStyle.titleTextStyle),
                              Text(Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount), style: KTextStyle.descriptionTextStyle),
                            ],
                          ),
                          Spacer(),
                          if (delivery.transactionStatus == DeliveryStatus.pending) ...[
                            Icon(Icons.pending_actions_rounded, color: Colors.orange, size: 35),
                          ],
                          if (delivery.transactionStatus == DeliveryStatus.delivered) ...[Icon(Icons.check, color: Colors.green, size: 40)],
                          if (delivery.transactionStatus == DeliveryStatus.returned) ...[Icon(Icons.close, color: Colors.red, size: 40)],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void showLoading(bool showLoading) async {
    if (mounted) await Helperfunctions.showLoading(context: context, showLoading: showLoading);
    if (!showLoading) setState(() {});
  }
}
