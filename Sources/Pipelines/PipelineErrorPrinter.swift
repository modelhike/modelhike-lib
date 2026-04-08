//
//  PipelineErrorPrinter.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

public struct PipelineErrorPrinter {
    func printError(_ err: Error, context: Context) async {
        let stack = await context.debugLog.stack.snapshot()
        let includeMemoryVariablesDump = await context.config.errorOutput.includeMemoryVariablesDump
        let debugLog = await context.debugLog
        
        let callStackInfo = StringTemplate {
            "[Call Stack]"
            
            for log in stack {
                String.newLine
                log.callStackItem.renderForDisplay()
            }
        }
        
        let memoryVarsInfo = await StringTemplate {
            "[Memory]"
            
            await dumpMemory(context: context)
        }
        
        
        let debugInfo = await StringTemplate {
            "[Extra Debug Info]"
            String.newLine
            
            await context.debugInfo.title
            
            for (k, v) in await context.debugInfo.debugInfo {
                String.newLine
                
                if let sendable = v as? SendableDebugStringConvertible {
                    "- \(k): \(await sendable.debugDescription)"
                } else if let sendable = v as? SendableStringConvertible {
                    "- \(k): \(await sendable.description)"
                } else {
                    "- \(k): \(v)"
                }
            }
            
            String.newLine
        }
        
        let extraInfo = await StringTemplate {
            if await context.debugInfo.hasAny {
                debugInfo
                String.newLine
            }
            
            callStackInfo
            
            if includeMemoryVariablesDump {
                String.newLine
                String.newLine
                memoryVarsInfo
            }
        }.toString()
        
        
        if let parseErr = err as? ParsingError {
            let pInfo = parseErr.pInfo
            let msg = """
                      🐞🐞 ERROR WHILE PARSING 🐞🐞
                       \(pInfo.identifier) [\(pInfo.lineNo)] \(parseErr.infoWithCode)
                      
                      \(extraInfo)
                      
                      """
            debugLog.pipelineError(msg)
            //print(Thread.callStackSymbols)
        } else if let parseErr = err as? Model_ParsingError {
            let pInfo = parseErr.pInfo
            let msg = """
                      🐞🐞 ERROR WHILE PARSING MODELS 🐞🐞
                       \(pInfo.identifier) [\(pInfo.lineNo)] \(parseErr.infoWithCode)
                      
                      \(extraInfo)
                      
                      """
            debugLog.pipelineError(msg)
            //print(Thread.callStackSymbols)
        } else if let evalErr = err as? EvaluationError {
            let pInfo = evalErr.pInfo
            
            var info = ""
            if case let .invalidAppState(string, _) = evalErr {
                info = ErrorCodes.format(message: string, code: evalErr.code)
            } else if case let .invalidInput(string, _) = evalErr {
                info = ErrorCodes.format(message: string, code: evalErr.code)
            } else {
                info = evalErr.infoWithCode
            }
            let msg = """
                  🐞🐞 ERROR DURING EVAL 🐞🐞
                   \(pInfo.identifier) [\(pInfo.lineNo)] \(info)
                  
                  \(extraInfo)
                  
                  """
            debugLog.pipelineError(msg)
            //print(Thread.callStackSymbols)
        } else if let tsParseErr = err as? TemplateSoup_ParsingError {
            let pInfo = tsParseErr.pInfo
            let msg = """
                  🐞🐞 TEMPLATE SYNTAX ERROR 🐞🐞
                   \(pInfo.identifier) [\(pInfo.lineNo)] \(tsParseErr.infoWithCode)
                  
                  \(extraInfo)
                  
                  """
            debugLog.pipelineError(msg)
        } else if let tsEvalErr = err as? TemplateSoup_EvaluationError {
            let pInfo = tsEvalErr.pInfo
            let msg = """
                  🐞🐞 TEMPLATE EVALUATION ERROR 🐞🐞
                   \(pInfo.identifier) [\(pInfo.lineNo)] \(tsEvalErr.infoWithCode)
                  
                  \(extraInfo)
                  
                  """
            debugLog.pipelineError(msg)
        } else if let err = err as? ErrorWithMessageAndParsedInfo {
            let msg = """
                  🐞🐞 UNHANDLED ERROR (\(type(of: err))) 🐞🐞
                   \(err.infoWithCode)
                  
                  \(extraInfo)
                  
                  """
            debugLog.pipelineError(msg)
            //print(Thread.callStackSymbols)
        } else {
            debugLog.pipelineError("❌❌ UNKNOWN INTERNAL ERROR (\(type(of: err))) ❌❌")
            debugLog.pipelineError(err)
        }
        
    }
    
    fileprivate func dumpMemory(context: Context) async -> String{
        let variables = await context.variables.snapshot()
        
        return await StringTemplate {
            for va in variables {
                String.newLine
                let value = va.value
                
                if let sendable = value as? SendableDebugStringConvertible {
                    "\(va.key) = \(await sendable.debugDescription)"
                } else if let sendable = value as? SendableStringConvertible {
                    "\(va.key) = \(await sendable.description)"
                } else if let arr = value as? [Sendable] {
                    "\(va.key) =" + .newLine
                    for item in arr {
                        "| \(item)"
                    }
                } else if let unwrappedValue = deepUnwrap(value) {  // Cast to Optional<Any>
                    "\(va.key) = \(unwrappedValue)"
                } else {
                    "\(va.key) = null"
                }
            }
        }.toString()
    }
}
