//
//  HydrateModels.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

public struct HydrateModelsPass: LoadingPass {
    
    public func runIn(_ ws: Workspace, phase: LoadPhase) async throws -> Bool {
        try await processAfterLoad(model: ws.model, with: ws.context)
        
        return true
    }
    
    func processAfterLoad(model: AppModel, with ctx: LoadContext) async throws {
        //set specific port for each mobile
        var portNumber = 3000
        if await ctx.variables.has(ModelConfigConstants.API_StartingPort) {
            if let value = await ctx.variables[ModelConfigConstants.API_StartingPort] as? String {
                portNumber = Int(value) ?? portNumber
            }
        }
        
        let components = await model.containers.allComponents
        let portMap = components.enumerated().map { (index, component) in
            (component, portNumber + index + 1)
        }
        
        for (component, port) in portMap {
            await component.attribs.set("port", value: "\(port)")
        }
        
        //set dataType for each parsed type
        try await model.commonModel.forEachType {  e, _ in await e.dataType(.valueType) }
        
        try await model.containers.forEachType {  e, component in
            
            if let cls = e as? DomainObject {
                if await cls.givenname.hasSuffix("Cache"){
                    await e.dataType(.cache)
                } else if await cls.givenname.hasSuffix("Input"){
                    await e.dataType(.apiInput_forGraphQL)
                } else if await hasIdProp(cls) {
                    await e.dataType(.entity)
                } else if await isService(cls) {
                    await e.dataType(.service)
                } else {
                    await e.dataType(.embeddedType)
                }
                return
            }
            
            if let cls = e as? DtoObject {
                if await cls.givenname.hasSuffix("Input"){
                    await e.dataType(.apiInput_forGraphQL)
                } else {
                    await e.dataType(.dto)
                }
            }
        }
    }
    
    private func hasIdProp(_ cls: DomainObject) async -> Bool {
        let hasIdProp: Bool = await cls.hasProp("_id")
        let hasIdProp2: Bool = await cls.hasProp("id")
        
        return hasIdProp || hasIdProp2
    }

    /// A domain object with no properties but at least one method is a service.
    private func isService(_ cls: DomainObject) async -> Bool {
        guard await !cls.hasProperties() else { return false }
        return await cls.hasMethods()
    }

    public init() {}

}
