import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/health_profile.dart';
import '../models/weight_entry.dart';
import '../services/health_profile_service.dart';
import '../services/weight_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snackbar.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.onLatestWeightChanged});

  /// Called with the latest weight whenever the history is loaded, so the
  /// daily energy targets can follow it.
  final ValueChanged<double?>? onLatestWeightChanged;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<WeightEntry> _entries = [];
  HealthProfile? _profile;

  /// Days shown on the chart; [_allRange] shows everything, including the
  /// whole goal plan, and [_customRange] shows [_customDates].
  int _rangeDays = 30;
  DateTimeRange? _customDates;
  bool _loading = true;

  static const _allRange = -1;
  static const _customRange = -2;
  static const _ranges = [
    (7, '7 วัน'),
    (30, '1 เดือน'),
    (90, '3 เดือน'),
    (180, '6 เดือน'),
    (365, '1 ปี'),
    (_allRange, 'ทั้งหมด'),
  ];

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = _entries.isEmpty ? today : _entries.first.date;
    final picked = await showDateRangePicker(
      context: context,
      helpText: 'เลือกช่วงวันที่ของกราฟ',
      saveText: 'ตกลง',
      firstDate: DateTime(math.min(first.year, now.year - 5)),
      lastDate: today,
      initialDateRange: _customDates ??
          DateTimeRange(
              start: today.subtract(const Duration(days: 29)), end: today),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customDates = picked;
      _rangeDays = _customRange;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await WeightHistoryService.instance.loadAll();
    final profile = await HealthProfileService.instance.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _profile = profile;
      _loading = false;
    });
    widget.onLatestWeightChanged
        ?.call(entries.isEmpty ? null : entries.last.weight);
  }

  /// Straight line from the weight when the goal was set to the goal
  /// weight on the goal date; null when maintaining or without a date.
  _GoalLine? get _plan {
    final profile = _profile;
    final end = profile?.targetDate;
    if (profile == null || end == null || profile.weightGoal == 'maintain') {
      return null;
    }
    final start = profile.planStartedAt;
    return _GoalLine(
      start: DateTime(start.year, start.month, start.day),
      startWeight: profile.currentWeight,
      end: DateTime(end.year, end.month, end.day),
      endWeight: profile.targetWeight,
    );
  }

  (DateTime, DateTime) get _window {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_rangeDays == _allRange) {
      var first = _entries.isEmpty ? today : _entries.first.date;
      final last = today;
      if (last.difference(first).inDays < 7) {
        first = last.subtract(const Duration(days: 7));
      }
      return (first, last);
    }
    final custom = _customDates;
    if (_rangeDays == _customRange && custom != null) {
      final start =
          DateTime(custom.start.year, custom.start.month, custom.start.day);
      final end = DateTime(custom.end.year, custom.end.month, custom.end.day);
      return (
        start,
        end.difference(start).inDays < 1
            ? start.add(const Duration(days: 1))
            : end
      );
    }
    return (today.subtract(Duration(days: _rangeDays - 1)), today);
  }

  List<WeightEntry> get _filteredEntries {
    final (from, to) = _window;
    return _entries
        .where((entry) => !entry.date.isBefore(from) && !entry.date.isAfter(to))
        .toList();
  }

  Future<void> _openEditor([WeightEntry? existing]) async {
    final controller = TextEditingController(
      text: existing?.weight.toStringAsFixed(1) ??
          (_entries.isNotEmpty
              ? _entries.last.weight.toStringAsFixed(1)
              : _profile?.currentWeight.toStringAsFixed(1) ?? ''),
    );
    final noteController = TextEditingController(text: existing?.note ?? '');
    String? weightError;
    var selectedDate = existing?.date ?? DateTime.now();
    WeightEntry? sameDay(DateTime date) {
      for (final entry in _entries) {
        if (entry.id != existing?.id &&
            entry.date.year == date.year &&
            entry.date.month == date.month &&
            entry.date.day == date.day) {
          return entry;
        }
      }
      return null;
    }

    final result = await showModalBottomSheet<WeightEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(existing == null ? 'บันทึกน้ำหนัก' : 'แก้ไขน้ำหนัก',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,3}(\.\d?)?')),
                ],
                onChanged: (_) {
                  if (weightError != null) {
                    setSheetState(() => weightError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'น้ำหนัก',
                  errorText: weightError,
                  suffixText: 'กก.',
                  prefixIcon: const Icon(Icons.monitor_weight_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('ชั่งเมื่อวันไหน',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final yesterday = today.subtract(const Duration(days: 1));
                bool isDay(DateTime a, DateTime b) =>
                    a.year == b.year && a.month == b.month && a.day == b.day;
                final other = !isDay(selectedDate, today) &&
                    !isDay(selectedDate, yesterday);
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('วันนี้'),
                    selected: isDay(selectedDate, today),
                    onSelected: (_) =>
                        setSheetState(() => selectedDate = today),
                  ),
                  ChoiceChip(
                    label: const Text('เมื่อวาน'),
                    selected: isDay(selectedDate, yesterday),
                    onSelected: (_) =>
                        setSheetState(() => selectedDate = yesterday),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: Text(other ? _shortDate(selectedDate) : 'ย้อนหลัง'),
                    selected: other,
                    onSelected: (_) async {
                      final date = await showDatePicker(
                        context: context,
                        helpText: 'เลือกวันที่ชั่งน้ำหนัก',
                        initialDate: selectedDate,
                        firstDate: DateTime(now.year - 5),
                        lastDate: now,
                      );
                      if (date != null) {
                        setSheetState(() => selectedDate = date);
                      }
                    },
                  ),
                ]);
              }),
              if (sameDay(selectedDate) case final replaced?) ...[
                const SizedBox(height: 8),
                _ChartHint(
                    'วันที่ ${_shortDate(replaced.date)} บันทึกไว้แล้ว ${replaced.weight.toStringAsFixed(1)} กก. '
                    'ระบบเก็บได้วันละ 1 ค่า ค่าใหม่จะแทนที่ค่าเดิม'),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: 'บันทึกเพิ่มเติม (ไม่บังคับ)',
                  prefixIcon: const Icon(Icons.notes_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final weight = double.tryParse(controller.text);
                  if (weight == null || weight < 30 || weight > 300) {
                    setSheetState(() => weightError = weight == null
                        ? 'กรุณากรอกน้ำหนัก'
                        : 'น้ำหนักต้องอยู่ระหว่าง 30–300 กก.');
                    return;
                  }
                  Navigator.of(context).pop(WeightEntry(
                    id: existing?.id ??
                        'weight_${DateTime.now().microsecondsSinceEpoch}',
                    date: DateTime(selectedDate.year, selectedDate.month,
                        selectedDate.day),
                    weight: weight,
                    note: noteController.text.trim(),
                  ));
                },
                child: Text(existing == null ? 'บันทึก' : 'บันทึกการแก้ไข'),
              ),
            ],
          ),
        ),
      ),
    );
    // Wait for the bottom-sheet reverse animation before disposing controllers
    // that are still attached to its TextFields.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    noteController.dispose();
    if (result == null) return;
    final replaced = existing == null && sameDay(result.date) != null;
    await WeightHistoryService.instance.save(result);
    await _load();
    if (!mounted) return;
    showAppSnackBar(
      context,
      existing != null
          ? 'แก้ไขน้ำหนักแล้ว'
          : replaced
              ? 'อัปเดตน้ำหนักของวันที่ ${_shortDate(result.date)} แล้ว'
              : 'บันทึกน้ำหนักแล้ว',
      type: AppMessageType.success,
    );
  }

  Future<void> _delete(WeightEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบบันทึกน้ำหนัก?'),
        content: Text(
            '${entry.weight.toStringAsFixed(1)} กก. · ${_dateLabel(entry.date)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ')),
        ],
      ),
    );
    if (confirmed != true) return;
    await WeightHistoryService.instance.delete(entry.id);
    await _load();
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year + 543}';

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    final profile = _profile;
    final plan = _plan;
    final latest = _entries.isEmpty ? null : _entries.last;
    final previous = _entries.length < 2 ? null : _entries[_entries.length - 2];
    final window = _window;
    final visible = _filteredEntries;
    final goal = profile?.weightGoal ?? 'maintain';

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          children: [
            Row(children: [
              Expanded(
                child: Text('น้ำหนัก',
                    style: Theme.of(context).textTheme.headlineMedium),
              ),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('บันทึก'),
              ),
            ]),
            const SizedBox(height: 16),
            _SummaryCard(
              latest: latest,
              previous: previous,
              profile: profile,
              plan: plan,
              goal: goal,
              onAdd: () => _openEditor(),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('กราฟน้ำหนัก',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (days, label) in _ranges)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _rangeDays == days,
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setState(() => _rangeDays = days),
                            ),
                          ),
                        ChoiceChip(
                          avatar:
                              const Icon(Icons.date_range_rounded, size: 18),
                          label: Text(
                              _rangeDays == _customRange && _customDates != null
                                  ? '${_shortDate(_customDates!.start)} – '
                                      '${_shortDate(_customDates!.end)}'
                                  : 'กำหนดเอง'),
                          selected: _rangeDays == _customRange,
                          showCheckmark: false,
                          onSelected: (_) => _pickCustomRange(),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (visible.isEmpty)
                      const SizedBox(
                        height: 160,
                        child: Center(
                          child: Text(
                              'ไม่มีน้ำหนักในช่วงนี้\nลองเลือกช่วงที่ยาวขึ้น',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.muted)),
                        ),
                      )
                    else
                      _WeightChart(
                        entries: visible,
                        from: window.$1,
                        to: window.$2,
                        target:
                            goal == 'maintain' ? null : profile?.targetWeight,
                        goal: goal,
                      ),
                    if (visible.length == 1) ...[
                      const SizedBox(height: 8),
                      const _ChartHint('บันทึกเพิ่มอีกวัน (หรือย้อนหลัง) '
                          'เพื่อดูเส้นกราฟ'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('ประวัติการชั่ง',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (_entries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('ยังไม่มีประวัติ กด "บันทึก" เพื่อเริ่มต้น',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted)),
                ),
              )
            else
              Card(
                child: Column(children: [
                  for (final (index, entry)
                      in _entries.reversed.take(30).indexed) ...[
                    if (index > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    _HistoryRow(
                      entry: entry,
                      before: _entryBefore(entry),
                      goal: goal,
                      onTap: () => _openEditor(entry),
                      onDelete: () => _delete(entry),
                    ),
                  ],
                ]),
              ),
          ],
        ),
      ),
    );
  }

  WeightEntry? _entryBefore(WeightEntry entry) {
    final index = _entries.indexOf(entry);
    return index > 0 ? _entries[index - 1] : null;
  }
}

