// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.js_emitter.program_builder;

import 'js_emitter.dart' show computeMixinClass;
import 'model.dart';

import '../common.dart';
import '../js/js.dart' as js;

import '../js_backend/js_backend.dart' show
    Namer,
    JavaScriptBackend,
    JavaScriptConstantCompiler;

import 'js_emitter.dart' show
    ClassStubGenerator,
    CodeEmitterTask,
    InterceptorStubGenerator,
    TypeTestGenerator,
    TypeTestProperties;

import '../universe/universe.dart' show Universe;
import '../deferred_load.dart' show DeferredLoadTask, OutputUnit;

part 'registry.dart';

class ProgramBuilder {
  final Compiler _compiler;
  final Namer namer;
  final CodeEmitterTask _task;

  final Registry _registry;

  /// True if the program should store function types in the metadata.
  bool _storeFunctionTypesInMetadata = false;

  ProgramBuilder(Compiler compiler,
                 this.namer,
                 this._task)
      : this._compiler = compiler,
        this._registry = new Registry(compiler);

  JavaScriptBackend get backend => _compiler.backend;
  Universe get universe => _compiler.codegenWorld;

  /// Mapping from [ClassElement] to constructed [Class]. We need this to
  /// update the superclass in the [Class].
  final Map<ClassElement, Class> _classes = <ClassElement, Class>{};

  /// Mapping from [OutputUnit] to constructed [Fragment]. We need this to
  /// generate the deferredLoadingMap (to know which hunks to load).
  final Map<OutputUnit, Fragment> _outputs = <OutputUnit, Fragment>{};

  /// Mapping from [ConstantValue] to constructed [Constant]. We need this to
  /// update field-initializers to point to the ConstantModel.
  final Map<ConstantValue, Constant> _constants = <ConstantValue, Constant>{};

  Program buildProgram({bool storeFunctionTypesInMetadata: false}) {
    this._storeFunctionTypesInMetadata = storeFunctionTypesInMetadata;
    // Note: In rare cases (mostly tests) output units can be empty. This
    // happens when the deferred code is dead-code eliminated but we still need
    // to check that the library has been loaded.
    _compiler.deferredLoadTask.allOutputUnits.forEach(
        _registry.registerOutputUnit);
    _task.outputClassLists.forEach(_registry.registerElements);
    _task.outputStaticLists.forEach(_registry.registerElements);
    _task.outputConstantLists.forEach(_registerConstants);
    _task.outputStaticNonFinalFieldLists.forEach(_registry.registerElements);

    // TODO(kasperl): There's code that implicitly needs access to the special
    // $ holder so we have to register that. Can we track if we have to?
    _registry.registerHolder(r'$');

    MainFragment mainOutput = _buildMainOutput(_registry.mainLibrariesMap);
    Iterable<Fragment> deferredOutputs = _registry.deferredLibrariesMap
        .map((librariesMap) => _buildDeferredOutput(mainOutput, librariesMap));

    List<Fragment> outputs = new List<Fragment>(_registry.librariesMapCount);
    outputs[0] = mainOutput;
    outputs.setAll(1, deferredOutputs);

    List<Class> nativeClasses = _task.nativeClasses
        .map((ClassElement classElement) {
          Class result = _classes[classElement];
          return (result == null) ? _buildClass(classElement) : result;
        })
        .toList();

    // Resolve the superclass references after we've processed all the classes.
    _classes.forEach((ClassElement element, Class c) {
      if (element.superclass != null) {
        c.setSuperclass(_classes[element.superclass]);
        assert(c.superclass != null);
      }
      if (c is MixinApplication) {
        c.setMixinClass(_classes[computeMixinClass(element)]);
        assert(c.mixinClass != null);
      }
    });

    _markEagerClasses();

    return new Program(outputs,
                       nativeClasses,
                       _task.outputContainsConstantList,
                       _buildLoadMap());
  }

  void _markEagerClasses() {
    _markEagerInterceptorClasses();
  }

  /// Builds a map from loadId to outputs-to-load.
  Map<String, List<Fragment>> _buildLoadMap() {
    List<OutputUnit> convertHunks(List<OutputUnit> hunks) {
      return hunks.map((OutputUnit unit) => _outputs[unit])
          .toList(growable: false);
    }

    Map<String, List<Fragment>> loadMap = <String, List<Fragment>>{};
    _compiler.deferredLoadTask.hunksToLoad
        .forEach((String loadId, List<OutputUnit> outputUnits) {
      loadMap[loadId] = outputUnits
          .map((OutputUnit unit) => _outputs[unit])
          .toList(growable: false);
    });
    return loadMap;
  }

