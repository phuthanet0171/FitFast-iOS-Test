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
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<WeightEntry> _entries = [];
  HealthProfile? _profile;
  int _rangeDays = 30;
  bool _loading = true;

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
  }

  List<WeightEntry> get _filteredEntries {
    final cutoff = DateTime.now().subtract(Duration(days: _rangeDays - 1));
    final day = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return _entries.where((entry) => !entry.date.isBefore(day)).toList();
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
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(DateTime.now().year - 5),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setSheetState(() => selectedDate = date);
                  }
                },
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(_dateLabel(selectedDate)),
              ),
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
    await WeightHistoryService.instance.save(result);
    await _load();
    if (!mounted) return;
    showAppSnackBar(
      context,
      existing == null ? 'บันทึกน้ำหนักแล้ว' : 'แก้ไขน้ำหนักแล้ว',
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    final filtered = _filteredEntries;
    final latest = _entries.isEmpty ? null : _entries.last;
    final first = _entries.isEmpty ? null : _entries.first;
    final change =
        latest == null || first == null ? 0.0 : latest.weight - first.weight;
    final target = _profile?.targetWeight;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('ความก้าวหน้า',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 5),
                    const Text(
                        'ติดตามแนวโน้มน้ำหนัก ไม่ยึดติดกับตัวเลขวันเดียว',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ])),
              IconButton.filled(
                  onPressed: () => _openEditor(),
                  tooltip: 'บันทึกน้ำหนัก',
                  icon: const Icon(Icons.add_rounded)),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: _SummaryCard(
                      label: 'ล่าสุด',
                      value: latest == null
                          ? '—'
                          : '${latest.weight.toStringAsFixed(1)} กก.',
                      color: AppColors.teal)),
              const SizedBox(width: 10),
              Expanded(
                  child: _SummaryCard(
                      label: 'เปลี่ยนแปลง',
                      value: _entries.length < 2
                          ? '—'
                          : '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} กก.',
                      color: change <= 0 ? AppColors.blue : AppColors.orange)),
              const SizedBox(width: 10),
              Expanded(
                  child: _SummaryCard(
                      label: 'เป้าหมาย',
                      value: target == null
                          ? '—'
                          : '${target.toStringAsFixed(1)} กก.',
                      color: AppColors.orange)),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('แนวโน้มน้ำหนัก',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 14),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: const [
                          _RangeChip(label: '1 สัปดาห์', days: 7),
                          _RangeChip(label: '3 สัปดาห์', days: 21),
                          _RangeChip(label: '1 เดือน', days: 30),
                          _RangeChip(label: '3 เดือน', days: 90),
                          _RangeChip(label: '6 เดือน', days: 180),
                          _RangeChip(label: '1 ปี', days: 365),
                        ]
                                .map((chip) => Padding(
                                      padding: const EdgeInsets.only(right: 7),
                                      child: ChoiceChip(
                                        label: Text(chip.label),
                                        selected: _rangeDays == chip.days,
                                        onSelected: (_) => setState(
                                            () => _rangeDays = chip.days),
                                      ),
                                    ))
                                .toList()),
                      ),
                      const SizedBox(height: 20),
                      if (filtered.isEmpty)
                        const SizedBox(
                            height: 190,
                            child: Center(
                                child: Text('ยังไม่มีข้อมูลในช่วงเวลานี้',
                                    style: TextStyle(color: AppColors.muted))))
                      else
                        SizedBox(
                          height: 220,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _WeightChartPainter(
                                entries: filtered, target: target),
                          ),
                        ),
                    ]),
              ),
            ),
            const SizedBox(height: 18),
            Text('ประวัติล่าสุด',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (_entries.isEmpty)
              Card(
                  child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  const Icon(Icons.monitor_weight_outlined,
                      size: 48, color: AppColors.muted),
                  const SizedBox(height: 12),
                  const Text('เริ่มบันทึกน้ำหนักเพื่อดูแนวโน้ม',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('บันทึกน้ำหนัก')),
                ]),
              ))
            else
              ..._entries.reversed.take(10).map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Card(
                        child: ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: AppColors.mint,
                          child: Icon(Icons.monitor_weight_outlined,
                              color: AppColors.tealDark)),
                      title: Text('${entry.weight.toStringAsFixed(1)} กก.',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(entry.note.isEmpty
                          ? _dateLabel(entry.date)
                          : '${_dateLabel(entry.date)} · ${entry.note}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => value == 'edit'
                            ? _openEditor(entry)
                            : _delete(entry),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                          PopupMenuItem(value: 'delete', child: Text('ลบ')),
                        ],
                      ),
                    )),
                  )),
          ],
        ),
      ),
    );
  }
}

class _RangeChip {
  const _RangeChip({required this.label, required this.days});
  final String label;
  final int days;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 5),
          FittedBox(
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 17))),
        ]),
      );
}

class _WeightChartPainter extends CustomPainter {
  const _WeightChartPainter({required this.entries, required this.target});
  final List<WeightEntry> entries;
  final double? target;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 28.0;
    final values = entries.map((entry) => entry.weight).toList();
    if (target != null) values.add(target!);
    var minValue = values.reduce(math.min) - 1;
    var maxValue = values.reduce(math.max) + 1;
    if (maxValue - minValue < 2) {
      minValue -= 1;
      maxValue += 1;
    }
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    double x(int index) => entries.length == 1
        ? left + chartWidth / 2
        : left + chartWidth * index / (entries.length - 1);
    double y(double value) =>
        top + chartHeight * (1 - (value - minValue) / (maxValue - minValue));

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final dy = top + chartHeight * i / 4;
      canvas.drawLine(
          Offset(left, dy), Offset(size.width - right, dy), gridPaint);
    }
    if (target != null) {
      final targetPaint = Paint()
        ..color = AppColors.orange
        ..strokeWidth = 1.5;
      final dy = y(target!);
      for (double dx = left; dx < size.width - right; dx += 9) {
        canvas.drawLine(Offset(dx, dy),
            Offset(math.min(dx + 5, size.width - right), dy), targetPaint);
      }
    }
    final path = Path();
    for (var i = 0; i < entries.length; i++) {
      final point = Offset(x(i), y(entries[i].weight));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.teal
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    final dotPaint = Paint()..color = AppColors.teal;
    for (var i = 0; i < entries.length; i++) {
      canvas.drawCircle(Offset(x(i), y(entries[i].weight)), 4.5, dotPaint);
    }

    final style = const TextStyle(color: AppColors.muted, fontSize: 10);
    final firstLabel = TextPainter(
        text: TextSpan(
            text: '${entries.first.date.day}/${entries.first.date.month}',
            style: style),
        textDirection: TextDirection.ltr)
      ..layout();
    final lastLabel = TextPainter(
        text: TextSpan(
            text: '${entries.last.date.day}/${entries.last.date.month}',
            style: style),
        textDirection: TextDirection.ltr)
      ..layout();
    firstLabel.paint(canvas, Offset(left, size.height - 17));
    lastLabel.paint(
        canvas, Offset(size.width - right - lastLabel.width, size.height - 17));
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.entries != entries || oldDelegate.target != target;
}