// ------------------------------------------------------------------ helpers

const _months = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

/// "4 ต.ค."
String _dayMonth(DateTime date) => '${date.day} ${_months[date.month - 1]}';

/// "4 ต.ค. 69"
String _shortDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${(date.year + 543) % 100}';

/// "+0.4" / "−1.2" / "0.0"
String _signed(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == 0) return '0.0';
  return '${rounded > 0 ? '+' : '−'}${rounded.abs().toStringAsFixed(1)}';
}

/// Green when the change moves towards the goal, orange when away.
Color _changeColor(double change, String goal) {
  if (change.abs() < .05 || goal == 'maintain') return AppColors.muted;
  final towards = goal == 'gain' ? change > 0 : change < 0;
  return towards ? AppColors.teal : AppColors.orange;
}

/// A goal weight to reach by a date, drawn as a straight line.
class _GoalLine {
  const _GoalLine({
    required this.start,
    required this.startWeight,
    required this.end,
    required this.endWeight,
  });

  final DateTime start;
  final double startWeight;
  final DateTime end;
  final double endWeight;

  int get totalDays => math.max(1, end.difference(start).inDays);

  /// Planned weight on [date], held at the goal after the goal date.
  double weightOn(DateTime date) {
    final days = date.difference(start).inDays.clamp(0, totalDays);
    return startWeight + (endWeight - startWeight) * days / totalDays;
  }
}

