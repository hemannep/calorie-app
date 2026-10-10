import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/ui.dart';
import '../data/models.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.radius = 28});

  final BodyProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = profile.photoBase64;
    ImageProvider? image;
    if (photo != null && photo.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(photo));
      } catch (_) {
        image = null;
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.kayleoSurfaces.soft,
      backgroundImage: image,
      child: image == null
          ? Text(
              profile.name.isEmpty
                  ? 'K'
                  : profile.name.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: radius * .75,
                fontWeight: FontWeight.w800,
                color: context.kayleoPrimary,
              ),
            )
          : null,
    );
  }
}
