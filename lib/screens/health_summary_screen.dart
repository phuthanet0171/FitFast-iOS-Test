import 'package:flutter/material.dart';

import '../models/health_result.dart';
import '../services/health_calculator.dart';
import '../theme/app_theme.dart';
import '../widgets/goal_pace.dart';
import 'health_onboarding_screen.dart' show thaiDate;
import 'if_interest_screen.dart';

/// The plan after the health questions, built around one number the user
/// acts on every day (calories to eat), with BMI, BMR and TDEE explained in
/// plain words as the steps that lead to it.
class HealthSummaryScreen extends StatelessWidget {
  const HealthSummaryScreen({
    super.key,
    required this.age,
    required this.height,
    required this.currentWeight,
    required this.targetWeight,
    required this.result,
    this.activity,
  });

  final int age;
  final double height;
  final double currentWeight;
  final double targetWeight;
  final HealthResult result;

  /// sedentary, light, moderate or high; used to name the activity step.
  final String? activity;

  String get _activityLabel => switch (activity) {
        'sedentary' => 'กิจกรรมน้อย',
        'moderate' => 'กิจกรรมปานกลาง',
        'high' => 'กิจกรรมสูง',
        _ => 'กิจกรรมเบา',
      };

  /// The chosen pace goes beyond the guidelines: intake below the calorie
  /// floor when losing, or a surplus above 20% of TDEE when gaining.
  bool get _beyondGuideline {
    final floor = result.calorieFloor;
    return result.weightGoal == 'gain'
        ? result.dailyAdjustment >
            result.tdee * HealthCalculator.maxSurplusShare + 1e-6
        : floor != null && result.calories < floor - 1e-6;
  }

  String get _goalSentence {
    final date = result.targetDate;
    final weight = '${targetWeight.toStringAsFixed(1)} กก.';
    return switch (result.weightGoal) {
      'lose' when date != null =>
        'เพื่อลดน้ำหนักเหลือ $weight ภายใน ${thaiDate(date)}',
      'gain' when date != null =>
        'เพื่อเพิ่มน้ำหนักเป็น $weight ภายใน ${thaiDate(date)}',
      'lose' => 'เพื่อลดน้ำหนักเหลือ $weight',
      'gain' => 'เพื่อเพิ่มน้ำหนักเป็น $weight',
      _ => 'เพื่อรักษาน้ำหนัก ${currentWeight.toStringAsFixed(1)} กก.',
    };
  }

  String _adjustmentSentence() {
    final change = result.dailyAdjustment.abs().round();
    return switch (result.weightGoal) {
      'lose' => 'แผนนี้ให้กินน้อยกว่าที่ใช้วันละ ${_withComma(change)} kcal '
          'ร่างกายจึงดึงพลังงานสะสมมาใช้และน้ำหนักค่อยๆ ลดลง',
      'gain' => 'แผนนี้ให้กินมากกว่าที่ใช้วันละ ${_withComma(change)} kcal '
          'ร่างกายจึงมีพลังงานเหลือไว้เพิ่มน้ำหนัก',
      _ => 'แผนนี้ให้กินเท่ากับที่ใช้ น้ำหนักจึงคงที่',
    };
  }

  /// Asia-Pacific BMI classification (WHO Western Pacific Region, 2000;
  /// WHO Expert Consultation, 2004), as used for Thai adults.
  static (String, Color) _bmiBand(double bmi) {
    for (final band in _bmiBands) {
      if (bmi < band.$2) return (band.$4, band.$3);
    }
    return (_bmiBands.last.$4, _bmiBands.last.$3);
  }

