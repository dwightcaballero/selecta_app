import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/delivery_page.dart';
import 'package:flutter_app/views/pages/returnlist_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class DeliveryListPage extends StatefulWidget {
  const DeliveryListPage({super.key});

  @override
  State<DeliveryListPage> createState() => _DeliveryListPageState();
}

class _DeliveryListPageState extends State<DeliveryListPage> {
  final DeliveryService db = DeliveryService();
  bool isDealer = false;
  int? returnedDeliveryCount;

  DateTime _selectedDate = DateTime.now();

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

  void showLoading(bool showLoading) async {
    if (mounted) await Helperfunctions.showLoading(context: context, showLoading: showLoading);
    if (!showLoading) setState(() {});
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
  }

  String _dateLabel() {
    final today = DateTime.now();
    final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final currentDay = DateTime(today.year, today.month, today.day);

    if (selectedDay == currentDay) return 'Today, ${DateFormat('d MMM').format(_selectedDate)}';
    if (selectedDay == currentDay.subtract(const Duration(days: 1))) return 'Yesterday, ${DateFormat('d MMM').format(_selectedDate)}';
    if (selectedDay == currentDay.add(const Duration(days: 1))) return 'Tomorrow, ${DateFormat('d MMM').format(_selectedDate)}';
    return DateFormat('EEE, d MMM yyyy').format(_selectedDate);
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
        '$returnedDeliveryCount returned ${returnedDeliveryCount == 1 ? 'delivery needs' : 'deliveries need'} rescheduling. Review now.',
        style: KTextStyle.descriptionRedTextStyle,
      ),
    );
  }

  Widget _dateHeader() {
    return Row(
      children: [
        IconButton(tooltip: 'Previous day', onPressed: isDealer ? () => _changeDate(-1) : null, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Column(
            children: [
              Text(_dateLabel(), style: KTextStyle.titleTextStyle),
              TextButton.icon(
                onPressed: isDealer ? onChangeDate : null,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('Choose date'),
              ),
            ],
          ),
        ),
        IconButton(tooltip: 'Next day', onPressed: isDealer ? () => _changeDate(1) : null, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }

  Widget _summary(List deliveries) {
    int pending = 0;
    int delivered = 0;
    int returned = 0;

    for (final item in deliveries) {
      final status = (item.data() as Delivery).transactionStatus;
      if (status == DeliveryStatus.pending) pending++;
      if (status == DeliveryStatus.delivered) delivered++;
      if (status == DeliveryStatus.returned) returned++;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _summaryItem('Total', deliveries.length, Theme.of(context).colorScheme.primary),
            _summaryItem('Delivered', delivered, Colors.green),
            _summaryItem('Pending', pending, Colors.orange),
            _summaryItem('Returned', returned, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final (Color color, IconData icon) = switch (status) {
      DeliveryStatus.delivered => (Colors.green, Icons.check_circle),
      DeliveryStatus.returned => (Colors.red, Icons.cancel),
      _ => (Colors.orange, Icons.pending_actions),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _deliveryListView() {
    return Expanded(
      child: StreamBuilder(
        stream: db.getListDeliveryByDate(_selectedDate),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load deliveries. Please try again.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          List listDelivery = snapshot.data?.docs ?? [];
          if (listDelivery.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined, size: 48, color: Colors.grey.shade500),
                  const SizedBox(height: 12),
                  Text('No deliveries for ${DateFormat('d MMM yyyy').format(_selectedDate)}'),
                  if (isDealer) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DeliveryPage(deliveryID: '', delivery: Delivery.empty()),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add delivery'),
                    ),
                  ],
                ],
              ),
            );
          }

          return Column(
            children: [
              _summary(listDelivery),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: listDelivery.length,
                  itemBuilder: (context, index) {
                    Delivery delivery = listDelivery[index].data();
                    String deliveryID = listDelivery[index].id;

                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DeliveryPage(deliveryID: deliveryID, delivery: delivery),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.storefront_outlined, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(delivery.storeName, style: KTextStyle.titleTextStyle, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text(Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount), style: KTextStyle.descriptionTextStyle),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _statusBadge(delivery.transactionStatus),
                                  const SizedBox(height: 4),
                                  const Icon(Icons.chevron_right, size: 20),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Delivery', subtitle: 'List of Deliveries', showBackButton: true),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(children: [_dateHeader(), _returnedTransactions(), _deliveryListView()]),
      ),

      floatingActionButton: isDealer ? floatingActionAddButton() : null,
    );
  }
}
