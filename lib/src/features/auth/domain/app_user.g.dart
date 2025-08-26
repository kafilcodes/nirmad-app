// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AppUserImpl _$$AppUserImplFromJson(Map<String, dynamic> json) =>
    _$AppUserImpl(
      uid: json['uid'] as String,
      email: json['email'] as String,
      role: $enumDecode(_$UserRoleEnumMap, json['role']),
      blocks:
          (json['blocks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      displayName: json['displayName'] as String?,
      assignedVillage: json['assignedVillage'] as String?,
    );

Map<String, dynamic> _$$AppUserImplToJson(_$AppUserImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'email': instance.email,
      'role': _$UserRoleEnumMap[instance.role]!,
      'blocks': instance.blocks,
      'displayName': instance.displayName,
      'assignedVillage': instance.assignedVillage,
    };

const _$UserRoleEnumMap = {
  UserRole.superNodal: 'superNodal',
  UserRole.subNodal: 'subNodal',
  UserRole.projectOwner: 'projectOwner',
  UserRole.devAdmin: 'devAdmin',
};
