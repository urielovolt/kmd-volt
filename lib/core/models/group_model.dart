import 'package:uuid/uuid.dart';

class GroupModel {
  final String id;
  String name;
  String? iconCode;
  int sortOrder;
  DateTime createdAt;

  GroupModel({
    String? id,
    required this.name,
    this.iconCode,
    this.sortOrder = 0,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  GroupModel copyWith({
    String? name,
    String? iconCode,
    int? sortOrder,
  }) {
    return GroupModel(
      id: id,
      name: name ?? this.name,
      iconCode: iconCode ?? this.iconCode,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconCode': iconCode,
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
        id: json['id'] as String,
        name: json['name'] as String,
        iconCode: json['iconCode'] as String?,
        sortOrder: json['sortOrder'] as int? ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toDb() => {
        'id': id,
        'name': name,
        'icon_code': iconCode,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory GroupModel.fromDb(Map<String, dynamic> db) => GroupModel(
        id: db['id'] as String,
        name: db['name'] as String,
        iconCode: db['icon_code'] as String?,
        sortOrder: db['sort_order'] as int? ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(db['created_at'] as int),
      );

  // Default groups to pre-populate
  static List<GroupModel> get defaults => [
        GroupModel(name: 'General',        iconCode: 'lock',    sortOrder: 0),
        GroupModel(name: 'Redes Sociales', iconCode: 'people',  sortOrder: 1),
        GroupModel(name: 'Correos',        iconCode: 'email',   sortOrder: 2),
        GroupModel(name: 'Bancos',         iconCode: 'bank',    sortOrder: 3),
        GroupModel(name: 'Trabajo',        iconCode: 'work',    sortOrder: 4),
      ];
}
