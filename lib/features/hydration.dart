import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/ui.dart';

class WaterPanel extends StatelessWidget {
  const WaterPanel({super.key, required this.state, required this.date});
  final AppState state;
  final DateTime date;
  Future<void> add(BuildContext context, int ml) async {
    try {
      final entry = await state.recordDrink(
        ml,
        date: DateTime(
          date.year,
          date.month,
          date.day,
          DateTime.now().hour,
          DateTime.now().minute,
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.storageError ?? '$ml ml added'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => state.removeDrink(entry.id),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('FormatException: ', '')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ml = state.waterFor(date), goal = state.profile.waterTarget;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Hydration',
            action: 'Details',
            onAction: () =>
                openSheet(context, HydrationDetails(state: state, date: date)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              KayleoRing(
                progress: goal > 0 ? ml / goal : 0,
                size: 84,
                stroke: 6,
                color: blue,
                track: context.kayleoSurfaces.soft,
                semanticLabel: 'Water: $ml of $goal ml',
                child: const Icon(
                  Icons.water_drop_outlined,
                  color: blue,
                  size: 30,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(ml / 1000).toStringAsFixed(2)} L',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'of ${(goal / 1000).toStringAsFixed(1)} L goal',
                      style: TextStyle(color: context.kayleoMuted),
                    ),
                    Text(
                      ml >= goal
                          ? 'Daily goal reached'
                          : '${goal - ml} ml remaining',
                      style: TextStyle(
                        color: context.kayleoMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in [250, 500])
                OutlinedButton.icon(
                  key: amount == 250 ? const Key('add-water') : null,
                  onPressed: () => add(context, amount),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('Add $amount ml'),
                ),
              TextButton(
                onPressed: () => openSheet(
                  context,
                  HydrationDetails(state: state, date: date, custom: true),
                ),
                child: const Text('Custom'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HydrationDetails extends StatefulWidget {
  const HydrationDetails({
    super.key,
    required this.state,
    required this.date,
    this.custom = false,
  });
  final AppState state;
  final DateTime date;
  final bool custom;
  @override
  State<HydrationDetails> createState() => _HydrationDetailsState();
}

class _HydrationDetailsState extends State<HydrationDetails> {
  final amount = TextEditingController(text: '250');
  late final goal = TextEditingController(
    text: widget.state.profile.waterTarget.toString(),
  );
  String unit = 'ml';
  String? editing, error;
  bool saving = false;
  @override
  void dispose() {
    amount.dispose();
    goal.dispose();
    super.dispose();
  }

  Future<void> commit({bool goalOnly = false}) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final raw = double.tryParse((goalOnly ? goal : amount).text);
      if (raw == null || !raw.isFinite || raw <= 0) {
        throw const FormatException('Enter a positive number.');
      }
      final ml = (raw * (goalOnly || unit == 'ml' ? 1 : 29.5735295625)).round();
      if (goalOnly) {
        await widget.state.setWaterGoal(ml);
      } else {
        await widget.state.recordDrink(
          ml,
          date: DateTime(
            widget.date.year,
            widget.date.month,
            widget.date.day,
            DateTime.now().hour,
            DateTime.now().minute,
          ),
          replaceId: editing,
        );
        editing = null;
      }
      if (mounted && widget.state.storageError != null) {
        setState(() => error = widget.state.storageError);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => SheetFrame(
      title: 'Your hydration',
      subtitle: DateFormat('EEEE, d MMM').format(widget.date),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.state.waterFor(widget.date)} / ${widget.state.profile.waterTarget} ml',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('water-custom-amount'),
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: editing == null ? 'Drink amount' : 'Edit drink amount',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final u in ['ml', 'US fl oz'])
                ChoiceChip(
                  label: Text(u),
                  selected: unit == u,
                  onSelected: saving
                      ? null
                      : (_) => setState(() {
                          final n = double.tryParse(amount.text);
                          if (n != null) {
                            amount.text =
                                (u == 'ml'
                                        ? n * 29.5735295625
                                        : n / 29.5735295625)
                                    .toStringAsFixed(2);
                          }
                          unit = u;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: saving ? null : () => commit(),
            child: Text(editing == null ? 'Log water' : 'Save drink'),
          ),
          if (editing != null)
            TextButton(
              onPressed: () => setState(() => editing = null),
              child: const Text('Cancel edit'),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Today’s drinks',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          if (widget.state.drinksFor(widget.date).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No water logged yet.'),
            ),
          for (final entry in widget.state.drinksFor(widget.date))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${entry.ml} ml'),
              subtitle: Text(DateFormat('h:mm a').format(entry.time)),
              onTap: saving
                  ? null
                  : () => setState(() {
                      editing = entry.id;
                      amount.text = entry.ml.toString();
                      unit = 'ml';
                    }),
              trailing: IconButton(
                tooltip: 'Delete drink',
                icon: const Icon(Icons.delete_outline),
                onPressed: saving
                    ? null
                    : () async {
                        await widget.state.removeDrink(entry.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Drink removed'),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () => widget.state.restoreDrink(entry),
                            ),
                          ),
                        );
                      },
              ),
            ),
          const Divider(height: 32),
          TextField(
            controller: goal,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Daily goal (ml)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: saving ? null : () => commit(goalOnly: true),
            child: const Text('Update hydration goal'),
          ),
          const SizedBox(height: 12),
          Text(
            'Set a goal that fits your routine. Log water throughout the day; the goal is not a reason to drink it all at once.',
            style: TextStyle(fontSize: 12, color: context.kayleoMuted),
          ),
        ],
      ),
    ),
  );
}
