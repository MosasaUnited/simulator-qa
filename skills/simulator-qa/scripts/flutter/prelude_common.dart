// Prepended to every step by step.sh. Flattened to one line: whole-line
// comments like these are dropped, so never put a comment after code.
//
// qa('tag', future) — fire an async call and log its outcome as
// "QA[tag] => <result>" in run.log (the VM cannot await an evaluation).
// It prints to the device log: pass it test data only.
void qa(String tag, Future<Object?> f) {
  f.then(
    (r) => print('QA[$tag] => $r'),
    onError: (Object e) => print('QA[$tag] !! $e'),
  );
}