  void _showInfo(
    BuildContext context, {
    required String title,
    required String body,
    Widget? extra,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(height: 1.55)),
              if (extra != null) ...[const SizedBox(height: 18), extra],
            ],
          ),
        ),
      ),
    );
  }

  void _continue(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IfInterestScreen(
          age: age,
          bmi: result.bmi,
          healthResult: result,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แผนของคุณ')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(
          onPressed: () => _continue(context),
          child: const Text('ถัดไป'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          _CalorieHero(
            calories: result.calories,
            goalSentence: _goalSentence,
            weeks:
                result.planDays == null ? null : (result.planDays! / 7).round(),
            weeklyChangeKg: result.weeklyChangeKg,
          ),
          if (_beyondGuideline) ...[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.warning_amber_rounded,
              text: result.weightGoal == 'gain'
                  ? 'ความเร็วที่เลือกเกินกว่าที่แนะนำ อาจได้ไขมันมากกว่ากล้ามเนื้อ'
                  : 'พลังงานต่ำกว่าขั้นต่ำที่แนะนำ ควรปรึกษาผู้เชี่ยวชาญ',
            ),
          ],
          if (result.usesTeenSafetyMode) ...[
            const SizedBox(height: 10),
            const _Notice(
              icon: Icons.health_and_safety_outlined,
              text: 'สำหรับอายุ 16–17 ปี ระบบใช้เป้าหมายรักษาน้ำหนัก '
                  'และไม่เปิดการทำ IF เพราะร่างกายยังต้องการพลังงานเพื่อการเจริญเติบโต',
            ),
          ],
          const SizedBox(height: 14),
          _GoalCard(
            goal: result.weightGoal,
            currentWeight: currentWeight,
            targetWeight: targetWeight,
            weeklyChangeKg: result.weeklyChangeKg,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _StatTile(
                label: 'BMI',
                value: result.bmi.toStringAsFixed(1),
                caption: _bmiBand(result.bmi).$1,
                color: _bmiBand(result.bmi).$2,
                onInfo: () => _showInfo(
                  context,
                  title: 'ดัชนีมวลกาย (BMI)',
                  body:
                      'เทียบน้ำหนักกับส่วนสูง เพื่อดูว่าน้ำหนักอยู่ในช่วงที่เหมาะสมหรือไม่',
                  extra: _BmiScale(bmi: result.bmi),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'ร่างกายใช้วันละ',
                value: _withComma(result.tdee.round()),
                caption: 'kcal',
                color: AppColors.blue,
                onInfo: () => _showInfo(
                  context,
                  title: 'พลังงานที่ร่างกายใช้',
                  body: 'ร่างกายใช้พลังงานพื้นฐาน (BMR) '
                      '${_withComma(result.bmr.round())} kcal แม้นอนเฉยๆ '
                      'เพื่อหายใจและให้หัวใจเต้น เมื่อรวมการเคลื่อนไหวแบบ'
                      '$_activityLabel จะใช้ทั้งวัน (TDEE) '
                      '${_withComma(result.tdee.round())} kcal\n\n'
                      '${_adjustmentSentence()}',
                ),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          const _SectionTitle('สารอาหารต่อวัน'),
          const SizedBox(height: 10),
          _MacroCard(result: result),
          const SizedBox(height: 16),
          const Text(
            'ค่าที่แสดงเป็นการประมาณเบื้องต้นจากสูตรมาตรฐาน '
            'ไม่ใช่คำวินิจฉัยทางการแพทย์',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}

/// The one number to act on: calories to eat per day.
class _CalorieHero extends StatelessWidget {
  const _CalorieHero({
    required this.calories,
    required this.goalSentence,
    required this.weeks,
    required this.weeklyChangeKg,
  });

  final double calories;
  final String goalSentence;
  final int? weeks;
  final double? weeklyChangeKg;

  @override
  Widget build(BuildContext context) {
    final change = weeklyChangeKg;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [AppColors.teal, AppColors.tealDark]),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ควรกินวันละ',
            style: TextStyle(color: Color(0xFFD7F5ED), fontSize: 15)),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_withComma(calories.round()),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  height: 1.1,
                  fontWeight: FontWeight.w900)),
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 6),
            child: Text('kcal',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(goalSentence,
            style: const TextStyle(color: Colors.white, height: 1.4)),
        if (weeks != null && change != null) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Pill(icon: Icons.event_rounded, text: 'ประมาณ $weeks สัปดาห์'),
            _Pill(
              icon: change < 0
                  ? Icons.trending_down_rounded
                  : Icons.trending_up_rounded,
              text: '${change < 0 ? 'ลด' : 'เพิ่ม'}ราว '
                  '${change.abs().toStringAsFixed(2)} กก./สัปดาห์',
            ),
          ]),
        ],
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

/// The goal the user chose: weight now, goal weight and pace.
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.currentWeight,
    required this.targetWeight,
    required this.weeklyChangeKg,
  });

  final String goal;
  final double currentWeight;
  final double targetWeight;
  final double? weeklyChangeKg;

  @override
  Widget build(BuildContext context) {
    final rate = weeklyChangeKg?.abs();
    final change = (targetWeight - currentWeight).abs();
    Widget weight(String label, double value, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text('${value.toStringAsFixed(1)} กก.',
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('เป้าหมายที่เลือก',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (goal == 'maintain')
          weight('รักษาน้ำหนักที่', currentWeight, AppColors.navy)
        else ...[
          Row(children: [
            Expanded(child: weight('ตอนนี้', currentWeight, AppColors.navy)),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
                child: weight('เป้าหมาย', targetWeight, AppColors.tealDark)),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${goal == 'lose' ? 'ลด' : 'เพิ่ม'} '
                '${change.toStringAsFixed(1)} กก.'
                '${rate == null ? '' : ' · ${formatKgPerWeek(rate)} กก./สัปดาห์'}',
                style: const TextStyle(fontSize: 13),
              ),
              if (rate != null) PaceLevelChip(level: PaceLevel.of(goal, rate)),
            ],
          ),
        ],
      ]),
    );
  }
}

