typedef ValidateFn = bool Function();
typedef ToModelFn = Map<String, dynamic> Function();

class SectionController {
  final ValidateFn validate;
  final ToModelFn? toModel;
  final bool Function()? isReadOnly;
  const SectionController({required this.validate, this.toModel, this.isReadOnly});
}