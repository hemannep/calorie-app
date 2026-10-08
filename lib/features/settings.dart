import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/auth_repository.dart';
import '../core/ui.dart';
import '../data/models.dart';

Color _settingsMuted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
Color _settingsSoft(BuildContext context) =>
    Theme.of(context).extension<KayleoSurfaces>()!.soft;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    required this.navigate,
  });
  final AppState state;
  final ValueChanged<int> navigate;

  @override
  Widget build(BuildContext context) {
    final p = state.profile;
    final scheme = Theme.of(context).colorScheme;
    final sections = [
      if (state.accountEmail != null)
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.accountEmail!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Tag('DEMO ACCOUNT'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  Text(
                    '${state.meals.map((m) => dateKey(m.time)).toSet().length} logged days',
                  ),
                  Text('${state.streak} day streak'),
                  Text('${state.templates.length} saved meals'),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  await state.persist();
                  if (state.storageError != null) {
                    if (context.mounted) toast(context, state.storageError!);
                    return;
                  }
                  try {
                    await DemoAuthRepository().signOut();
                    state.markSignedOut();
                  } catch (_) {
                    if (context.mounted) {
                      toast(context, 'Could not sign out. Try again.');
                    }
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      _group(context, [
        _setting(
          context,
          Icons.flag_outlined,
          'Goals',
          () => openSheet(context, TargetsSheet(state: state)),
        ),
        _setting(
          context,
          Icons.restaurant_outlined,
          'Diet preferences',
          () => openSheet(context, DietPreferencesSheet(state: state)),
        ),
        _setting(
          context,
          Icons.straighten_rounded,
          'Measurements',
          () => openSheet(context, EditProfileSheet(state: state)),
        ),
        _setting(
          context,
          Icons.notifications_none_rounded,
          'Notifications',
          () => openSheet(context, ReminderSheet(state: state)),
        ),
        _setting(
          context,
          Icons.palette_outlined,
          'Appearance',
          () => openSheet(context, AppearanceSheet(state: state)),
        ),
        _setting(
          context,
          Icons.lock_outline_rounded,
          'Privacy & data',
          () => openSheet(context, PrivacySheet(state: state)),
        ),
      ]),
      _group(context, [
        _setting(
          context,
          Icons.add_circle_outline_rounded,
          'Kayleo+',
          () => openSheet(context, PremiumSheet(state: state)),
        ),
        _setting(
          context,
          Icons.info_outline_rounded,
          'About Kayleo',
          () => openSheet(context, const AboutSheet()),
        ),
      ]),
      _group(context, [
        _setting(
          context,
          Icons.bookmark_border_rounded,
          'Saved meals',
          () => navigate(4),
        ),
        _setting(
          context,
          Icons.people_outline_rounded,
          'Community',
          () => navigate(5),
        ),
        _setting(
          context,
          Icons.monitor_weight_outlined,
          'Log weight',
          () => logWeightDialog(context, state),
        ),
        _setting(
          context,
          Icons.straighten_rounded,
          'Units',
          () => unitDialog(context),
        ),
        _setting(
          context,
          Icons.download_outlined,
          'Export my data',
          () => exportData(context, state),
        ),
        _setting(
          context,
          Icons.refresh_rounded,
          'Reset & sample data',
          () => openSheet(context, DataToolsSheet(state: state)),
        ),
      ]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: KayleoSpacing.xl),
        Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 30,
                backgroundColor: _settingsSoft(context),
                child: Text(
                  p.name.isEmpty ? 'K' : p.name.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: KayleoSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name.isEmpty ? 'Your profile' : p.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () =>
                        openSheet(context, EditProfileSheet(state: state)),
                    child: Text('Edit profile'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: KayleoSpacing.xl),
        for (var i = 0; i < sections.length; i++) ...[
          sections[i],
          if (i != sections.length - 1)
            const SizedBox(height: KayleoSpacing.lg),
        ],
        const SizedBox(height: KayleoSpacing.xl),
        Center(
          child: Text(
            'kayleo.  ·  Local prototype',
            style: TextStyle(fontSize: 12, color: _settingsMuted(context)),
          ),
        ),
      ],
    );
  }

  Widget _group(BuildContext context, List<Widget> rows) => Panel(
    padding: 0,
    border: false,
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1)
            const Divider(height: 1, indent: 52, endIndent: 16),
        ],
      ],
    ),
  );

  Widget _setting(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: KayleoSpacing.lg,
      vertical: 3,
    ),
    leading: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
    title: Text(
      title,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    trailing: Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: _settingsMuted(context),
    ),
    onTap: action,
  );

  Future<void> unitDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Choose your units'),
        children: ['Metric', 'Imperial']
            .map(
              (u) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, u),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        state.profile.units == u
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: KayleoSpacing.md),
                      Expanded(
                        child: Text(
                          u == 'Metric'
                              ? 'Metric · kg & cm'
                              : 'Imperial · lb & inches',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (result != null) {
      state.profile.units = result;
      await state.persist();
    }
  }
}

