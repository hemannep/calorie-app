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
          .showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(socialError(e))));
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
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
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
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.kayleoMuted, height: 1.6),
        ),
      ],
    ),
  );
}

class SocialAvatar extends StatelessWidget {
  const SocialAvatar(this.name, {super.key, this.radius = 23});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: context.kayleoSurfaces.soft,
    child: Text(
      name.trim().isEmpty ? 'K' : name.trim().characters.first.toUpperCase(),
      style: TextStyle(
        color: context.kayleoPrimary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
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
        Text(
          message ?? 'Could not load this conversation. Check your connection or membership.',
          textAlign: TextAlign.center,
        ),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}