/// A small figure with a button that explains it.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.onInfo,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onInfo,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ),
                const Icon(Icons.info_outline_rounded,
                    size: 18, color: AppColors.muted),
              ]),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 26, fontWeight: FontWeight.w900)),
              Text(caption,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Asia-Pacific BMI bands: lower bound, upper bound, colour, label.
const _bmiBands = [
  (0.0, 18.5, AppColors.blue, 'ต่ำกว่าเกณฑ์'),
  (18.5, 23.0, AppColors.teal, 'ปกติ'),
  (23.0, 25.0, Color(0xFFD69A00), 'น้ำหนักเกิน'),
  (25.0, 30.0, AppColors.orange, 'อ้วนระดับ 1'),
  (30.0, 99.0, Color(0xFFD84C3E), 'อ้วนระดับ 2'),
];

/// BMI on a coloured scale with the Asia-Pacific cut-offs.
class _BmiScale extends StatelessWidget {
  const _BmiScale({required this.bmi});

  final double bmi;

  static const _min = 15.0;
  static const _max = 35.0;

  @override
  Widget build(BuildContext context) {
    final position = ((bmi - _min) / (_max - _min)).clamp(0.0, 1.0);
    double at(double value) => (value - _min) / (_max - _min);
    final bands = [
      for (final band in _bmiBands)
        (
          band.$1.clamp(_min, _max).toDouble(),
          band.$2.clamp(_min, _max).toDouble(),
          band.$3,
          band.$4
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 40,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              right: 0,
              top: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Row(children: [
                  for (final band in bands)
                    Expanded(
                      flex: ((band.$2 - band.$1) * 10).round(),
                      child: Container(height: 10, color: band.$3),
                    ),
                ]),
              ),
            ),
            Positioned(
              left: (width * position - 9).clamp(0, width - 18),
              top: 0,
              child: Container(
                width: 18,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.navy, width: 3),
                ),
              ),
            ),
            for (final mark in [18.5, 23.0, 25.0, 30.0])
              Positioned(
                left: width * at(mark) - 14,
                top: 24,
                child: SizedBox(
                  width: 28,
                  child: Text(
                      mark == mark.roundToDouble()
                          ? mark.toStringAsFixed(0)
                          : mark.toStringAsFixed(1),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 11)),
                ),
              ),
          ]),
        );
      }),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final band in bands)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: band.$3, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(band.$4, style: const TextStyle(fontSize: 12)),
          ]),
      ]),
      const SizedBox(height: 10),
      const Text('เกณฑ์สำหรับคนเอเชีย (WHO) ช่วงปกติคือ 18.5–22.9',
          style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }
}

/// Protein, carbohydrate and fat as a share of the day's calories.
class _MacroCard extends StatelessWidget {
  const _MacroCard({required this.result});
  final HealthResult result;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (
        'คาร์โบไฮเดรต',
        result.carbs,
        45,
        AppColors.teal,
        'ข้าว แป้ง ผลไม้ ให้พลังงานหลัก'
      ),
      (
        'โปรตีน',
        result.protein,
        25,
        AppColors.blue,
        'เนื้อสัตว์ ไข่ นม ถั่ว ช่วยรักษากล้ามเนื้อ'
      ),
      (
        'ไขมัน',
        result.fat,
        30,
        AppColors.amber,
        'น้ำมัน ถั่ว อะโวคาโด จำเป็นต่อร่างกาย'
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(children: [
              for (final row in rows)
                Expanded(
                  flex: row.$3,
                  child: Container(height: 12, color: row.$4),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          for (final (index, row) in rows.indexed) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: row.$4, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${row.$1}  ${row.$3}%',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
              ),
              Text('${row.$2.round()} กรัม',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
            if (index != rows.length - 1) const Divider(height: 24),
          ],
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.orange),
          const SizedBox(width: 11),
          Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 12, height: 1.45)),
          ),
        ]),
      );
}

String _withComma(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