class DietPreferencesSheet extends StatelessWidget {
  const DietPreferencesSheet({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => SheetFrame(
      title: 'Diet preferences',
      subtitle: 'Choose what suits your meals.',
      child: Column(
        children: [
          for (final diet in [
            'Everything',
            'Vegetarian',
            'Vegan',
            'Pescatarian',
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(diet),
              leading: Icon(
                state.profile.diet == diet
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              selected: state.profile.diet == diet,
              onTap: () async {
                state.profile.diet = diet;
                await state.persist();
              },
            ),
        ],
      ),
    ),
  );
}

class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => SheetFrame(
      title: 'Appearance',
      subtitle: 'Make Kayleo feel at home.',
      child: Column(
        children: [
          for (final (value, title, icon) in [
            ('light', 'Light', Icons.light_mode_outlined),
            ('dark', 'Dark', Icons.dark_mode_outlined),
            ('system', 'System', Icons.settings_suggest_outlined),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(title),
              subtitle: value == 'system'
                  ? Text('Follow your device settings')
                  : null,
              trailing: state.appearance == value
                  ? Icon(
                      Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              selected: state.appearance == value,
              onTap: () async => await state.setAppearance(value),
            ),
        ],
      ),
    ),
  );
}

class DataToolsSheet extends StatelessWidget {
  const DataToolsSheet({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'Data tools',
    subtitle: 'Keep a backup before replacing records.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () => exportData(context, state),
          icon: Icon(Icons.download_outlined),
          label: Text('Export my data'),
        ),
        const SizedBox(height: KayleoSpacing.lg),
        OutlinedButton(
          onPressed: () async {
            if (await confirm(
              context,
              'Replay onboarding?',
              'Your diary will stay saved. Your profile can be set up again.',
            )) {
              state.onboarded = false;
              await state.persist();
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: Text('Replay onboarding'),
        ),
        const SizedBox(height: KayleoSpacing.md),
        OutlinedButton(
          onPressed: () async {
            if (await confirm(
              context,
              'Load sample data?',
              'This replaces your diary, saved meals, hydration, movement, and weight records. Export anything you want to keep first.',
            )) {
              state.seedDemo();
              await state.persist();
              if (context.mounted) toast(context, 'Sample week loaded');
            }
          },
          child: Text('Load sample week'),
        ),
        const SizedBox(height: KayleoSpacing.lg),
        TextButton(
          onPressed: () async {
            if (await confirm(
              context,
              'Delete all local data?',
              'Your profile, meals, photos, hydration, weight, and preferences will be deleted. Export a backup first if you want to keep them.',
            )) {
              if (context.mounted) Navigator.pop(context);
              await state.reset();
            }
          },
          child: Text(
            'Delete all data & start over',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: Text(body, style: TextStyle(fontSize: 13, height: 1.7)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Continue'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> exportData(BuildContext context, AppState state) async {
  try {
    final text = state.storage.getString(state.backupKey) != null
        ? state.storage.getString(state.backupKey)!
        : const JsonEncoder.withIndent('  ').convert(state.toJson());
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(text)),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: ['kayleo-backup-${dateKey(DateTime.now())}.json'],
        title: 'My Kayleo backup',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        'Export could not open. Try a browser that supports file downloads.',
      );
    }
  }
}

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key, required this.state});
  final AppState state;
  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final BodyProfile profile = BodyProfile.fromJson(
    widget.state.profile.toJson(),
  );
  late final name = TextEditingController(text: profile.name);
  late final age = TextEditingController(text: '${profile.age}');
  late final height = TextEditingController(
    text: profile.height.toStringAsFixed(0),
  );
  late final weight = TextEditingController(
    text: profile.weight.toStringAsFixed(1),
  );
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    age.dispose();
    height.dispose();
    weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'About you',
    subtitle: 'Your profile. Always editable.',
    footer: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () async {
          if (!form.currentState!.validate()) {
            return;
          }
          profile.name = name.text.trim();
          profile.age = int.parse(age.text);
          profile.height = double.parse(height.text);
          profile.weight = double.parse(weight.text);
          widget.state.profile = profile;
          await widget.state.persist();
          if (context.mounted) {
            Navigator.pop(context);
            toast(
              context,
              'Profile updated. Your custom targets are preserved.',
            );
          }
        },
        child: Text('Save profile'),
      ),
    ),
    child: Form(
      key: form,
      child: Column(
        children: [
          TextFormField(
            controller: name,
            maxLength: 24,
            decoration: const InputDecoration(labelText: 'First name'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a name' : null,
          ),
          const SizedBox(height: 14),
          _numeric(age, 'Age', 18, 100, integer: true),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final heightField = _numeric(height, 'Height (cm)', 100, 250);
              final weightField = _numeric(weight, 'Weight (kg)', 30, 300);
              if (constraints.maxWidth < 350 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  children: [
                    heightField,
                    const SizedBox(height: KayleoSpacing.lg),
                    weightField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heightField),
                  const SizedBox(width: KayleoSpacing.md),
                  Expanded(child: weightField),
                ],
              );
            },
          ),
          const SizedBox(height: KayleoSpacing.lg),
          Text(
            'Profile measurements are entered in metric. Your chosen units are used for display and weight logging.',
            style: TextStyle(fontSize: 12, color: context.kayleoMuted),
          ),
          const SizedBox(height: KayleoSpacing.lg),
          _dropdown(
            'Sex for calculation',
            ['Prefer not to say', 'Female', 'Male'],
            profile.sex,
            (v) => profile.sex = v,
          ),
          const SizedBox(height: KayleoSpacing.lg),
          _dropdown(
            'Your goal',
            [
              'Feel healthier',
              'Lose weight',
              'Maintain weight',
              'Build muscle',
            ],
            profile.goal,
            (v) => profile.goal = v,
          ),
          const SizedBox(height: KayleoSpacing.lg),
          _dropdown(
            'Activity',
            [
              'Mostly sitting',
              'Lightly active',
              'Moderately active',
              'Very active',
            ],
            profile.activity,
            (v) => profile.activity = v,
          ),
          const SizedBox(height: KayleoSpacing.lg),
          _dropdown(
            'Food preference',
            ['Everything', 'Vegetarian', 'Vegan', 'Pescatarian'],
            profile.diet,
            (v) => profile.diet = v,
          ),
        ],
      ),
    ),
  );
  Widget _numeric(
    TextEditingController c,
    String label,
    double min,
    double max, {
    bool integer = false,
  }) => TextFormField(
    controller: c,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      final n = double.tryParse(v ?? '');
      return n == null ||
              !n.isFinite ||
              n < min ||
              n > max ||
              (integer && int.tryParse(v ?? '') == null)
          ? 'Enter $min–$max'
          : null;
    },
  );
  Widget _dropdown(
    String label,
    List<String> values,
    String selected,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: values
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(
              v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13),
            ),
          ),
        )
        .toList(),
    onChanged: (v) => change(v!),
  );
}