// ------------------------------------------------------------------ cards

/// "ลดลง 3.0 กก." / "เพิ่มขึ้น 0.4 กก." / "เท่าเดิม"
String _changeWords(double change) {
  final amount = (change.abs() * 10).round() / 10;
  if (amount == 0) return 'เท่าเดิม';
  return '${change < 0 ? 'ลดลง' : 'เพิ่มขึ้น'} ${amount.toStringAsFixed(1)} กก.';
}

/// Latest weight and, with a goal, progress towards it — one card.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.latest,
    required this.previous,
    required this.profile,
    required this.plan,
    required this.goal,
    required this.onAdd,
  });

  final WeightEntry? latest;
  final WeightEntry? previous;
  final HealthProfile? profile;
  final _GoalLine? plan;
  final String goal;
  final VoidCallback onAdd;

  static const _soft = Color(0xFFD7F5ED);

  @override
  Widget build(BuildContext context) {
    final latest = this.latest;
    if (latest == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            const Icon(Icons.monitor_weight_outlined,
                size: 44, color: AppColors.muted),
            const SizedBox(height: 10),
            const Text('ยังไม่มีบันทึกน้ำหนัก',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAdd, child: const Text('บันทึกน้ำหนัก')),
          ]),
        ),
      );
    }
    final previous = this.previous;
    final change = previous == null ? null : latest.weight - previous.weight;
    final profile = this.profile;
    final hasGoal = profile != null && goal != 'maintain';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [AppColors.teal, AppColors.tealDark]),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('น้ำหนักล่าสุด · ${_shortDate(latest.date)}',
            style: const TextStyle(color: _soft, fontSize: 13)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(latest.weight.toStringAsFixed(1),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  height: 1.15,
                  fontWeight: FontWeight.w900)),
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 7),
            child: Text('กก.',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          if (change != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _Pill(
                text: '${_signed(change)} กก.',
                color: _changeColor(change, goal),
              ),
            ),
        ]),
        if (hasGoal) ..._goalSection(profile, latest.weight),
      ]),
    );
  }

  List<Widget> _goalSection(HealthProfile profile, double current) {
    final start = profile.currentWeight;
    final target = profile.targetWeight;
    final losing = target < start;
    final total = (target - start).abs();
    final done = losing ? start - current : current - start;
    final progress = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final remaining = losing ? current - target : target - current;
    final reached = remaining <= 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final plan = this.plan;
    (String, Color)? status;
    if (reached) {
      status = ('ถึงเป้าหมายแล้ว', AppColors.teal);
    } else if (plan != null) {
      if (plan.end.isBefore(today)) {
        status = ('เลยวันเป้าหมาย', AppColors.orange);
      } else {
        final expected = plan.weightOn(today);
        // Daily weight swings of a few hundred grams are normal.
        final onTrack =
            losing ? current <= expected + .3 : current >= expected - .3;
        status = onTrack
            ? ('ตามแผน', AppColors.teal)
            : ('ช้ากว่าแผน', AppColors.orange);
      }
    }

    return [
      const SizedBox(height: 16),
      Row(children: [
        Text('เป้าหมาย ${target.toStringAsFixed(1)} กก.',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('${(progress * 100).round()}%',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 10,
          color: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: .25),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Text(
            reached
                ? 'เริ่ม ${start.toStringAsFixed(1)} กก.'
                : 'เหลือ ${remaining.toStringAsFixed(1)} กก.'
                    '${plan == null ? '' : ' · ถึง ${_dayMonth(plan.end)}'}',
            style: const TextStyle(color: _soft, fontSize: 13),
          ),
        ),
        if (status != null) _Pill(text: status.$1, color: status.$2),
      ]),
    ];
  }
}