  MainFragment _buildMainOutput(LibrariesMap librariesMap) {
    // Construct the main output from the libraries and the registered holders.
    MainFragment result = new MainFragment(
        librariesMap.outputUnit,
        "",  // The empty string is the name for the main output file.
        backend.emitter.staticFunctionAccess(_compiler.mainFunction),
        _buildLibraries(librariesMap),
        _buildStaticNonFinalFields(librariesMap),
        _buildStaticLazilyInitializedFields(librariesMap),
        _buildConstants(librariesMap),
        _registry.holders.toList(growable: false));
    _outputs[librariesMap.outputUnit] = result;
    return result;
  }

  DeferredFragment _buildDeferredOutput(MainFragment mainOutput,
                                      LibrariesMap librariesMap) {
    DeferredFragment result = new DeferredFragment(
        librariesMap.outputUnit,
        backend.deferredPartFileName(librariesMap.name, addExtension: false),
                                     librariesMap.name,
        mainOutput,
        _buildLibraries(librariesMap),
        _buildStaticNonFinalFields(librariesMap),
        _buildStaticLazilyInitializedFields(librariesMap),
        _buildConstants(librariesMap));
    _outputs[librariesMap.outputUnit] = result;
    return result;
  }

  List<Constant> _buildConstants(LibrariesMap librariesMap) {
    List<ConstantValue> constantValues =
        _task.outputConstantLists[librariesMap.outputUnit];
    if (constantValues == null) return const <Constant>[];
    return constantValues.map((ConstantValue value) => _constants[value])
        .toList(growable: false);
  }

  List<StaticField> _buildStaticNonFinalFields(LibrariesMap librariesMap) {
    // TODO(floitsch): handle static non-final fields correctly with deferred
    // libraries.
    if (librariesMap != _registry.mainLibrariesMap) {
      return const <StaticField>[];
    }
    Iterable<VariableElement> staticNonFinalFields =
        backend.constants.getStaticNonFinalFieldsForEmission();
    return Elements.sortedByPosition(staticNonFinalFields)
        .map(_buildStaticField)
        .toList(growable: false);
  }

  StaticField _buildStaticField(Element element) {
    JavaScriptConstantCompiler handler = backend.constants;
    ConstantValue initialValue = handler.getInitialValueFor(element).value;
    js.Expression code = _task.emitter.constantReference(initialValue);
    String name = namer.getNameOfGlobalField(element);
    bool isFinal = false;
    bool isLazy = false;
    return new StaticField(element,
                           name, _registry.registerHolder(r'$'), code,
                           isFinal, isLazy);
  }

  List<StaticField> _buildStaticLazilyInitializedFields(
      LibrariesMap librariesMap) {
    // TODO(floitsch): lazy fields should just be in their respective
    // libraries.
    if (librariesMap != _registry.mainLibrariesMap) {
      return const <StaticField>[];
    }

    JavaScriptConstantCompiler handler = backend.constants;
    List<VariableElement> lazyFields =
        handler.getLazilyInitializedFieldsForEmission();
    return Elements.sortedByPosition(lazyFields)
        .map(_buildLazyField)
        .where((field) => field != null)  // Happens when the field was unused.
        .toList(growable: false);
  }

  StaticField _buildLazyField(Element element) {
    JavaScriptConstantCompiler handler = backend.constants;
    js.Expression code = backend.generatedCode[element];
    // The code is null if we ended up not needing the lazily
    // initialized field after all because of constant folding
    // before code generation.
    if (code == null) return null;

    String name = namer.getNameOfGlobalField(element);
    bool isFinal = element.isFinal;
    bool isLazy = true;
    return new StaticField(element,
                           name, _registry.registerHolder(r'$'), code,
                           isFinal, isLazy);
  }

  List<Library> _buildLibraries(LibrariesMap librariesMap) {
    List<Library> libraries = new List<Library>(librariesMap.length);
    int count = 0;
    librariesMap.forEach((LibraryElement library, List<Element> elements) {
      libraries[count++] = _buildLibrary(library, elements);
    });
    return libraries;
  }

  // Note that a library-element may have multiple [Library]s, if it is split
  // into multiple output units.
  Library _buildLibrary(LibraryElement library, List<Element> elements) {
    String uri = library.canonicalUri.toString();

    List<StaticMethod> statics = elements
        .where((e) => e is FunctionElement)
        .map(_buildStaticMethod)
        .toList();

    if (library == backend.interceptorsLibrary) {
      statics.addAll(_generateGetInterceptorMethods());
      statics.addAll(_generateOneShotInterceptors());
    }

    List<Class> classes = elements
        .where((e) => e is ClassElement)
        .map(_buildClass)
        .toList(growable: false);

    bool visitStatics = true;
    List<Field> staticFieldsForReflection = _buildFields(library, visitStatics);

    return new Library(library, uri, statics, classes,
                       staticFieldsForReflection);
  }