class TargetsSheet extends StatefulWidget {
  const TargetsSheet({super.key, required this.state});
  final AppState state;
  @override
  State<TargetsSheet> createState() => _TargetsSheetState();
}

class _TargetsSheetState extends State<TargetsSheet> {
  final form = GlobalKey<FormState>();
  late String goal = widget.state.profile.goal;
  late final fields = [
    widget.state.profile.calorieTarget,
    widget.state.profile.proteinTarget,
    widget.state.profile.carbTarget,
    widget.state.profile.fatTarget,
    widget.state.profile.waterTarget,
  ].map((v) => TextEditingController(text: '$v')).toList();
  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'Goals',
    subtitle: 'Your goal and daily targets.',
    footer: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () async {
          if (!form.currentState!.validate()) {
            return;
          }
          final values = fields.map((c) => int.parse(c.text)).toList();
          final p = widget.state.profile;
          p.goal = goal;
          p.calorieTarget = values[0];
          p.proteinTarget = values[1];
          p.carbTarget = values[2];
          p.fatTarget = values[3];
          p.waterTarget = values[4];
          await widget.state.persist();
          if (context.mounted) {
            Navigator.pop(context);
            toast(context, 'Daily targets updated');
          }
        },
        child: Text('Save my targets'),
      ),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: goal,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Your goal'),
            items:
                [
                      'Feel healthier',
                      'Lose weight',
                      'Maintain weight',
                      'Build muscle',
                    ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (value) => setState(() => goal = value!),
          ),
          const SizedBox(height: KayleoSpacing.lg),
          for (var i = 0; i < fields.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: KayleoSpacing.lg),
              child: TextFormField(
                controller: fields[i],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: [
                    'Daily energy (kcal)',
                    'Protein (g)',
                    'Carbohydrates (g)',
                    'Fat (g)',
                    'Water (ml)',
                  ][i],
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  final min = [1500, 20, 20, 20, 250][i],
                      max = [4500, 300, 600, 200, 5000][i];
                  return n == null || n < min || n > max
                      ? 'Choose $min–$max for this prototype'
                      : null;
                },
              ),
            ),
          OutlinedButton.icon(
            onPressed: () {
              final p = BodyProfile.fromJson(widget.state.profile.toJson())
                ..goal = goal
                ..calculateTargets();
              final v = [
                p.calorieTarget,
                p.proteinTarget,
                p.carbTarget,
                p.fatTarget,
                p.waterTarget,
              ];
              for (var i = 0; i < fields.length; i++) {
                fields[i].text = '${v[i]}';
              }
            },
            icon: Icon(Icons.refresh_rounded, size: 16),
            label: Text('Recalculate from my profile'),
          ),
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'How are targets estimated?',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            children: [
              Text(
                'The starting estimate uses the Mifflin–St Jeor resting-energy equation and an activity multiplier. Lose-weight and muscle goals adjust maintenance by 250 kcal. Unspecified sex uses a midpoint. Targets are illustrative adult estimates, with a 1,500–4,500 kcal range in this prototype. Individual needs, pregnancy, and medical conditions require appropriate professional guidance.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.kayleoMuted,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ReminderSheet extends StatelessWidget {
  const ReminderSheet({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => SheetFrame(
      title: 'Reminders',
      subtitle: 'You decide what’s useful.',
      child: Column(
        children: [
          for (final (key, sub) in [
            ('Meal reminders', 'Gentle prompts to check in with your diary'),
            ('Hydration reminders', 'Prompts to reach for your water'),
            ('Weekly review', 'Make time to reflect on your week'),
            ('Quiet hours', 'Keep things quiet from 9 PM to 8 AM'),
          ])
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: state.preferences[key]!,
              onChanged: (v) {
                state.preferences[key] = v;
                state.persist();
              },
              title: Text(
                key,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                sub,
                style: TextStyle(fontSize: 12, color: context.kayleoMuted),
              ),
            ),
          const SizedBox(height: KayleoSpacing.page),
          Panel(
            color: context.kayleoSurfaces.soft,
            border: false,
            child: Text(
              'Your preferences are saved here, and reminders appear in the in-app inbox. Background push and scheduled notifications are planned integrations.',
              style: TextStyle(
                fontSize: 12,
                color: context.kayleoText,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PrivacySheet extends StatelessWidget {
  const PrivacySheet({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => SheetFrame(
      title: 'Your data belongs to you',
      subtitle: 'Saved locally. Shared only by your choice.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Panel(
            color: context.kayleoSurfaces.soft,
            border: false,
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: context.kayleoPrimary),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'There is no account or cloud sync in this prototype. Your profile, photos, and diary are stored on this device. Browser storage can be cleared by your browser.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.kayleoText,
                      height: 1.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KayleoSpacing.page),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: state.preferences['Keep meal photos']!,
            onChanged: (v) {
              state.preferences['Keep meal photos'] = v;
              state.persist();
            },
            title: Text(
              'Keep photos with future meals',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Turn off to save nutrition without the photo.',
              style: TextStyle(fontSize: 12, color: context.kayleoMuted),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: state.preferences['Improve recognition']!,
            onChanged: (v) {
              state.preferences['Improve recognition'] = v;
              state.persist();
            },
            title: Text(
              'Allow corrections to improve recognition',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Consent preference only. Nothing is uploaded in this prototype.',
              style: TextStyle(fontSize: 12, color: context.kayleoMuted),
            ),
          ),
          const SizedBox(height: KayleoSpacing.page),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => exportData(context, state),
              icon: Icon(Icons.download_outlined, size: 16),
              label: Text('Export my data'),
            ),
          ),
          const SizedBox(height: KayleoSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                if (await confirm(
                  context,
                  'Remove saved photos?',
                  'All uploaded photos will be removed from your diary and saved meals. Nutrition records will remain.',
                )) {
                  for (final m in [...state.meals, ...state.templates]) {
                    m.photo = null;
                  }
                  await state.persist();
                  if (context.mounted) {
                    toast(context, 'Saved photos removed');
                  }
                }
              },
              child: Text('Remove all saved photos'),
            ),
          ),
          const SizedBox(height: KayleoSpacing.xl),
          TextButton(
            onPressed: () async {
              if (await confirm(
                context,
                'Delete all local data?',
                'Your profile, meals, photos, hydration, weight, and preferences will be deleted. Export a backup first if you want to keep them.',
              )) {
                if (context.mounted) {
                  Navigator.pop(context);
                }
                await state.reset();
              }
            },
            child: Text(
              'Delete all data & start over',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ),
  );
}

class PremiumSheet extends StatefulWidget {
  const PremiumSheet({super.key, required this.state});
  final AppState state;
  @override
  State<PremiumSheet> createState() => _PremiumSheetState();
}

class _PremiumSheetState extends State<PremiumSheet> {
  bool annual = true;
  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'Kayleo+',
    subtitle: 'A concept preview. No billing or extra features enabled.',
    footer: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () async {
          widget.state.premium = !widget.state.premium;
          await widget.state.persist();
          if (context.mounted) {
            Navigator.pop(context);
            toast(
              context,
              widget.state.premium
                  ? 'Kayleo+ preview enabled. No payment made.'
                  : 'Kayleo+ preview ended.',
            );
          }
        },
        child: Text(
          widget.state.premium
              ? 'End Kayleo+ preview'
              : 'Explore Kayleo+ preview',
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          color: forest,
          border: false,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tag(
                  'KAYLEO+',
                  color: KayleoColors.forest,
                  textColor: lime,
                  icon: Icons.add_circle_outline_rounded,
                ),
                SizedBox(height: KayleoSpacing.page),
                Text(
                  'More room\nto understand.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        for (final (icon, title, sub) in [
          (
            Icons.camera_alt_outlined,
            'Photo & voice logging',
            'A concept for quicker meal entry',
          ),
          (
            Icons.add_circle_outline_rounded,
            'Deeper meal understanding',
            'Planned ingredient and portion insights',
          ),
          (
            Icons.insights_outlined,
            'Personal weekly insights',
            'A concept for understanding your patterns',
          ),
          (
            Icons.bookmark_border_rounded,
            'Meal memory',
            'Planned suggestions from familiar meals',
          ),
          (
            Icons.cloud_outlined,
            'Backup & sync',
            'A planned premium integration',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              children: [
                IconBox(icon, size: 37),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: KayleoSpacing.xs),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.kayleoMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: KayleoSpacing.md),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              label: Text(
                'Yearly · \$39.99 / year',
                style: TextStyle(
                  fontSize: 12,
                  color: annual ? forest : context.kayleoText,
                ),
              ),
              selected: annual,
              onSelected: (_) => setState(() => annual = true),
              selectedColor: lime,
              checkmarkColor: forest,
            ),
            ChoiceChip(
              label: Text(
                'Monthly · \$5.99 / month',
                style: TextStyle(
                  fontSize: 12,
                  color: !annual ? forest : context.kayleoText,
                ),
              ),
              selected: !annual,
              onSelected: (_) => setState(() => annual = false),
              selectedColor: lime,
              checkmarkColor: forest,
            ),
          ],
        ),
        const SizedBox(height: KayleoSpacing.lg),
        Text(
          'Illustrative pricing only. This preview does not start a trial, process payment, or enable cloud AI. All local prototype features remain available.',
          style: TextStyle(
            fontSize: 12,
            color: context.kayleoMuted,
            height: 1.8,
          ),
        ),
      ],
    ),
  );
}

class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});
  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'About Kayleo',
    subtitle: 'A local-first nutrition companion prototype.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: KayleoSpacing.lg,
          runSpacing: KayleoSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/images/kayleo-icon.png',
                width: 54,
                height: 54,
                semanticLabel: 'Kayleo app icon',
              ),
            ),
            const Brand(size: 32),
          ],
        ),
        SizedBox(height: KayleoSpacing.xl),
        Text(
          'Your day, in balance.',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
        SizedBox(height: 18),
        Text(
          'Kayleo is a local nutrition prototype. Set up your profile, review meal estimates, keep a diary, and track water, weight, and movement. Your records and preferences stay on this device; you can export a backup.',
          style: TextStyle(fontSize: 12, height: 1.9),
        ),
        SizedBox(height: 18),
        Text(
          'Estimates use a local food catalog and prototype parsing. Photo recognition, live barcode lookup, cloud AI, push notifications, subscriptions, sync, wearables, and live community are previews. Sample records are clearly labeled.',
          style: TextStyle(
            fontSize: 12,
            color: context.kayleoMuted,
            height: 1.9,
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Food nutrition is estimated, not laboratory-exact. This app provides general information for adults and does not diagnose conditions or replace medical advice.',
          style: TextStyle(
            fontSize: 12,
            color: context.kayleoMuted,
            height: 1.8,
          ),
        ),
      ],
    ),
  );
}

