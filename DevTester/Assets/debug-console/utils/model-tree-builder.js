export function moduleToNode(module) {
  return {
    kind: 'folder',
    label: module.givenname || module.name || '?',
    meta: ((module.objects || []).length) + ' objects',
    badge: 'module',
    children: [
      ...(module.submodules || []).map(moduleToNode),
      ...(module.objects || []).map(objectToNode)
    ]
  };
}

export function objectToNode(object) {
  return {
    kind: 'folder',
    label: object.givenname || object.name || '?',
    meta: ((object.properties || []).length) + ' props · ' + ((object.methods || []).length) + ' methods',
    badge: object.kind || 'object',
    children: [
      ...(object.properties || []).map(prop => ({
        kind: 'property',
        label: prop.givenname || prop.name || '?',
        meta: (prop.typeName || '?') + ' ' + (prop.required || ''),
        badge: 'prop',
        children: []
      })),
      ...(object.methods || []).map(method => ({
        kind: 'method',
        label: method.givenname || method.name || '?',
        meta: 'returns ' + (method.returnType || 'Void'),
        badge: 'method',
        children: []
      }))
    ]
  };
}
