import 'package:analyzer/dart/element/element.dart';
import 'package:api_annotations/api_annotations.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:source_gen/source_gen.dart';
import 'package:path/path.dart' as p;

class RepositoryGenerator extends GeneratorForAnnotation<ApiRepository> {
  final Set<Type> _methodAnnotations = {Get, Post, Put, Delete};

  @override
  generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        'Generator cannot target `${element.displayName}`.',
        todo:
            'Remove the [ApiRepository] annotation from `${element.displayName}',
      );
    }
    final buffer = StringBuffer();

    final className = element.name;
    final basePath = annotation.read('basePath').literalValue as String;
    final repositoryClassName = '${className}Impl';

    buffer.writeln('''
      part of '${element.source.shortName}';

      @LazySingleton(as: $className)
      class $repositoryClassName implements $className {
        final ApiClient apiClient;

        ${_generateConstructor(repositoryClassName)}
    ''');

    buffer.writeAll(_parseMethods(element.methods, basePath));
    buffer.writeln('}');
    return buffer.toString();
  }

  _generateConstructor(String repositoryClassName) {
    return '$repositoryClassName(this.apiClient);';
  }

  ConstantReader? _getMethodAnnotation(MethodElement methodElement) {
    for (final Type type in _methodAnnotations) {
      final annotation = TypeChecker.fromRuntime(type).firstAnnotationOfExact(
        methodElement,
        throwOnUnresolved: false,
      );
      if (annotation != null) {
        return ConstantReader(annotation);
      }
    }

    return null;
  }

  bool _hasAnnotation(MethodElement methodElement, Type type) =>
      TypeChecker.fromRuntime(type).hasAnnotationOfExact(methodElement);

  String _getUrlPath(ConstantReader? methodAnnotation, String basePath) {
    final methodPath = methodAnnotation!.read('path').literalValue as String;
    return p.join(basePath, methodPath);
  }

  String _getApiResponseConverter(
      ConstantReader? methodAnnotation, String methodInnerReturnType) {
    final isDataPageResponse =
        methodAnnotation!.read('isDataPageResponse').literalValue as bool;
    final isListResponse =
        methodAnnotation.read('isListResponse').literalValue as bool;

    if (isDataPageResponse) {
      return '$methodInnerReturnType.dataPageFromJson(response.data)';
    } else if (isListResponse) {
      return '$methodInnerReturnType.listFromJson(response.data)';
    } else {
      return '$methodInnerReturnType.fromJson(response.data)';
    }
  }

  String _generateMethodArguments(List<ParameterElement> parameters) {
    final argumentList = parameters.map((param) {
      final paramName = param.name;
      final paramType = param.type.getDisplayString(withNullability: false);
      return '$paramType $paramName';
    }).join(', ');

    return argumentList;
  }

  Iterable<StringBuffer?> _parseMethods(
      List<MethodElement> methodElements, String basePath) {
    return methodElements
        .where((method) =>
            _getMethodAnnotation(method) != null && method.isAbstract)
        .map((method) => _generateMethod(method, basePath));
  }

  String _getAnnotationArgName(List<ParameterElement> parameters, Type type) {
    for (final param in parameters) {
      final hasAnnotation =
          TypeChecker.fromRuntime(type).hasAnnotationOfExact(param);
      if (hasAnnotation) {
        return ', ${param.name}';
      }
    }

    return '';
  }

  Map<String, String> _getAnnotationArgNames(
      List<ParameterElement> parameters, Type type) {
    Map<String, String> namesAndValues = {};
    for (final param in parameters) {
      final hasAnnotation =
          TypeChecker.fromRuntime(type).hasAnnotationOfExact(param);
      if (hasAnnotation) {
        namesAndValues["'${param.name}'"] = param.name;
      }
    }

    return namesAndValues;
  }

  StringBuffer _generateMethod(MethodElement methodElement, String basePath) {
    final methodName = methodElement.name;
    final returnType = methodElement.returnType;
    final returnTypes =
        methodElement.returnType.toString().replaceAll(">", "").split('<');
    final innerReturnType = returnTypes[returnTypes.length - 1];
    final ConstantReader? methodAnnotation =
        _getMethodAnnotation(methodElement);
    final httpMethod = methodAnnotation!.objectValue.type!
        .getDisplayString(withNullability: false)
        .toLowerCase();
    final endpoint = _getUrlPath(methodAnnotation, basePath);
    final methodArgs = _generateMethodArguments(methodElement.parameters);
    final bodyArgName = _getAnnotationArgName(methodElement.parameters, Body);
    final isMultipart = _hasAnnotation(methodElement, Multipart);
    final urlParams =
        _getAnnotationArgNames(methodElement.parameters, UrlParam);
    final queryParams =
        _getAnnotationArgNames(methodElement.parameters, QueryParam);
    final methodBuffer = StringBuffer();
    methodBuffer.writeln('''
      @override
      $returnType $methodName($methodArgs) async {
        try {
          final response = await apiClient.$httpMethod(
            '$endpoint'$bodyArgName, 
            urlParams: $urlParams, 
            query: $queryParams,
            ${(isMultipart) ? 'isMultipart: $isMultipart,' : ''}
          );
          return Success(
            message: "Successful Operation",
            data: ${_getApiResponseConverter(methodAnnotation, innerReturnType)},
          );
        } on ApiException catch(e) {
          return Future.error(Failure(
            message: e.getResponseMessage(),
            exception: e,
          ));
        }
      }
    ''');
    return methodBuffer;
  }
}