Future<void> logWeightDialog(BuildContext context, AppState state) async {
  final imperial = state.profile.units == 'Imperial';
  final controller = TextEditingController(
    text: (state.profile.weight * (imperial ? 2.20462 : 1)).toStringAsFixed(1),
  );
  final key = GlobalKey<FormState>();
  final ok = await showManagedDialog<bool>(
    controllers: [controller],
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Log weight'),
      content: Form(
        key: key,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: imperial ? 'Weight (lb)' : 'Weight (kg)',
          ),
          validator: (v) {
            final value = double.tryParse(v ?? '');
            final kg = value == null ? null : value / (imperial ? 2.20462 : 1);
            return kg == null || !kg.isFinite || kg < 30 || kg > 300
                ? 'Enter a valid adult weight'
                : null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (key.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
          child: Text('Save weight'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await state.logWeight(
      double.parse(controller.text) / (imperial ? 2.20462 : 1),
    );
    if (context.mounted) {
      toast(context, 'Today’s weight saved');
    }
  }
}

Future<void> logActivityDialog(BuildContext context, AppState state) async {
  final c = TextEditingController(text: '20');
  final form = GlobalKey<FormState>();
  final ok = await showManagedDialog<bool>(
    controllers: [c],
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Log movement'),
      content: Form(
        key: form,
        child: TextFormField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes of walking or movement',
          ),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            return n == null || n < 1 || n > 600 ? 'Enter 1–600 minutes' : null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
          child: Text('Log movement'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await state.addActivity(int.parse(c.text));
    if (context.mounted) {
      toast(context, 'Movement saved');
    }
  }
}
