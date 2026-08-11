import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Test Page'),
      body: Center(
      )
    );
  }
}