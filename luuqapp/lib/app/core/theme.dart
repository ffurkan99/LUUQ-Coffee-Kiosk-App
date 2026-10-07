part of '../../main.dart';

const _bgDark = Color(0xFF16131D); // Deep dark warm navy/brown
const _surface = Color(0xFF231E2D);
const _gold = Color(0xFFF9AB3E);
const _caramel = Color(
  0xFFD88E2B,
); // Complementary darker shade of the new gold
const _mint = Color(0xFF48C9B0);
const _cream = Color(0xFFFFF7EC);
const _muted = Color(0xFF8A8694);

/// Soluk METİN rengi — _muted'ın okunabilir tonu (koyu zeminlerde ~6:1
/// kontrast). Kural: metin renginde _muted kullanılmaz; _muted yalnız
/// ikon/çizgi soldurma içindir.
const _mutedText = Color(0xFFA29DB0);

/// Kiosk tip ölçeği tabanları: rozet/etiket 12, ikincil metin (caption) 14.
/// Kural: gövde metni 14'ün, rozet 12'nin altına inemez.
const double _fsBadge = 12;
const double _fsCaption = 14;
