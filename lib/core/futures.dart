/// Both answers, asked at once. The first failure is thrown as it is, unlike the record
/// `.wait`, which wraps it in a `ParallelWaitError`.
Future<(A, B)> both<A, B>(Future<A> a, Future<B> b) async {
  final results = await Future.wait<Object?>([a, b]);
  return (results[0] as A, results[1] as B);
}
