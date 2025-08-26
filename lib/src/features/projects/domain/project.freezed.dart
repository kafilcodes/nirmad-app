// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Project {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String get ownerId => throw _privateConstructorUsedError;
  String get blockId => throw _privateConstructorUsedError;
  String get villageId => throw _privateConstructorUsedError;
  ProjectStatus get status => throw _privateConstructorUsedError;
  int get phase => throw _privateConstructorUsedError;
  GeoPoint? get location => throw _privateConstructorUsedError;
  Map<String, dynamic> get landDetails => throw _privateConstructorUsedError;
  Map<String, dynamic> get financials => throw _privateConstructorUsedError;
  List<String> get attachments => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime get updatedAt => throw _privateConstructorUsedError;
  DateTime? get completedAt => throw _privateConstructorUsedError;

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProjectCopyWith<Project> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProjectCopyWith<$Res> {
  factory $ProjectCopyWith(Project value, $Res Function(Project) then) =
      _$ProjectCopyWithImpl<$Res, Project>;
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    String ownerId,
    String blockId,
    String villageId,
    ProjectStatus status,
    int phase,
    GeoPoint? location,
    Map<String, dynamic> landDetails,
    Map<String, dynamic> financials,
    List<String> attachments,
    DateTime createdAt,
    DateTime updatedAt,
    DateTime? completedAt,
  });
}

/// @nodoc
class _$ProjectCopyWithImpl<$Res, $Val extends Project>
    implements $ProjectCopyWith<$Res> {
  _$ProjectCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? ownerId = null,
    Object? blockId = null,
    Object? villageId = null,
    Object? status = null,
    Object? phase = null,
    Object? location = freezed,
    Object? landDetails = null,
    Object? financials = null,
    Object? attachments = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? completedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            ownerId: null == ownerId
                ? _value.ownerId
                : ownerId // ignore: cast_nullable_to_non_nullable
                      as String,
            blockId: null == blockId
                ? _value.blockId
                : blockId // ignore: cast_nullable_to_non_nullable
                      as String,
            villageId: null == villageId
                ? _value.villageId
                : villageId // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as ProjectStatus,
            phase: null == phase
                ? _value.phase
                : phase // ignore: cast_nullable_to_non_nullable
                      as int,
            location: freezed == location
                ? _value.location
                : location // ignore: cast_nullable_to_non_nullable
                      as GeoPoint?,
            landDetails: null == landDetails
                ? _value.landDetails
                : landDetails // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>,
            financials: null == financials
                ? _value.financials
                : financials // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>,
            attachments: null == attachments
                ? _value.attachments
                : attachments // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            updatedAt: null == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            completedAt: freezed == completedAt
                ? _value.completedAt
                : completedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ProjectImplCopyWith<$Res> implements $ProjectCopyWith<$Res> {
  factory _$$ProjectImplCopyWith(
    _$ProjectImpl value,
    $Res Function(_$ProjectImpl) then,
  ) = __$$ProjectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    String ownerId,
    String blockId,
    String villageId,
    ProjectStatus status,
    int phase,
    GeoPoint? location,
    Map<String, dynamic> landDetails,
    Map<String, dynamic> financials,
    List<String> attachments,
    DateTime createdAt,
    DateTime updatedAt,
    DateTime? completedAt,
  });
}

/// @nodoc
class __$$ProjectImplCopyWithImpl<$Res>
    extends _$ProjectCopyWithImpl<$Res, _$ProjectImpl>
    implements _$$ProjectImplCopyWith<$Res> {
  __$$ProjectImplCopyWithImpl(
    _$ProjectImpl _value,
    $Res Function(_$ProjectImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? ownerId = null,
    Object? blockId = null,
    Object? villageId = null,
    Object? status = null,
    Object? phase = null,
    Object? location = freezed,
    Object? landDetails = null,
    Object? financials = null,
    Object? attachments = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? completedAt = freezed,
  }) {
    return _then(
      _$ProjectImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        ownerId: null == ownerId
            ? _value.ownerId
            : ownerId // ignore: cast_nullable_to_non_nullable
                  as String,
        blockId: null == blockId
            ? _value.blockId
            : blockId // ignore: cast_nullable_to_non_nullable
                  as String,
        villageId: null == villageId
            ? _value.villageId
            : villageId // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as ProjectStatus,
        phase: null == phase
            ? _value.phase
            : phase // ignore: cast_nullable_to_non_nullable
                  as int,
        location: freezed == location
            ? _value.location
            : location // ignore: cast_nullable_to_non_nullable
                  as GeoPoint?,
        landDetails: null == landDetails
            ? _value._landDetails
            : landDetails // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>,
        financials: null == financials
            ? _value._financials
            : financials // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>,
        attachments: null == attachments
            ? _value._attachments
            : attachments // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        updatedAt: null == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        completedAt: freezed == completedAt
            ? _value.completedAt
            : completedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
      ),
    );
  }
}

