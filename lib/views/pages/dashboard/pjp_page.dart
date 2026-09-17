import 'package:flutter/material.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class PjpPage extends StatefulWidget {
  const PjpPage({super.key});

  @override
  State<PjpPage> createState() => _PjpPageState();
}

class _PjpPageState extends State<PjpPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Permanent Journey Plan'),
      body: const Center(child: Text('To be Added')),
    );
  }
}
