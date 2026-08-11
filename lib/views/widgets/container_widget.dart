import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';

class ContainerWidget extends StatelessWidget {
  const ContainerWidget({
    super.key,
    required this.title,
    required this.description1,
    required this.description2,
  });

  final String title;
  final String description1;
  final String description2;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  Text(title, style: KTextStyle.titleTextStyle,),
                  Text(description1, style: KTextStyle.descriptionTextStyle,),
                  if (description2.isNotEmpty)...[Text(description2, style: KTextStyle.descriptionTextStyle,),]
                ],
              ),
              Spacer(),
              Icon(Icons.info_outline_rounded, size: 30,),
            ],
          ),
        ),
      ),
    );
  }
}