class HealthProfile {
  const HealthProfile({
    required this.age,
    required this.gender,
    required this.height,
    required this.currentWeight,
    required this.targetWeight,
    required this.activity,
    required this.weightGoal,
    required this.updatedAt,
    this.targetDate,
    DateTime? planStartedAt,
  }) : _planStartedAt = planStartedAt;

  final int age;
  final String gender;
  final double height;
  final double currentWeight;
  final double targetWeight;
  final String activity;
  final String weightGoal;

  /// When the profile was last saved.
  final DateTime updatedAt;

  final DateTime? _planStartedAt;

  /// The day the current goal plan started, with [currentWeight] as its
  /// starting weight. Editing other details keeps this day, so progress
  /// is not reset; profiles saved before it existed use [updatedAt].
  DateTime get planStartedAt => _planStartedAt ?? updatedAt;

  /// The day the user wants to reach [targetWeight]; null when maintaining.
  final DateTime? targetDate;

  String get genderLabel => gender == 'male' ? 'ชาย' : 'หญิง';

  String get goalLabel => switch (weightGoal) {
        'lose' => 'ลดน้ำหนัก',
        'gain' => 'เพิ่มน้ำหนัก',
        _ => 'รักษาน้ำหนัก',
      };

  String get activityLabel => switch (activity) {
        'sedentary' => 'กิจกรรมน้อย',
        'moderate' => 'กิจกรรมปานกลาง',
        'high' => 'กิจกรรมสูง',
        _ => 'กิจกรรมเบา',
      };

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'height': height,
        'currentWeight': currentWeight,
        'targetWeight': targetWeight,
        'activity': activity,
        'weightGoal': weightGoal,
        'updatedAt': updatedAt.toIso8601String(),
        'targetDate': targetDate?.toIso8601String(),
        'planStartedAt': _planStartedAt?.toIso8601String(),
      };

  factory HealthProfile.fromJson(Map<String, dynamic> json) => HealthProfile(
        age: (json['age'] as num?)?.toInt() ?? 0,
        gender: json['gender'] as String? ?? 'male',
        height: (json['height'] as num?)?.toDouble() ?? 0,
        currentWeight: (json['currentWeight'] as num?)?.toDouble() ?? 0,
        targetWeight: (json['targetWeight'] as num?)?.toDouble() ?? 0,
        activity: json['activity'] as String? ?? 'light',
        weightGoal: json['weightGoal'] as String? ?? 'maintain',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        targetDate: DateTime.tryParse(json['targetDate'] as String? ?? ''),
        planStartedAt:
            DateTime.tryParse(json['planStartedAt'] as String? ?? ''),
      );

  HealthProfile copyWith({
    double? currentWeight,
    double? targetWeight,
    DateTime? updatedAt,
  }) =>
      HealthProfile(
        age: age,
        gender: gender,
        height: height,
        currentWeight: currentWeight ?? this.currentWeight,
        targetWeight: targetWeight ?? this.targetWeight,
        activity: activity,
        weightGoal: weightGoal,
        updatedAt: updatedAt ?? this.updatedAt,
        targetDate: targetDate,
        planStartedAt: _planStartedAt,
      );
}