/// A small white pill with coloured text.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w800)),
      );
}

class _ChartHint extends StatelessWidget {
  const _ChartHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.tealDark),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ]),
      );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.before,
    required this.goal,
    required this.onTap,
    required this.onDelete,
  });

  final WeightEntry entry;
  final WeightEntry? before;
  final String goal;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final change = before == null ? null : entry.weight - before!.weight;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_shortDate(entry.date),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (entry.note.isNotEmpty)
                Text(entry.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          if (change != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_signed(change),
                  style: TextStyle(
                      color: _changeColor(change, goal),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          Text('${entry.weight.toStringAsFixed(1)} กก.',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          PopupMenuButton<String>(
            tooltip: 'ตัวเลือก',
            onSelected: (value) => value == 'edit' ? onTap() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
              PopupMenuItem(value: 'delete', child: Text('ลบ')),
            ],
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ chart

/// Logged weights over real dates with the goal weight as a dashed line.
/// Tap or drag to read a point.
class _WeightChart extends StatefulWidget {
  const _WeightChart({
    required this.entries,
    required this.from,
    required this.to,
    required this.target,
    required this.goal,
  });

  final List<WeightEntry> entries;
  final DateTime from;
  final DateTime to;

  /// Goal weight, or null when maintaining.
  final double? target;
  final String goal;

  @override
  State<_WeightChart> createState() => _WeightChartState();
}

class _WeightChartState extends State<_WeightChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant _WeightChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) _selected = null;
  }

  void _select(Offset position, double width) {
    if (widget.entries.isEmpty) return;
    final geometry = _ChartGeometry(widget, Size(width, _height));
    var best = 0;
    var bestDistance = double.infinity;
    for (final (index, entry) in widget.entries.indexed) {
      final distance = (geometry.x(entry.date) - position.dx).abs();
      if (distance < bestDistance) {
        best = index;
        bestDistance = distance;
      }
    }
    if (best != _selected) {
      HapticFeedback.selectionClick();
      setState(() => _selected = best);
    }
  }

  static const _height = 230.0;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final selected = _selected;
    Widget? header;
    if (selected != null && selected < entries.length) {
      final entry = entries[selected];
      final before = selected > 0 ? entries[selected - 1] : null;
      header = _ChartHeader(
        label: _shortDate(entry.date),
        change: before == null ? null : entry.weight - before.weight,
        suffix: ' จากครั้งก่อน',
        goal: widget.goal,
        onClear: () => setState(() => _selected = null),
      );
    } else if (entries.length >= 2) {
      header = _ChartHeader(
        label: '${_dayMonth(entries.first.date)} – '
            '${_dayMonth(entries.last.date)}',
        change: entries.last.weight - entries.first.weight,
        goal: widget.goal,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (header != null) ...[header, const SizedBox(height: 4)],
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (details) => _select(details.localPosition, width),
          onHorizontalDragUpdate: (details) =>
              _select(details.localPosition, width),
          child: SizedBox(
            height: _height,
            width: width,
            child: CustomPaint(
              painter: _WeightChartPainter(chart: widget, selected: selected),
            ),
          ),
        );
      }),
    ]);
  }
}

