class RecipeIngredient {
  final String name;
  final String amount;

  const RecipeIngredient({required this.name, required this.amount});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeIngredient &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          amount == other.amount;

  @override
  int get hashCode => Object.hash(name, amount);

  RecipeIngredient copyWith({String? name, String? amount}) {
    return RecipeIngredient(
      name: name ?? this.name,
      amount: amount ?? this.amount,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'amount': amount};
  }

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] as String? ?? '',
      amount: json['amount'] as String? ?? '',
    );
  }
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
