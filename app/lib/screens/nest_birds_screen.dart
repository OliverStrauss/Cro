import 'package:flutter/material.dart';

import '../models/bird.dart';

class NestBirdsScreen extends StatelessWidget {
  final String title;
  final List<Bird> birds;

  const NestBirdsScreen({super.key, required this.title, required this.birds});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView.builder(
          itemCount: birds.length,
          itemBuilder: (context, index) => ListTile(
            key: Key('birdTile_${birds[index].id}'),
            title: Text(birds[index].name),
          ),
        ),
      );
}
