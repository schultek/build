import 'package:build/build.dart';
import 'package:build_modules/build_modules.dart';
// ignore: implementation_imports
import 'package:build_modules/src/module_cache.dart';
// ignore: implementation_imports
import 'package:build_modules/src/module_library.dart';
import 'package:collection/collection.dart';

const flutterPackages = {
  'flutter',
  'flutter_test',
};

class JasprModuleBuilder extends ModuleBuilder {
  final DartPlatform platform;

  JasprModuleBuilder(this.platform) : super(platform);

  @override
  Future build(BuildStep buildStep) async {
    final cleanMetaModules = await buildStep.fetchResource(metaModuleCache);
    final metaModule = (await cleanMetaModules.find(
        AssetId(buildStep.inputId.package,
            'lib/${metaModuleCleanExtension(platform)}'),
        buildStep))!;
    var outputModule = metaModule.modules
        .firstWhereOrNull((m) => m.primarySource == buildStep.inputId);
    if (outputModule == null) {
      final serializedLibrary = await buildStep.readAsString(
          buildStep.inputId.changeExtension(moduleLibraryExtension));
      final libraryModule =
          ModuleLibrary.deserialize(buildStep.inputId, serializedLibrary);
      if (libraryModule.hasMain) {
        outputModule = metaModule.modules
            .firstWhere((m) => m.sources.contains(buildStep.inputId));
      }
    }
    if (outputModule == null) return;

    if (flutterPackages.contains(buildStep.inputId.package)) {
      if (!outputModule.isSupported) {
        outputModule = Module(outputModule.primarySource, outputModule.sources,
            outputModule.directDependencies, outputModule.platform, true,
            isMissing: outputModule.isMissing);
      }
    }

    final modules = await buildStep.fetchResource(moduleCache);
    await modules.write(
        buildStep.inputId.changeExtension(moduleExtension(platform)),
        buildStep,
        outputModule);
  }
}
