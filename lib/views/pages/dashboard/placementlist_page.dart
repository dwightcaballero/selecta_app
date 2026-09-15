import 'package:flutter/material.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class PlacementlistPage extends StatefulWidget {
  const PlacementlistPage({super.key});

  @override
  State<PlacementlistPage> createState() => _PlacementlistPageState();
}

class _PlacementlistPageState extends State<PlacementlistPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Placement List'),
      body: Center(child: Text('Placement List Content Here')),
    );
  }
}
