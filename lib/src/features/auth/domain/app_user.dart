import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';
part 'app_user.g.dart';

enum UserRole {
  superNodal('super_nodal'),
  subNodal('sub_nodal'),
  projectOwner('project_owner'),
  devAdmin('dev_admin');

  final String key;
  const UserRole(this.key);

  static UserRole? fromKey(String? k) {
    if (k == null) return null;
    return UserRole.values.firstWhere(
      (e) => e.key == k,
      orElse: () => UserRole.projectOwner,
    );
  }
}

@freezed
class AppUser with _$AppUser {
  const factory AppUser({
    required String uid,
    required String email,
    required UserRole role,
  String? blockId,
  @Default(<String>[]) List<String> blocks,
    String? displayName,
    String? assignedVillage,
  }) = _AppUser;

  factory AppUser.fromJson(Map<String, dynamic> json) => _$AppUserFromJson(json);
}
