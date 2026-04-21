//
//  ModelFileParser.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor ModelFileParser {
    let modelSpace = ModelSpace()
    var component = C4Component()
    var subComponent : C4Component?
    var currentSystem: C4System?
    var lineParser : LineParserDuringLoad
    let ctx: LoadContext
    
    public func parse(file: LocalFile) async throws -> ModelSpace {
        let lines = try file.readTextLines(ignoreEmptyLines: false)
        return try await self.parse(lines: lines, identifier: file.name)
    }
    
    public func parse(string: String, identifier: String) async throws -> ModelSpace {
        let lines = string.splitIntoLines()
        return try await self.parse(lines: lines, identifier: identifier)
    }
    
    public func parse(lines contents: [String], identifier: String) async throws -> ModelSpace {
        let lineParser = LineParserDuringLoad(lines: contents, identifier: identifier, isStatementsPrefixedWithKeyword: true, with: ctx, autoIncrementLineNoForEveryLoop: false)
        self.lineParser = lineParser

        do {
            var pendingMetadataBlock = ParserUtil.PendingMetadataBlock()

            try await lineParser.parse(level: 0) {[weak self] pctx, _ in
                guard let self else { return }
                
                if await lineParser.isCurrentLineEmptyOrCommented() { await lineParser.skipLine(); return }

                guard let pInfo = await lineParser.currentParsedInfo(level : pctx.level) else { await lineParser.skipLine(); return }

                if await ParserUtil.consumePendingMetadataBlockLines(from: lineParser, into: &pendingMetadataBlock) {
                    return
                }

                let trimmed = await lineParser.currentLine()
                if trimmed.hasPrefix(ModelConstants.Member_Description), !trimmed.hasOnly("-") {
                    _ = await ParserUtil.consumeDescriptionLines(from: lineParser)
                    return
                }

                if await SystemParser.canParse(parser: lineParser) {
                    let meta = ParserUtil.PendingMetadata.from(pendingMetadataBlock)
                    pendingMetadataBlock.clear()
                    try await self.parseSystem(pInfo: pInfo, parser: lineParser, pending: meta)
                    return
                }

                if await ContainerParser.canParse(parser: lineParser) {
                    let meta = ParserUtil.PendingMetadata.from(pendingMetadataBlock)
                    pendingMetadataBlock.clear()
                    try await self.parseContainer(firstWord: pInfo.firstWord, pInfo: pInfo, parser: lineParser, pending: meta)
                    return
                }
                
                if await ModuleParser.canParse(parser: lineParser) {
                    let meta = ParserUtil.PendingMetadata.from(pendingMetadataBlock)
                    pendingMetadataBlock.clear()
                    try await parseModule(firstWord: pInfo.firstWord, pInfo: pInfo, parser: lineParser, pending: meta)
                    return
                }
                
                if await SubModuleParser.canParse(parser: lineParser) {
                    let meta = ParserUtil.PendingMetadata.from(pendingMetadataBlock)
                    pendingMetadataBlock.clear()
                    try await parseSubModule(firstWord: pInfo.firstWord, pInfo: pInfo, parser: lineParser, pending: meta)
                    return
                }

                if pInfo.firstWord == ModelConstants.Member_Calculated {
                    if ParserUtil.isNamedConstraintEqualsLine(line: pInfo.line, firstWord: pInfo.firstWord) {
                        if let c = try await ParserUtil.parseNamedConstraint(from: pInfo, parser: lineParser) {
                            await self.component.namedConstraints.add(c)
                            pendingMetadataBlock.clear()
                            return
                        }
                    } else if let prop = try await Property.parse(pInfo: pInfo) {
                        await self.component.append(expression: prop)
                        await ParserUtil.appendConsumedDescriptionLines(from: lineParser, to: prop)
                        pendingMetadataBlock.clear()
                        return
                    }
                }

                if await MethodObject.canParse(parser: lineParser) {
                    let passPending = pendingMetadataBlock.isEmpty ? nil : pendingMetadataBlock
                    pendingMetadataBlock.clear()
                    guard let methodPInfo = await lineParser.currentParsedInfo(level: 0) else {
                        await lineParser.skipLine()
                        return
                    }
                    if let method = try await MethodObject.parse(pInfo: methodPInfo, pendingMetadataBlock: passPending) {
                        await ParserUtil.appendConsumedDescriptionLines(from: lineParser, to: method)
                        await self.component.append(function: method)
                        return
                    }
                }
                
                //check for class starting
                if await DomainObjectParser.canParse(parser: lineParser) {
                    let meta = ParserUtil.PendingMetadata.from(pendingMetadataBlock)
                    pendingMetadataBlock.clear()
                    if let item = try await DomainObjectParser.parse(parser: lineParser, with: pInfo, pending: meta) {
                        await appendToComponent(item)
                        return
                    } else {
                        throw Model_ParsingError.invalidDomainObjectLine(pInfo)
                    }
                }
                
                if await DtoObjectParser.canParse(parser: lineParser) {
                    let meta = ParserUtil.PendingMetadata.from(pendingMetadataBlock)
                    pendingMetadataBlock.clear()
                    if let item = try await DtoObjectParser.parse(parser: lineParser, with: pInfo, pending: meta) {
                        await appendToComponent(item)
                        return
                    } else {
                        throw Model_ParsingError.invalidDtoObjectLine(pInfo)
                    }
                }
                
                if await UIViewParser.canParse(parser: lineParser) {
                    let meta = ParserUtil.PendingMetadata.from(pendingMetadataBlock)
                    pendingMetadataBlock.clear()
                    if let item = try await UIViewParser.parse(parser: lineParser, with: ctx, pending: meta) {
                        await appendToComponent(item)
                        return
                    } else {
                        throw Model_ParsingError.invalidUIViewLine(pInfo)
                    }
                }
                
                if let subComponent = await self.subComponent { //sub module active
                    if try await pInfo.tryParseAttachedSections(with: subComponent) {
                        pendingMetadataBlock.clear()
                        return
                    }
                    if try await pInfo.tryParseAnnotations(with: subComponent) {
                        pendingMetadataBlock.clear()
                        return
                    }
                } else {
                    if try await pInfo.tryParseAttachedSections(with: self.component) {
                        pendingMetadataBlock.clear()
                        return
                    }
                    if try await pInfo.tryParseAnnotations(with: self.component) {
                        pendingMetadataBlock.clear()
                        return
                    }
                }

                pendingMetadataBlock.clear()
                await lineParser.skipLine();
            }
            
            return modelSpace
        } catch let err {
            if let parseErr = err as? Model_ParsingError {
                throw ParsingError.invalidLine(parseErr.pInfo, parseErr)
            } else {
                throw err
            }
        }
    }
    
    func parseModule(firstWord: String, pInfo: ParsedInfo, parser: LineParser, pending: ParserUtil.PendingMetadata? = nil) async throws {
        if let module = try await ModuleParser.parse(parser: lineParser, with: ctx, pending: pending) {
            self.component = module
            self.subComponent = nil
            await self.modelSpace.append(module: module)
        } else {
            throw Model_ParsingError.invalidModuleLine(pInfo)
        }
    }
    
    func parseSubModule(firstWord: String, pInfo: ParsedInfo, parser: LineParser, pending: ParserUtil.PendingMetadata? = nil) async throws {
        if let submodule = try await SubModuleParser.parse(parser: lineParser, with: ctx, pending: pending) {
            self.subComponent = submodule
            await self.component.append(submodule: submodule)
        } else {
            throw Model_ParsingError.invalidSubModuleLine(pInfo)
        }
    }
    
    func parseSystem(pInfo: ParsedInfo, parser: LineParser, pending: ParserUtil.PendingMetadata? = nil) async throws {
        if let system = try await SystemParser.parse(parser: lineParser, with: ctx, pending: pending) {
            self.currentSystem = system
            await self.modelSpace.append(system: system)
        } else {
            throw Model_ParsingError.invalidSystemLine(pInfo)
        }
    }

    func parseContainer(firstWord: String, pInfo: ParsedInfo, parser: LineParser, pending: ParserUtil.PendingMetadata? = nil) async throws {
        if let container = try await ContainerParser.parse(parser: lineParser, with: ctx, pending: pending) {
            await self.modelSpace.append(container: container)
        } else {
            throw Model_ParsingError.invalidContainerLine(pInfo)
        }
    }
    
    fileprivate func appendToComponent(_ item: CodeObject) async {
        //if sub-component is actively being parsed, then add the object to it
        if let subComponent = self.subComponent {
            await subComponent.append(item)
        } else {
            await self.component.append(item)
        }
    }
    
    
    fileprivate func appendToComponent(_ item: UIObject) async {
        //if sub-component is actively being parsed, then add the object to it
        if let subComponent = self.subComponent {
            await subComponent.append(item)
        } else {
            await self.component.append(item)
        }
    }
    
    public init(with context: LoadContext) {
        lineParser = LineParserDuringLoad(identifier: "", isStatementsPrefixedWithKeyword: true, with: context)
        self.ctx = context
    }
}
