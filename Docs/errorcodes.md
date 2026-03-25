# Error Codes

This document is the canonical registry for ModelHike's stable error and warning codes.

It covers:
- structured diagnostics emitted during pipeline execution
- thrown parsing/evaluation/model-loading errors
- wrapper error families that preserve nested inner codes when possible

## Rules

- `E...` codes are blocking errors.
- `W...` codes are non-fatal warnings surfaced through diagnostics.
- Once introduced, a code should remain stable.
- Wrapper errors delegate to the nested error's code when the inner error already has one.

## Code Ranges

| Range | Family |
| --- | --- |
| `E101` | Blueprint preflight |
| `E201-E218` | TemplateSoup parsing |
| `E301-E311` | TemplateSoup evaluation |
| `E401-E405` | Generic parsing wrappers |
| `E501-E509` | Generic evaluation wrappers |
| `E601-E617` | Model parsing |
| `E701-E702` | Resource loading |
| `W201-W202` | Runtime warnings |
| `W301-W306` | Model validation warnings |

## Diagnostic Codes

These are emitted through `DebugEvent.diagnostic` and shown in the Problems panel.

| Code | Severity | Meaning | Emitted From |
| --- | --- | --- | --- |
| `E101` | Error | Selected blueprint is missing required `main.ss` entry point. | `Sources/Pipelines/5. Render/GenerateCodePass.swift` |
| `W201` | Warning | Conditional expression resolved to `nil` and is treated as `false`. | `Sources/Workspace/Evaluation/ExpressionEvaluator.swift` |
| `W202` | Warning | Existing variable was cleared because a `set` / `set-str` expression resolved to `nil`. | `Sources/Scripting/SoupyScript/Stmts/SetVar.swift`, `Sources/Scripting/SoupyScript/Stmts/SetStr.swift` |
| `W301` | Warning | Property references a custom type that does not exist in the loaded model. | `Sources/Pipelines/3.5. Validate/ValidateModels.swift` |
| `W303` | Warning | Container module reference could not be resolved. | `Sources/Pipelines/3.5. Validate/ValidateModels.swift` |
| `W304` | Warning | Duplicate normalized type name detected. | `Sources/Pipelines/3.5. Validate/ValidateModels.swift` |
| `W305` | Warning | Duplicate property name detected within one type. | `Sources/Pipelines/3.5. Validate/ValidateModels.swift` |
| `W306` | Warning | Duplicate method name detected within one type. | `Sources/Pipelines/3.5. Validate/ValidateModels.swift` |

Notes:
- `W302` is currently unassigned.
- Blocking thrown errors are also surfaced in the debug console as `error` events with their structured `code`.

## TemplateSoup Parsing Errors

Defined in `Sources/Scripting/_Base_/Parsing/TemplateSoup_ParsingError.swift`.

| Code | Case | Meaning |
| --- | --- | --- |
| `E201` | `invalidFrontMatter` | Front matter could not be parsed. |
| `E202` | `invalidStmt` | Statement line is syntactically invalid. |
| `E203` | `invalidMultiBlockStmt` | Multi-block statement syntax is invalid. |
| `E204` | `invalidTemplateFunctionStmt` | Template function declaration syntax is invalid. |
| `E205` | `modifierNotFound` | Referenced modifier does not exist. |
| `E206` | `modifierInvalidSyntax` | Modifier call syntax is malformed. |
| `E207` | `modifierInvalidArguments` | Modifier arguments are missing or malformed. |
| `E208` | `modifierCalledOnwrongType` | Modifier was applied to an incompatible input type. |
| `E209` | `invalidExpression` | Template expression has invalid syntax. |
| `E210` | `propertiesEmpty` | Property access chain evaluated against an empty property path or payload. |
| `E211` | `invalidPropertyAccess` | Property access syntax or traversal is invalid. |
| `E212` | `variableOrPropertyNotFound` | Variable or object property lookup failed. |
| `E213` | `expressionOperandNotFound` | Expression operand could not be resolved. |
| `E214` | `invalidPropertyInCall` | Function or call-site property usage is invalid. |
| `E215` | `infixOperatorNotFound` | Infix operator is unknown. |
| `E216` | `infixOperatorCalledOnwrongLhsType` | Infix operator received an invalid left-hand side type. |
| `E217` | `infixOperatorCalledOnwrongRhsType` | Infix operator received an invalid right-hand side type. |
| `E218` | `templateFunctionNotFound` | Template function lookup failed. |

## TemplateSoup Evaluation Errors

Defined in `Sources/Workspace/Evaluation/TemplateSoup_EvaluationError.swift`.

