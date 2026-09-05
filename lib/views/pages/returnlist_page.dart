import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/return_page.dart';
import 'package:flutter_app/views/widgets/container_widget.dart';

class ReturnlistPage extends StatefulWidget {
  const ReturnlistPage({super.key});

  @override
  State<ReturnlistPage> createState() => _ReturnlistPageState();
}

class _ReturnlistPageState extends State<ReturnlistPage> {
  final DeliveryService db = DeliveryService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('List of Returns'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [_returnListView()],
          ),
        ),
      ),
    );
  }

  Widget _returnListView() {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListDeliveryWithReturnStatus(),
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

          List listReturns = snapshot.data?.docs;

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listReturns.length,
            itemBuilder: (context, index) {
              Delivery delivery = listReturns[index].data();
              String deliveryID = listReturns[index].id;

              return InkWell(
                onTap: () => Helperfunctions.navigateTo(
                  context,
                  ReturnPage(recID: deliveryID, delivery: delivery),
                ),
                child: ContainerWidget(
                  title: delivery.storeName,
                  description1: Helperfunctions.formatTimestampForDisplay(
                    delivery.lastupdatedDate,
                  ),
                  description2: Helperfunctions.formatDoubleAmountForDisplay(
                    delivery.orderAmount,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
