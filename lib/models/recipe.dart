class RecipeIngredient {
  final String name;
  final String quantity;
  final String unit;
  final String amount;

  RecipeIngredient({
    required this.name,
    this.quantity = '',
    this.unit = '',
    String? amount,
  }) : amount = amount ?? _composeAmount(quantity, unit);

  static String _composeAmount(String quantity, String unit) {
    final q = quantity.trim();
    final u = unit.trim();
    if (q.isEmpty && u.isEmpty) return '';
    if (q.isEmpty) return u;
    if (u.isEmpty) return q;
    return '$q$u';
  }

  static _LegacyAmountParts _parseLegacyAmount(String amount) {
    final trimmed = amount.trim();
    if (trimmed.isEmpty) return const _LegacyAmountParts('', '');
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(trimmed);
    if (match == null) {
      return _LegacyAmountParts('', trimmed);
    }
    return _LegacyAmountParts(
      match.group(1) ?? '',
      (match.group(2) ?? '').trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeIngredient &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          quantity == other.quantity &&
          unit == other.unit &&
          amount == other.amount;

  @override
  int get hashCode => Object.hash(name, quantity, unit, amount);

  RecipeIngredient copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? amount,
  }) {
    final preservedAmount = amount ??
        (quantity == null && unit == null ? this.amount : null);
    return RecipeIngredient(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      amount: preservedAmount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'amount': amount,
    };
  }

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'] as String? ?? '';
    final hasNewShape =
        json.containsKey('quantity') || json.containsKey('unit');
    if (hasNewShape) {
      return RecipeIngredient(
        name: json['name'] as String? ?? '',
        quantity: json['quantity'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        amount: amount,
      );
    }
    final parts = _parseLegacyAmount(amount);
    return RecipeIngredient(
      name: json['name'] as String? ?? '',
      quantity: parts.quantity,
      unit: parts.unit,
      amount: amount,
    );
  }
}

class _LegacyAmountParts {
  const _LegacyAmountParts(this.quantity, this.unit);
  final String quantity;
  final String unit;
}

class Recipe {
  final String id;
  final String name;
  final String category;
  final int difficulty;
  final int cookingMinutes;
  final String description;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final List<String> tags;
  final String? imageUrl;

  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.difficulty,
    required this.cookingMinutes,
    required this.description,
    required this.ingredients,
    required this.steps,
    this.tags = const [],
    this.imageUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Recipe && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Recipe copyWith({
    String? id,
    String? name,
    String? category,
    int? difficulty,
    int? cookingMinutes,
    String? description,
    List<RecipeIngredient>? ingredients,
    List<String>? steps,
    List<String>? tags,
    String? imageUrl,
  }) {
    return Recipe(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      cookingMinutes: cookingMinutes ?? this.cookingMinutes,
      description: description ?? this.description,
      ingredients: ingredients ?? this.ingredients,
      steps: steps ?? this.steps,
      tags: tags ?? this.tags,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'difficulty': difficulty,
      'cookingMinutes': cookingMinutes,
      'description': description,
      'ingredients': ingredients.map((e) => e.toJson()).toList(),
      'steps': List<String>.from(steps),
      'tags': List<String>.from(tags),
      'imageUrl': imageUrl,
    };
  }

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 0,
      cookingMinutes: (json['cookingMinutes'] as num?)?.toInt() ?? 30,
      description: json['description'] as String? ?? '',
      ingredients:
          (json['ingredients'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => RecipeIngredient.fromJson(e))
              .toList() ??
          const [],
      steps:
          (json['steps'] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      tags:
          (json['tags'] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

extension RecipeDifficultyLabel on Recipe {
  String get difficultyLabel {
    if (difficulty <= 0) {
      return '难度未设置';
    }

    final level = difficulty.clamp(1, 5).toInt();
    return '难度 $level/5';
  }
}
