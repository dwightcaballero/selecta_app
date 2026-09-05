import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/credit_page.dart';

class CreditlistPage extends StatefulWidget {
  const CreditlistPage({super.key});

  @override
  State<CreditlistPage> createState() => _CreditlistPageState();
}

class _CreditlistPageState extends State<CreditlistPage> {
  final DeliveryService db = DeliveryService();
  bool isDealer = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('List of Credit'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [_creditListView()],
          ),
        ),
      ),
    );
  }

  Widget _creditListView() {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListDeliveryWithCredit(),
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

          List listCredit = snapshot.data?.docs;

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listCredit.length,
            itemBuilder: (context, index) {
              Delivery delivery = listCredit[index].data();
              String deliveryID = listCredit[index].id;

              return InkWell(
                onTap: () {
                  isDealer
                      ? Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) {
                              return CreditPage(
                                recID: deliveryID,
                                delivery: delivery,
                              );
                            },
                          ),
                        )
                      : null;
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
                              KForms.textTitle(delivery.storeName),
                              KForms.textDescriptionTimestampDateOnly(
                                delivery.deliveryDate!,
                              ),
                              KForms.textDescriptionAmount(
                                delivery.creditAmount,
                              ),
                            ],
                          ),
                          Spacer(),
                          if (delivery.creditStatus == CreditStatus.unpaid) ...[
                            Icon(
                              Icons.close_sharp,
                              color: Colors.red,
                              size: 40,
                            ),
                          ],
                          if (delivery.creditStatus == CreditStatus.paid) ...[
                            Icon(
                              Icons.check_sharp,
                              color: Colors.green,
                              size: 40,
                            ),
                          ],
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

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void prefetchData() async {
    isDealer = await KVariables.getIsDealer();
    setState(() {});
  }
}
