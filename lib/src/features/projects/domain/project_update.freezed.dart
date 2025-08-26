// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project_update.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$ProjectUpdate {
  String get id => throw _privateConstructorUsedError;
  String get projectId => throw _privateConstructorUsedError;
  int get phase => throw _privateConstructorUsedError;
  String? get comment => throw _privateConstructorUsedError;
  List<String> get photos => throw _privateConstructorUsedError;
  List<String> get documents => throw _privateConstructorUsedError;
  String get updatedBy => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Create a copy of ProjectUpdate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProjectUpdateCopyWith<ProjectUpdate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProjectUpdateCopyWith<$Res> {
  factory $ProjectUpdateCopyWith(
    ProjectUpdate value,
    $Res Function(ProjectUpdate) then,
  ) = _$ProjectUpdateCopyWithImpl<$Res, ProjectUpdate>;
  @useResult
  $Res call({
    String id,
    String projectId,
    int phase,
    String? comment,
    List<String> photos,
    List<String> documents,
    String updatedBy,
    DateTime createdAt,
  });
}

/// @nodoc
class _$ProjectUpdateCopyWithImpl<$Res, $Val extends ProjectUpdate>
    implements $ProjectUpdateCopyWith<$Res> {
  _$ProjectUpdateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ProjectUpdate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? projectId = null,
    Object? phase = null,
    Object? comment = freezed,
    Object? photos = null,
    Object? documents = null,
    Object? updatedBy = null,
    Object? createdAt = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            projectId: null == projectId
                ? _value.projectId
                : projectId // ignore: cast_nullable_to_non_nullable
                      as String,
            phase: null == phase
                ? _value.phase
                : phase // ignore: cast_nullable_to_non_nullable
                      as int,
            comment: freezed == comment
                ? _value.comment
                : comment // ignore: cast_nullable_to_non_nullable
                      as String?,
            photos: null == photos
                ? _value.photos
                : photos // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            documents: null == documents
                ? _value.documents
                : documents // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            updatedBy: null == updatedBy
                ? _value.updatedBy
                : updatedBy // ignore: cast_nullable_to_non_nullable
                      as String,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ProjectUpdateImplCopyWith<$Res>
    implements $ProjectUpdateCopyWith<$Res> {
  factory _$$ProjectUpdateImplCopyWith(
    _$ProjectUpdateImpl value,
    $Res Function(_$ProjectUpdateImpl) then,
  ) = __$$ProjectUpdateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String projectId,
    int phase,
    String? comment,
    List<String> photos,
    List<String> documents,
    String updatedBy,
    DateTime createdAt,
  });
}

/// @nodoc
class __$$ProjectUpdateImplCopyWithImpl<$Res>
    extends _$ProjectUpdateCopyWithImpl<$Res, _$ProjectUpdateImpl>
    implements _$$ProjectUpdateImplCopyWith<$Res> {
  __$$ProjectUpdateImplCopyWithImpl(
    _$ProjectUpdateImpl _value,
    $Res Function(_$ProjectUpdateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ProjectUpdate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? projectId = null,
    Object? phase = null,
    Object? comment = freezed,
    Object? photos = null,
    Object? documents = null,
    Object? updatedBy = null,
    Object? createdAt = null,
  }) {
    return _then(
      _$ProjectUpdateImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        projectId: null == projectId
            ? _value.projectId
            : projectId // ignore: cast_nullable_to_non_nullable
                  as String,
        phase: null == phase
            ? _value.phase
            : phase // ignore: cast_nullable_to_non_nullable
                  as int,
        comment: freezed == comment
            ? _value.comment
            : comment // ignore: cast_nullable_to_non_nullable
                  as String?,
        photos: null == photos
            ? _value._photos
            : photos // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        documents: null == documents
            ? _value._documents
            : documents // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        updatedBy: null == updatedBy
            ? _value.updatedBy
            : updatedBy // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
      ),
    );
  }
}

/// @nodoc

class _$ProjectUpdateImpl extends _ProjectUpdate {
  const _$ProjectUpdateImpl({
    required this.id,
    required this.projectId,
    required this.phase,
    this.comment,
    final List<String> photos = const <String>[],
    final List<String> documents = const <String>[],
    required this.updatedBy,
    required this.createdAt,
  }) : _photos = photos,
       _documents = documents,
       super._();

  @override
  final String id;
  @override
  final String projectId;
  @override
  final int phase;
  @override
  final String? comment;
  final List<String> _photos;
  @override
  @JsonKey()
  List<String> get photos {
    if (_photos is EqualUnmodifiableListView) return _photos;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_photos);
  }

  final List<String> _documents;
  @override
  @JsonKey()
  List<String> get documents {
    if (_documents is EqualUnmodifiableListView) return _documents;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_documents);
  }

  @override
  final String updatedBy;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'ProjectUpdate(id: $id, projectId: $projectId, phase: $phase, comment: $comment, photos: $photos, documents: $documents, updatedBy: $updatedBy, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProjectUpdateImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.projectId, projectId) ||
                other.projectId == projectId) &&
            (identical(other.phase, phase) || other.phase == phase) &&
            (identical(other.comment, comment) || other.comment == comment) &&
            const DeepCollectionEquality().equals(other._photos, _photos) &&
            const DeepCollectionEquality().equals(
              other._documents,
              _documents,
            ) &&
            (identical(other.updatedBy, updatedBy) ||
                other.updatedBy == updatedBy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    projectId,
    phase,
    comment,
    const DeepCollectionEquality().hash(_photos),
    const DeepCollectionEquality().hash(_documents),
    updatedBy,
    createdAt,
  );

  /// Create a copy of ProjectUpdate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProjectUpdateImplCopyWith<_$ProjectUpdateImpl> get copyWith =>
      __$$ProjectUpdateImplCopyWithImpl<_$ProjectUpdateImpl>(this, _$identity);
}

abstract class _ProjectUpdate extends ProjectUpdate {
  const factory _ProjectUpdate({
    required final String id,
    required final String projectId,
    required final int phase,
    final String? comment,
    final List<String> photos,
    final List<String> documents,
    required final String updatedBy,
    required final DateTime createdAt,
  }) = _$ProjectUpdateImpl;
  const _ProjectUpdate._() : super._();

  @override
  String get id;
  @override
  String get projectId;
  @override
  int get phase;
  @override
  String? get comment;
  @override
  List<String> get photos;
  @override
  List<String> get documents;
  @override
  String get updatedBy;
  @override
  DateTime get createdAt;

  /// Create a copy of ProjectUpdate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProjectUpdateImplCopyWith<_$ProjectUpdateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