/// One line above the chart: the dates shown (or the tapped day) and how
/// much the weight changed.
class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.label,
    required this.goal,
    this.change,
    this.suffix = '',
    this.onClear,
  });

  final String label;
  final String goal;
  final double? change;
  final String suffix;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final change = this.change;
    return SizedBox(
      height: 32,
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: onClear == null ? AppColors.muted : AppColors.navy,
                  fontWeight:
                      onClear == null ? FontWeight.w500 : FontWeight.w800,
                  fontSize: 13)),
        ),
        if (change != null)
          Text('${_changeWords(change)}$suffix',
              style: TextStyle(
                  color: _changeColor(change, goal),
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        if (onClear != null)
          IconButton(
            tooltip: 'ปิด',
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ]),
    );
  }
}

/// Shared positions for the painter and tap handling.
class _ChartGeometry {
  _ChartGeometry(this.chart, this.size) {
    final values = [
      for (final entry in chart.entries) entry.weight,
      if (chart.target != null) chart.target!,
    ];
    var low = values.isEmpty ? 50.0 : values.reduce(math.min);
    var high = values.isEmpty ? 80.0 : values.reduce(math.max);
    // Whole kilograms with room for the labels above the points.
    low = (low - .5).floorToDouble();
    high = (high + 1).ceilToDouble();
    if (high - low < 4) {
      final middle = (high + low) / 2;
      low = (middle - 2).floorToDouble();
      high = low + 4;
    }
    minValue = low;
    maxValue = high;
  }

  final _WeightChart chart;
  final Size size;
  late final double minValue;
  late final double maxValue;

  static const left = 30.0;
  static const right = 16.0;
  static const top = 8.0;
  static const bottom = 26.0;

  double get width => size.width - left - right;
  double get height => size.height - top - bottom;
  int get span => math.max(1, chart.to.difference(chart.from).inDays);

  double x(DateTime date) =>
      left + width * (date.difference(chart.from).inDays / span).clamp(0, 1);
  double y(double value) =>
      top + height * (1 - (value - minValue) / (maxValue - minValue));
}

class _WeightChartPainter extends CustomPainter {
  _WeightChartPainter({required this.chart, required this.selected});

  final _WeightChart chart;
  final int? selected;
  double _width = 0;