  /// HACK for Try.
  ///
  /// Returns a class that contains the fields of a class.
  Class buildClassWithFieldsForTry(ClassElement element) {
    bool onlyForRti = _task.typeTestRegistry.rtiNeededClasses.contains(element);

    List<Field> instanceFields =
        onlyForRti ? const <Field>[] : _buildFields(element, false);

    String name = namer.getNameOfClass(element);
    String holderName = namer.globalObjectFor(element);
    Holder holder = _registry.registerHolder(holderName);
    bool isInstantiated =
        _compiler.codegenWorld.directlyInstantiatedClasses.contains(element);

    return new Class(
        element, name, holder, [], instanceFields, [], [], [], null,
        isDirectlyInstantiated: isInstantiated,
        onlyForRti: onlyForRti,
        isNative: element.isNative);
  }

  Class _buildClass(ClassElement element) {
    bool onlyForRti = _task.typeTestRegistry.rtiNeededClasses.contains(element);

    List<Method> methods = [];
    List<StubMethod> callStubs = <StubMethod>[];

    void visitMember(ClassElement enclosing, Element member) {
      assert(invariant(element, member.isDeclaration));
      assert(invariant(element, element == enclosing));

      if (Elements.isNonAbstractInstanceMember(member)) {
        js.Expression code = backend.generatedCode[member];
        // TODO(kasperl): Figure out under which conditions code is null.
        if (code != null) methods.add(_buildMethod(member, code));
      }
      if (member.isGetter || member.isField) {
        Set<Selector> selectors =
            _compiler.codegenWorld.invokedNames[member.name];
        if (selectors != null && !selectors.isEmpty) {
          ClassStubGenerator generator =
              new ClassStubGenerator(_compiler, namer, backend);
          Map<String, js.Expression> callStubsForMember =
              generator.generateCallStubsForGetter(member, selectors);
          callStubsForMember.forEach((String name, js.Expression code) {
            callStubs.add(_buildStubMethod(name, code, element: member));
          });
        }
      }
    }

    ClassElement implementation = element.implementation;

    // MixinApplications run through the members of their mixin. Here, we are
    // only interested in direct members.
    if (!onlyForRti && !element.isMixinApplication) {
      implementation.forEachMember(visitMember, includeBackendMembers: true);
    }

    List<Field> instanceFields =
        onlyForRti ? const <Field>[] : _buildFields(element, false);
    List<Field> staticFieldsForReflection =
        onlyForRti ? const <Field>[] : _buildFields(element, true);

    TypeTestGenerator generator =
        new TypeTestGenerator(_compiler, _task, namer);
    TypeTestProperties typeTests =
        generator.generateIsTests(
            element,
            storeFunctionTypeInMetadata: _storeFunctionTypesInMetadata);

    List<StubMethod> isChecks = <StubMethod>[];
    typeTests.properties.forEach((String name, js.Node code) {
      isChecks.add(_buildStubMethod(name, code));
    });

    String name = namer.getNameOfClass(element);
    String holderName = namer.globalObjectFor(element);
    Holder holder = _registry.registerHolder(holderName);
    bool isInstantiated =
        _compiler.codegenWorld.directlyInstantiatedClasses.contains(element);

    Class result;
    if (element.isMixinApplication && !onlyForRti) {
      assert(!element.isNative);
      assert(methods.isEmpty);

      result = new MixinApplication(element,
                                    name, holder,
                                    instanceFields,
                                    staticFieldsForReflection,
                                    callStubs,
                                    isChecks,
                                    typeTests.functionTypeIndex,
                                    isDirectlyInstantiated: isInstantiated,
                                    onlyForRti: onlyForRti);
    } else {
      result = new Class(element,
                         name, holder, methods, instanceFields,
                         staticFieldsForReflection,
                         callStubs,
                         isChecks,
                         typeTests.functionTypeIndex,
                         isDirectlyInstantiated: isInstantiated,
                         onlyForRti: onlyForRti,
                         isNative: element.isNative);
    }
    _classes[element] = result;
    return result;
  }

  Method _buildMethod(FunctionElement element, js.Expression code) {
    String name = namer.getNameOfInstanceMember(element);
    // TODO(floitsch): compute `needsTearOff`.
    return new Method(element, name, code, needsTearOff: false);
  }

