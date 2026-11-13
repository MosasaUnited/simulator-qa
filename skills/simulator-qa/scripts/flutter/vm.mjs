// Evaluates Dart inside the running debug app, over the VM service.
//
//   node vm.mjs [--on <Type>[.<field>]] [--lib <package-uri>] [--prelude <file>]... (-e '<body>' | <body-file>)
//
// The body (plus any preludes) is wrapped as `(() { … })()` and flattened to ONE
// line. So the body must `return` a value, and must not contain `//` comments
// after code.
//
// --on    Evaluates the body ON a live object, so `this` is that object and its
//         private members and its library's imports are in scope. <Type> is the
//         class of a widget or of a State in the tree, found by name; with
//         .<field> the target is that member of it instead — `--on HomePage.controller`,
//         `--on _CartScreenState._bloc`. Defaults to QA_FLUTTER_STATE.
// --lib   Evaluates in that library's top-level scope instead (default: the
//         app's main.dart, see QA_FLUTTER_ROOT_LIB).
import { readFileSync } from 'node:fs';
import { flat, rootLibrary, setting, withVm } from './vmclient.mjs';

const args = process.argv.slice(2);
let on = setting('QA_FLUTTER_STATE') ?? null;
let lib = null;
const preludes = [];
let body = null;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--on') on = args[++i];
  else if (a === '--lib') {
    lib = args[++i];
    on = null;
  } else if (a === '--prelude') preludes.push(readFileSync(args[++i], 'utf8'));
  else if (a === '-e') body = args[++i];
  else body = readFileSync(a, 'utf8');
}
if (body === null) {
  console.error("usage: node vm.mjs [--on Type[.field]] [--lib uri] [--prelude f]... (-e 'body' | file)");
  process.exit(2);
}
if (on && !/^[A-Za-z_$][\w$]*(\.[A-Za-z_$][\w$]*)?$/.test(on)) {
  console.error(`--on takes a class name, optionally with one field: Type or Type.field (got "${on}")`);
  process.exit(2);
}

// Flatten each piece BEFORE wrapping: glued onto "(() {", a leading comment
// line would no longer start with // and would swallow the whole expression.
const expression = `(() { ${[...preludes, body].map(flat).join(' ')} })()`;

// The first widget, or State, in the tree whose class has that name.
const finder = (type) =>
  flat(`(() {
  Object? found;
  bool named(Object o) {
    final t = o.runtimeType.toString();
    return t == '${type}' || t.startsWith('${type}<');
  }
  void visit(Element e) {
    if (found != null) return;
    if (named(e.widget)) {
      found = e.widget;
      return;
    }
    if (e is StatefulElement && named(e.state)) {
      found = e.state;
      return;
    }
    e.visitChildren(visit);
  }
  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  return found;
})()`);

withVm(async ({ call, isolateId, libId, evaluate }) => {
  let targetId = libId(lib ?? rootLibrary());
  if (on) {
    const [type, field] = on.split('.');
    let ref = await evaluate(targetId, finder(type));
    if (ref.kind === 'Null' || !ref.id) {
      console.log(`FAILED: no ${type} widget or State in the tree — is that screen showing?`);
      return;
    }
    if (field) {
      // Read ON the object, so a private field resolves in its own library.
      ref = await evaluate(ref.id, field);
      if (ref.type === '@Error' || ref.kind === 'Null' || !ref.id) {
        console.log(`FAILED: ${type}.${field} is ${ref.kind === 'Null' ? 'null' : 'not readable: ' + ref.message}`);
        return;
      }
    }
    targetId = ref.id;
  }

  const r = await evaluate(targetId, expression);
  if (r.type === '@Error' || r.type === 'Error') {
    // The message carries a stack trace; the first lines say what went wrong.
    console.log('ERROR: ' + String(r.message).split('\n#0')[0].split('\n').slice(0, 6).join('\n'));
  } else if (r.kind === 'String') {
    const full = r.valueAsStringIsTruncated
      ? (await call('getObject', { isolateId, objectId: r.id, count: 1000000 })).valueAsString
      : r.valueAsString;
    console.log(full);
  } else if (r.valueAsString !== undefined) {
    console.log(`${r.kind}: ${r.valueAsString}`);
  } else {
    const s = await evaluate(r.id, 'toString()');
    console.log(`${r.class?.name}: ${s.valueAsString}`);
  }
});
