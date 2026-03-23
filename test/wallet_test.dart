import 'package:kaspa_sdk/kaspa_sdk.dart';
import 'package:test/test.dart';

const _knownMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  // ─── generateMnemonic ───────────────────────────────────────────────────────

  group('KaspaWallet.generateMnemonic', () {
    test('generates 12-word mnemonic by default', () {
      final phrase = KaspaWallet.generateMnemonic();
      expect(phrase.trim().split(' ').length, 12);
    });

    test('generates 24-word mnemonic when wordCount=24', () {
      final phrase = KaspaWallet.generateMnemonic(wordCount: 24);
      expect(phrase.trim().split(' ').length, 24);
    });

    test('generated 12-word mnemonic passes self-validation', () {
      final phrase = KaspaWallet.generateMnemonic();
      final (:valid, :error) = KaspaWallet.validateMnemonic(phrase);
      expect(valid, isTrue, reason: error);
    });

    test('generated 24-word mnemonic passes self-validation', () {
      final phrase = KaspaWallet.generateMnemonic(wordCount: 24);
      final (:valid, :error) = KaspaWallet.validateMnemonic(phrase);
      expect(valid, isTrue, reason: error);
    });

    test('two consecutive calls produce different mnemonics', () {
      final a = KaspaWallet.generateMnemonic();
      final b = KaspaWallet.generateMnemonic();
      expect(a, isNot(equals(b)));
    });

    test('all words are lower-case letters only', () {
      final phrase = KaspaWallet.generateMnemonic();
      final wordRe = RegExp(r'^[a-z]+$');
      for (final word in phrase.split(' ')) {
        expect(wordRe.hasMatch(word), isTrue,
            reason: '"$word" is not lowercase alpha');
      }
    });
  });

  // ─── validateMnemonic ───────────────────────────────────────────────────────

  group('KaspaWallet.validateMnemonic', () {
    test('returns valid=true for known valid 12-word mnemonic', () {
      final (:valid, :error) = KaspaWallet.validateMnemonic(_knownMnemonic);
      expect(valid, isTrue);
      expect(error, isEmpty);
    });

    test('returns valid=true for freshly generated mnemonic', () {
      final phrase = KaspaWallet.generateMnemonic();
      final (:valid, :error) = KaspaWallet.validateMnemonic(phrase);
      expect(valid, isTrue, reason: error);
    });

    test('returns InvalidWordCount for 11-word phrase', () {
      final (:valid, :error) = KaspaWallet.validateMnemonic('word ' * 11);
      expect(valid, isFalse);
      expect(error, contains('InvalidWordCount'));
    });

    test('returns InvalidWordCount for 13-word phrase', () {
      final (:valid, :error) = KaspaWallet.validateMnemonic('word ' * 13);
      expect(valid, isFalse);
      expect(error, contains('InvalidWordCount'));
    });

    test('returns InvalidWordCount for empty string', () {
      final (:valid, :error) = KaspaWallet.validateMnemonic('');
      expect(valid, isFalse);
      expect(error, contains('InvalidWordCount'));
    });

    test('returns InvalidWordCount for single word', () {
      final (:valid, :error) = KaspaWallet.validateMnemonic('abandon');
      expect(valid, isFalse);
      expect(error, contains('InvalidWordCount'));
    });

    test('returns InvalidWord for phrase containing non-BIP39 word', () {
      const phrase =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon INVALID123';
      final (:valid, :error) = KaspaWallet.validateMnemonic(phrase);
      expect(valid, isFalse);
      expect(error, contains('InvalidWord'));
    });

    test('returns error for correct length but wrong checksum', () {
      const phrase =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon zoo';
      final (:valid, :error) = KaspaWallet.validateMnemonic(phrase);
      expect(valid, isFalse);
      expect(
          error, anyOf(contains('InvalidChecksum'), contains('InvalidWord')));
    });

    test('trims leading/trailing whitespace before validating', () {
      final (:valid, error: _) =
          KaspaWallet.validateMnemonic('  $_knownMnemonic  ');
      expect(valid, isTrue);
    });

    test('handles multiple spaces between words', () {
      final elevenWords = 'abandon ' * 11;
      final multiSpaced = elevenWords.replaceAll(' ', '  ');
      final (:valid, :error) = KaspaWallet.validateMnemonic(multiSpaced);
      expect(valid, isFalse);
      expect(error, contains('InvalidWordCount'));
    });
  });

  // ─── KaspaWallet.fromMnemonic ────────────────────────────────────────────────

  group('KaspaWallet.fromMnemonic', () {
    test('creates wallet with kaspa: address', () {
      final wallet = KaspaWallet.fromMnemonic(_knownMnemonic);
      expect(wallet.address, startsWith('kaspa:'));
    });

    test('exposes the mnemonic', () {
      final wallet = KaspaWallet.fromMnemonic(_knownMnemonic);
      expect(wallet.mnemonic, equals(_knownMnemonic));
    });

    test('derivation is deterministic', () {
      final w1 = KaspaWallet.fromMnemonic(_knownMnemonic);
      final w2 = KaspaWallet.fromMnemonic(_knownMnemonic);
      expect(w1.address, equals(w2.address));
    });

    test('different mnemonics yield different addresses', () {
      final m1 = KaspaWallet.generateMnemonic();
      final m2 = KaspaWallet.generateMnemonic();
      final a1 = KaspaWallet.fromMnemonic(m1).address;
      final a2 = KaspaWallet.fromMnemonic(m2).address;
      expect(a1, isNot(equals(a2)));
    });

    test('throws ArgumentError for invalid mnemonic', () {
      expect(
        () => KaspaWallet.fromMnemonic('invalid mnemonic phrase here'),
        throwsArgumentError,
      );
    });

    test('uses hrp parameter for address prefix', () {
      final wallet =
          KaspaWallet.fromMnemonic(_knownMnemonic, hrp: 'kaspatest');
      expect(wallet.address, startsWith('kaspatest:'));
    });
  });

  // ─── KaspaWallet.generate ────────────────────────────────────────────────────

  group('KaspaWallet.generate', () {
    test('creates a wallet with a valid kaspa: address', () {
      final wallet = KaspaWallet.generate();
      expect(wallet.address, startsWith('kaspa:'));
    });

    test('generates a valid 12-word mnemonic by default', () {
      final wallet = KaspaWallet.generate();
      final (:valid, :error) = KaspaWallet.validateMnemonic(wallet.mnemonic);
      expect(valid, isTrue, reason: error);
    });

    test('generates a 24-word mnemonic when requested', () {
      final wallet = KaspaWallet.generate(wordCount: 24);
      expect(wallet.mnemonic.trim().split(' ').length, 24);
    });

    test('two generated wallets have different addresses', () {
      final w1 = KaspaWallet.generate();
      final w2 = KaspaWallet.generate();
      expect(w1.address, isNot(equals(w2.address)));
    });
  });

  // ─── sendTransaction — address validation ───────────────────────────────────

  group('KaspaWallet.sendTransaction — address validation', () {
    test('throws KaspaException immediately for wrong-hrp toAddress', () async {
      final wallet = KaspaWallet.fromMnemonic(_knownMnemonic); // hrp = kaspa
      // toAddress has kaspatest: prefix → wrong hrp
      await expectLater(
        wallet.sendTransaction(
          nodeUrl: 'wss://unreachable.invalid',
          toAddress:
              'kaspatest:qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq',
          amountSompi: 1000000,
        ),
        throwsA(isA<KaspaException>()),
      );
    });
  });
}
