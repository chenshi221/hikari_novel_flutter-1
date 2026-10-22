import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'cat_chapter.g.dart';

@JsonSerializable()
class CatChapter {
  final String title;
  final String cid;

  CatChapter({required this.title, required this.cid});

  factory CatChapter.fromJson(Map<String, dynamic> json) => _$CatChapterFromJson(json);

  Map<String, dynamic> toJson() => _$CatChapterToJson(this);

  @override
  String toString() => jsonEncode(toJson());

  factory CatChapter.fromString(String json) => CatChapter.fromJson(jsonDecode(json));
}
