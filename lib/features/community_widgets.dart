import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/ui.dart';
import '../services/community_service.dart';

Future<bool> socialAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: LocalizedText(success)));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: LocalizedText(socialError(e))));
    }
    return false;
  }
}

Future<bool> socialConfirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText(title),
        content: LocalizedText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: LocalizedText(action),
          ),
        ],
      ),
    ) ??
    false;

class SocialEmpty extends StatelessWidget {
  const SocialEmpty(this.icon, this.title, this.message, {super.key});
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
    child: Column(
      children: [
        IconBox(icon, size: 56),
        const SizedBox(height: 16),
        LocalizedText(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        LocalizedText(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.kayleoMuted, height: 1.6),
        ),
      ],
    ),
  );
}

class SocialAvatar extends StatelessWidget {
  const SocialAvatar(
    this.name, {
    super.key,
    this.radius = 23,
    this.photoBase64,
  });
  final String name;
  final double radius;
  final String? photoBase64;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (photoBase64 case final photo? when photo.isNotEmpty) {
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
          ? LocalizedText(
              name.trim().isEmpty
                  ? 'K'
                  : name.trim().characters.first.toUpperCase(),
              style: TextStyle(
                color: context.kayleoPrimary,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

class SocialSyncError extends StatelessWidget {
  const SocialSyncError({super.key, this.message, this.retry});
  final String? message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined),
        const SizedBox(height: 8),
        LocalizedText(
          message ?? 'Could not load this conversation. Check your connection or membership.',
          textAlign: TextAlign.center,
        ),
        if (retry != null)
          TextButton(onPressed: retry, child: const LocalizedText('Retry')),
      ],
    ),
  );
}
