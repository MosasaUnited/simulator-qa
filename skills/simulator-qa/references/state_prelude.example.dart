// A project's state prelude: copy this into YOUR project (for example
// tool/qa_prelude.dart), rewrite the two helpers for your own state object, and
// point QA_FLUTTER_PRELUDE at the copy in .simulator-qa.env.
//
// It is evaluated ON the object QA_FLUTTER_STATE names, so that object's
// fields — private ones included — are in scope by their bare names, exactly
// as inside one of its methods. The names below (_items, _status, _repository)
// are placeholders for a made-up cart screen; none of them exist in your app.
//
// The file is flattened to one line before it runs. Whole-line comments like
// these are dropped; a comment AFTER code would swallow the rest of the file.
//
// dump() — everything the screen is built from, on one line. step.sh prints it
// after every step, so a scenario can be checked without reading pixels.
String dump() {
  return 'items=${_items.length} total=$_total status=${_status.name} '
      'error=${_error ?? 'none'} loading=$_isLoading';
}
// seed(...) — puts the app in a state that is slow or impossible to reach by
// hand on an emulator (a full cart, an expired session, the 500th list row).
// Go through the same methods the UI would call, so the screen and anything
// derived from the state stay consistent.
Future<String> seed(int count) async {
  await _repository.clear();
  for (var i = 0; i < count; i++) {
    await _repository.add('test-item-$i');
  }
  _items = await _repository.all();
  setState(() {});
  return 'seeded ${_items.length}';
}