  /// Builds a stub method.
  ///
  /// Stub methods may have an element that can be used for code-size
  /// attribution.
  Method _buildStubMethod(String name, js.Expression code,
                          {Element element}) {
    // TODO(floitsch): compute `needsTearOff`.
    return new StubMethod(name, code, needsTearOff: false, element: element);
  }

  // The getInterceptor methods directly access the prototype of classes.
  // We must evaluate these classes eagerly so that the prototype is
  // accessible.
  void _markEagerInterceptorClasses() {
    Map<String, Set<ClassElement>> specializedGetInterceptors =
        backend.specializedGetInterceptors;
    for (Set<ClassElement> classes in specializedGetInterceptors.values) {
      for (ClassElement element in classes) {
        Class cls = _classes[element];
        if (cls != null) cls.isEager = true;
      }
    }
  }

  Iterable<StaticMethod> _generateGetInterceptorMethods() {
    InterceptorStubGenerator stubGenerator =
        new InterceptorStubGenerator(_compiler, namer, backend);

    String holderName = namer.globalObjectFor(backend.interceptorsLibrary);
    Holder holder = _registry.registerHolder(holderName);

    Map<String, Set<ClassElement>> specializedGetInterceptors =
        backend.specializedGetInterceptors;
    List<String> names = specializedGetInterceptors.keys.toList()..sort();
    return names.map((String name) {
      Set<ClassElement> classes = specializedGetInterceptors[name];
      js.Expression code = stubGenerator.generateGetInterceptorMethod(classes);
      // TODO(floitsch): compute `needsTearOff`.
      return new StaticStubMethod(name, holder, code, needsTearOff: false);
    });
  }

  List<Field> _buildFields(Element holder, bool visitStatics) {
    List<Field> fields = <Field>[];
    _task.oldEmitter.classEmitter.visitFields(
        holder, visitStatics, (VariableElement field,
                               String name,
                               String accessorName,
                               bool needsGetter,
                               bool needsSetter,
                               bool needsCheckedSetter) {
      assert(invariant(field, field.isDeclaration));

      int getterFlags = 0;
      if (needsGetter) {
        if (visitStatics || !backend.fieldHasInterceptedGetter(field)) {
          getterFlags = 1;
        } else {
          getterFlags += 2;
          // TODO(sra): 'isInterceptorClass' might not be the correct test
          // for methods forced to use the interceptor convention because
          // the method's class was elsewhere mixed-in to an interceptor.
          if (!backend.isInterceptorClass(holder)) {
            getterFlags += 1;
          }
        }
      }

      int setterFlags = 0;
      if (needsSetter) {
        if (visitStatics || !backend.fieldHasInterceptedSetter(field)) {
          setterFlags = 1;
        } else {
          setterFlags += 2;
          if (!backend.isInterceptorClass(holder)) {
            setterFlags += 1;
          }
        }
      }

      fields.add(new Field(field, name, accessorName,
                           getterFlags, setterFlags,
                           needsCheckedSetter));
    });

    return fields;
  }

  Iterable<StaticMethod> _generateOneShotInterceptors() {
    InterceptorStubGenerator stubGenerator =
        new InterceptorStubGenerator(_compiler, namer, backend);

    String holderName = namer.globalObjectFor(backend.interceptorsLibrary);
    Holder holder = _registry.registerHolder(holderName);

    List<String> names = backend.oneShotInterceptors.keys.toList()..sort();
    return names.map((String name) {
      js.Expression code = stubGenerator.generateOneShotInterceptor(name);
      return new StaticStubMethod(name, holder, code, needsTearOff: false);
    });
  }

  StaticMethod _buildStaticMethod(FunctionElement element) {
    String name = namer.getNameOfMember(element);
    String holder = namer.globalObjectFor(element);
    js.Expression code = backend.generatedCode[element];
    bool needsTearOff =
        universe.staticFunctionsNeedingGetter.contains(element);
    // TODO(floitsch): add tear-off name: namer.getStaticClosureName(element).
    return new StaticMethod(element,
                            name, _registry.registerHolder(holder), code,
                            needsTearOff: needsTearOff);
  }

  void _registerConstants(OutputUnit outputUnit,
                          Iterable<ConstantValue> constantValues) {
    // `constantValues` is null if an outputUnit doesn't contain any constants.
    if (constantValues == null) return;
    for (ConstantValue constantValue in constantValues) {
      _registry.registerConstant(outputUnit, constantValue);
      assert(!_constants.containsKey(constantValue));
      String name = namer.constantName(constantValue);
      String constantObject = namer.globalObjectForConstant(constantValue);
      Holder holder = _registry.registerHolder(constantObject);
      Constant constant = new Constant(name, holder, constantValue);
      _constants[constantValue] = constant;
    }
  }
}