/// @nodoc

class _$ProjectImpl extends _Project {
  const _$ProjectImpl({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.blockId,
    required this.villageId,
    this.status = ProjectStatus.draft,
    this.phase = 0,
    this.location,
    final Map<String, dynamic> landDetails = const {},
    final Map<String, dynamic> financials = const {},
    final List<String> attachments = const <String>[],
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  }) : _landDetails = landDetails,
       _financials = financials,
       _attachments = attachments,
       super._();

  @override
  final String id;
  @override
  final String name;
  @override
  final String? description;
  @override
  final String ownerId;
  @override
  final String blockId;
  @override
  final String villageId;
  @override
  @JsonKey()
  final ProjectStatus status;
  @override
  @JsonKey()
  final int phase;
  @override
  final GeoPoint? location;
  final Map<String, dynamic> _landDetails;
  @override
  @JsonKey()
  Map<String, dynamic> get landDetails {
    if (_landDetails is EqualUnmodifiableMapView) return _landDetails;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_landDetails);
  }

  final Map<String, dynamic> _financials;
  @override
  @JsonKey()
  Map<String, dynamic> get financials {
    if (_financials is EqualUnmodifiableMapView) return _financials;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_financials);
  }

  final List<String> _attachments;
  @override
  @JsonKey()
  List<String> get attachments {
    if (_attachments is EqualUnmodifiableListView) return _attachments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_attachments);
  }

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? completedAt;

  @override
  String toString() {
    return 'Project(id: $id, name: $name, description: $description, ownerId: $ownerId, blockId: $blockId, villageId: $villageId, status: $status, phase: $phase, location: $location, landDetails: $landDetails, financials: $financials, attachments: $attachments, createdAt: $createdAt, updatedAt: $updatedAt, completedAt: $completedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProjectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.ownerId, ownerId) || other.ownerId == ownerId) &&
            (identical(other.blockId, blockId) || other.blockId == blockId) &&
            (identical(other.villageId, villageId) ||
                other.villageId == villageId) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.phase, phase) || other.phase == phase) &&
            (identical(other.location, location) ||
                other.location == location) &&
            const DeepCollectionEquality().equals(
              other._landDetails,
              _landDetails,
            ) &&
            const DeepCollectionEquality().equals(
              other._financials,
              _financials,
            ) &&
            const DeepCollectionEquality().equals(
              other._attachments,
              _attachments,
            ) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    description,
    ownerId,
    blockId,
    villageId,
    status,
    phase,
    location,
    const DeepCollectionEquality().hash(_landDetails),
    const DeepCollectionEquality().hash(_financials),
    const DeepCollectionEquality().hash(_attachments),
    createdAt,
    updatedAt,
    completedAt,
  );

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProjectImplCopyWith<_$ProjectImpl> get copyWith =>
      __$$ProjectImplCopyWithImpl<_$ProjectImpl>(this, _$identity);
}

abstract class _Project extends Project {
  const factory _Project({
    required final String id,
    required final String name,
    final String? description,
    required final String ownerId,
    required final String blockId,
    required final String villageId,
    final ProjectStatus status,
    final int phase,
    final GeoPoint? location,
    final Map<String, dynamic> landDetails,
    final Map<String, dynamic> financials,
    final List<String> attachments,
    required final DateTime createdAt,
    required final DateTime updatedAt,
    final DateTime? completedAt,
  }) = _$ProjectImpl;
  const _Project._() : super._();

  @override
  String get id;
  @override
  String get name;
  @override
  String? get description;
  @override
  String get ownerId;
  @override
  String get blockId;
  @override
  String get villageId;
  @override
  ProjectStatus get status;
  @override
  int get phase;
  @override
  GeoPoint? get location;
  @override
  Map<String, dynamic> get landDetails;
  @override
  Map<String, dynamic> get financials;
  @override
  List<String> get attachments;
  @override
  DateTime get createdAt;
  @override
  DateTime get updatedAt;
  @override
  DateTime? get completedAt;

  /// Create a copy of Project
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProjectImplCopyWith<_$ProjectImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
