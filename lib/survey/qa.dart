/// Status kualitas titik berdasarkan akurasi yang dilaporkan HP dan sebaran sampel.
enum QaStatus { baik, cukup, buruk }

QaStatus assessPoint({
  required double meanAccuracy,
  required double stdH,
  required int nUsed,
}) {
  if (nUsed < 10 || meanAccuracy > 15 || stdH > 8) return QaStatus.buruk;
  if (meanAccuracy > 5 || stdH > 3) return QaStatus.cukup;
  return QaStatus.baik;
}