| Code | Case | Meaning |
| --- | --- | --- |
| `E301` | `objectNotFound` | Required object was not found in evaluation context. |
| `E302` | `unIdentifiedStmt` | Evaluator encountered a statement it could not identify. |
| `E303` | `errorInExpression` | Expression evaluation failed. |
| `E304` | `invalidFileSystemPath` | Filesystem-oriented statement received a non-string path argument. |
| `E305` | `workingDirectoryNotSet` | File operation required a working directory but none was available. |
| `E306` | `templateDoesNotExist` | Referenced template file could not be found. |
| `E307` | `templateReadingError` | Template file exists but could not be read. |
| `E308` | `scriptFileDoesNotExist` | Referenced script file could not be found. |
| `E309` | `scriptFileReadingError` | Script file exists but could not be read. |
| `E310` | `nonSendablePropertyValue` | A property value was not safe to move across concurrency boundaries. |
| `E311` | `nonSendableValueFound` | Evaluator found a non-sendable value in runtime data. |

## Generic Parsing Wrapper Errors

Defined in `Sources/_Common_/Errors/ParsingError.swift`.

| Code | Case | Meaning |
| --- | --- | --- |
| `E401` | `invalidLine` | Generic invalid-line parsing failure without a more specific nested code. |
| `E402` | `invalidLineWithoutErr` | Parser rejected a line and only a plain message is available. |
| `E403` | `unrecognisedParsingDirective` | Parsing directive name is unknown. |
| `E404` | `invalidParsingDirective` | Parsing directive syntax is invalid. |
| `E405` | `featureNotImplementedYet` | Encountered syntax for a parser feature that is not implemented yet. |

Note:
- `invalidLine` delegates to the inner error code when the wrapped error already participates in the registry.

## Generic Evaluation Wrapper Errors

Defined in `Sources/_Common_/Errors/EvaluationError.swift`.

| Code | Case | Meaning |
| --- | --- | --- |
| `E501` | `invalidLine` | Generic invalid-line evaluation failure without a more specific nested code. |
| `E502` | `invalidInput` | Runtime input is invalid. |
| `E503` | `invalidAppState` | Runtime application state is invalid for the requested operation. |
| `E504` | `failedWriteOperation` | File or output write operation failed. |
| `E505` | `workingDirectoryNotSet` | Wrapper-level working directory failure without a more specific nested code. |
| `E506` | `templateDoesNotExist` | Wrapper-level missing-template failure without a more specific nested code. |
| `E507` | `scriptFileDoesNotExist` | Wrapper-level missing-script failure without a more specific nested code. |
| `E508` | `readingError` | Generic read failure without a more specific nested code. |
| `E509` | `templateRenderingError` | Template rendering failed without a more specific nested code. |

Notes:
- `invalidLine`, `workingDirectoryNotSet`, `templateDoesNotExist`, `scriptFileDoesNotExist`, `readingError`, and `templateRenderingError` delegate to the nested error code when available.

## Model Parsing Errors

Defined in `Sources/Modelling/_Base_/ModelErrors.swift`.

| Code | Case | Meaning |
| --- | --- | --- |
| `E601` | `objectTypeNotFound` | A referenced model type could not be resolved. |
| `E602` | `invalidPropertyInType` | Property declaration is invalid for the owning type. |
| `E603` | `invalidPropertyUsedInApi` | API references an invalid property. |
| `E604` | `invalidMapping` | Mapping expression is invalid. |
| `E605` | `invalidPropertyLine` | Property declaration line is malformed. |
| `E606` | `invalidMethodLine` | Method declaration line is malformed. |
| `E607` | `invalidDerivedProperty` | Derived property declaration is invalid. |
| `E608` | `invalidContainerMemberLine` | Container member declaration is malformed. |
| `E609` | `invalidContainerLine` | Container declaration line is malformed. |
| `E610` | `invalidModuleLine` | Module declaration line is malformed. |
| `E611` | `invalidSubModuleLine` | Submodule declaration line is malformed. |
| `E612` | `invalidDomainObjectLine` | Domain object declaration line is malformed. |
| `E613` | `invalidDtoObjectLine` | DTO declaration line is malformed. |
| `E614` | `invalidUIViewLine` | UI view declaration line is malformed. |
| `E615` | `invalidAnnotationLine` | Annotation line is malformed. |
| `E616` | `invalidAttachedSection` | Attached section syntax is invalid. |
| `E617` | `invalidApiLine` | API declaration line is malformed. |

## Resource Loading Errors

Defined in `Sources/CodeGen/TemplateSoup/_Base_/Blueprints/ResourceBlueprint.swift`.

| Code | Case | Meaning |
| --- | --- | --- |
| `E701` | `ResourceReadingError` | Blueprint resource exists but could not be read. |
| `E702` | `ResourceDoesNotExist` | Blueprint resource could not be found. |

## Implementation Notes

- Stable code lookup lives in `Sources/Debug/ErrorCodes.swift`.
- Errors that conform to `ErrorCodeProviding` expose `errorCode`.
- All `ErrorWithMessage` values also expose:
  - `code`
  - `infoWithCode`
- Pipeline error capture now forwards structured error codes into debug `error` events so the Problems panel can show them consistently.

## Adding New Codes

1. Choose the next free code in the relevant family.
2. Add it directly on the owning error type.
3. If the error is surfaced through the debugger, make sure the code flows through `recordDiagnostic` or `DebugEvent.error`.
4. Update this file in the same change.
