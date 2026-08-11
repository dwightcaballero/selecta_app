import 'package:flutter/material.dart';

class HeroWidget extends StatelessWidget {
  const HeroWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: "hero_widget_1", 
      child: 
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset("assets/images/logo.png", color: Colors.red[50], colorBlendMode: BlendMode.darken,),
        ),
    );
  }
}