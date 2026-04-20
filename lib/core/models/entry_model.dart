import 'package:uuid/uuid.dart';

class EntryModel {
  final String id;
  final String groupId;
  String title;
  String username;
  String password;
  String url;
  String notes;
  String? iconCode;
  DateTime createdAt;
  DateTime updatedAt;
  bool isFavorite;

  EntryModel({
    String? id,
    required this.groupId,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.iconCode,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isFavorite = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  EntryModel copyWith({
    String? groupId,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? iconCode,
    bool? isFavorite,
  }) {
    return EntryModel(
      id: id,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      iconCode: iconCode ?? this.iconCode,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'iconCode': iconCode,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isFavorite': isFavorite,
      };

  factory EntryModel.fromJson(Map<String, dynamic> json) => EntryModel(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        title: json['title'] as String,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        iconCode: json['iconCode'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isFavorite: json['isFavorite'] as bool? ?? false,
      );

  Map<String, dynamic> toDb() => {
        'id': id,
        'group_id': groupId,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'icon_code': iconCode,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'is_favorite': isFavorite ? 1 : 0,
      };

  factory EntryModel.fromDb(Map<String, dynamic> db) => EntryModel(
        id: db['id'] as String,
        groupId: db['group_id'] as String,
        title: db['title'] as String,
        username: db['username'] as String? ?? '',
        password: db['password'] as String? ?? '',
        url: db['url'] as String? ?? '',
        notes: db['notes'] as String? ?? '',
        iconCode: db['icon_code'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(db['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(db['updated_at'] as int),
        isFavorite: (db['is_favorite'] as int? ?? 0) == 1,
      );
}
