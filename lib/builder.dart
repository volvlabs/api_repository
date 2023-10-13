import 'package:apirepository/src/generator.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder repositoryModelBuilder(BuilderOptions options) => LibraryBuilder(
      RepositoryGenerator(),
      generatedExtension: '.repository.g.dart',
      options: options,
    );