  @override
  void paint(Canvas canvas, Size size) {
    _width = size.width;
    final g = _ChartGeometry(chart, size);
    final entries = chart.entries;
    final right = size.width - _ChartGeometry.right;
    final bottom = _ChartGeometry.top + g.height;

    // Horizontal grid with kilogram labels.
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final range = g.maxValue - g.minValue;
    final step = range <= 6
        ? 1.0
        : range <= 12
            ? 2.0
            : 5.0;
    for (var value = (g.minValue / step).ceil() * step;
        value <= g.maxValue;
        value += step) {
      final dy = g.y(value);
      canvas.drawLine(Offset(_ChartGeometry.left, dy), Offset(right, dy), grid);
      _text(canvas, value.toStringAsFixed(0), Offset(0, dy - 7));
    }

    // Goal weight as a dashed line with its own label.
    final target = chart.target;
    if (target != null) {
      final dy = g.y(target);
      final paint = Paint()
        ..color = AppColors.orange
        ..strokeWidth = 2;
      for (double dx = _ChartGeometry.left; dx < right; dx += 10) {
        canvas.drawLine(
            Offset(dx, dy), Offset(math.min(dx + 6, right), dy), paint);
      }
      _label(canvas, 'เป้าหมาย ${target.toStringAsFixed(1)}',
          Offset(right, dy - 22), AppColors.orange,
          alignRight: true);
    }

    // Dates under the axis: one per point when there are few, otherwise
    // four evenly spaced dates.
    final dates = <DateTime>[];
    if (entries.isNotEmpty && entries.length <= 5) {
      dates.addAll(entries.map((entry) => entry.date));
    } else {
      for (var i = 0; i < 4; i++) {
        dates.add(chart.from.add(Duration(days: (g.span * i / 3).round())));
      }
    }
    var lastRight = -double.infinity;
    for (final date in dates) {
      final dx = g.x(date);
      final painter = _painter(_dayMonth(date), AppColors.muted, 10);
      final left = (dx - painter.width / 2)
          .clamp(_ChartGeometry.left - 4, size.width - painter.width);
      if (left < lastRight + 6) continue;
      painter.paint(canvas, Offset(left, bottom + 8));
      lastRight = left + painter.width;
    }

    if (entries.isEmpty) return;
    final points = [
      for (final entry in entries) Offset(g.x(entry.date), g.y(entry.weight))
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    if (points.length > 1) {
      final fill = Path.from(line)
        ..lineTo(points.last.dx, bottom)
        ..lineTo(points.first.dx, bottom)
        ..close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.teal.withValues(alpha: .2),
                AppColors.teal.withValues(alpha: 0),
              ],
            ).createShader(Offset.zero & size));
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.teal
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    final index = selected;
    if (index != null && index < points.length) {
      final point = points[index];
      canvas.drawLine(
          Offset(point.dx, _ChartGeometry.top),
          Offset(point.dx, bottom),
          Paint()
            ..color = AppColors.navy.withValues(alpha: .2)
            ..strokeWidth = 1);
    }
    for (final (i, point) in points.indexed) {
      final active = i == index || (index == null && i == points.length - 1);
      canvas.drawCircle(point, active ? 7 : 5, Paint()..color = Colors.white);
      canvas.drawCircle(
          point,
          active ? 7 : 5,
          Paint()
            ..color = active ? AppColors.tealDark : AppColors.teal
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      // Weight above each point when they fit, and always on the active one.
      if (points.length <= 8 || active) {
        _label(
            canvas,
            entries[i].weight.toStringAsFixed(1),
            Offset(point.dx, point.dy - 26),
            active ? AppColors.tealDark : AppColors.navy,
            center: true,
            filled: active);
      }
    }
  }

  TextPainter _painter(String text, Color color, double fontSize,
          {FontWeight weight = FontWeight.w500}) =>
      TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: color, fontSize: fontSize, fontWeight: weight)),
        textDirection: TextDirection.ltr,
      )..layout();

  void _text(Canvas canvas, String text, Offset at) =>
      _painter(text, AppColors.muted, 10).paint(canvas, at);

  /// A small label, optionally on a coloured pill, kept inside the chart.
  void _label(Canvas canvas, String text, Offset at, Color color,
      {bool center = false, bool alignRight = false, bool filled = false}) {
    final painter = _painter(text, filled ? Colors.white : color, 11,
        weight: FontWeight.w800);
    var dx = alignRight
        ? at.dx - painter.width
        : center
            ? at.dx - painter.width / 2
            : at.dx;
    dx = dx.clamp(
        _ChartGeometry.left,
        math.max(_ChartGeometry.left,
            _width - _ChartGeometry.right + 8 - painter.width));
    final dy = math.max(0.0, at.dy);
    if (filled) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  dx - 6, dy - 2, painter.width + 12, painter.height + 4),
              const Radius.circular(8)),
          Paint()..color = color);
    }
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) => true;
}
