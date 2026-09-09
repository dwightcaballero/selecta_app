import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';

class BuyinglistPage extends StatefulWidget {
  const BuyinglistPage({super.key});

  @override
  State<BuyinglistPage> createState() => _BuyinglistPageState();
}

class _BuyinglistPageState extends State<BuyinglistPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Buying'),
      body: Center(child: Text('Buying and Non Buying')),
    );
  }
}
