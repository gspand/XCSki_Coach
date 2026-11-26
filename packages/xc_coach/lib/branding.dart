/// The name of the product, in one place.
///
/// ## Why a file for four strings
///
/// A name that is typed out at every place it appears will differ at some of
/// them. It happens quietly: a screen written six months later says «Giulia»
/// where the header says «GIULIA», a report header keeps an old claim, and
/// nobody notices because each file is right on its own. For software that a
/// federation puts its own name next to, that is not a cosmetic problem.
///
/// So the wordmark and its expansion live here, and the screens read them.
/// A test in `test/ui/branding_test.dart` holds the rule.
///
/// ## What the name says
///
/// **GIULIA** — *Guided Intelligence for Unified Load, Individualization &
/// Analytics.*
///
/// The expansion is worth reading as a promise the product has to keep:
///
/// - **Guided** — the application leads through a diagnostic, it does not
///   leave a coach alone with a form.
/// - **Intelligence**, not automation. Every threshold names the method that
///   produced it, and an expert may choose a different one. The software
///   proposes; it never decides silently.
/// - **Unified Load** — one load axis whose meaning is known and stored, so
///   that two tests are only ever subtracted when they mean the same thing.
/// - **Individualization** — zones and judgements belong to one athlete, not
///   to a table.
/// - **Analytics** — what the data supports, and nothing beyond it.
///
/// That last word is why the athlete page says «Vergleich im eigenen
/// Datenbestand, keine Norm» instead of inventing a percentile: analytics is
/// a claim about evidence, and a name that claims it has to be honoured in
/// the places where it would be easier not to.
library;

/// The wordmark, as it is set on screen. Upper case is part of it.
const String giuliaWordmark = 'GIULIA';

/// What the letters stand for. Shown wherever the product introduces itself.
const String giuliaExpansion =
    'Guided Intelligence for Unified Load, Individualization & Analytics';

/// Title of the application window and of the task switcher entry.
///
/// The wordmark alone: the expansion belongs on a screen the user is reading,
/// not in a window title that gets truncated to «Guided Intel…».
const String giuliaApplicationTitle = giuliaWordmark;

/// One sentence on what the product does, in the language of its users.
///
/// Deliberately not a slogan. It appears where someone opens the application
/// for the first time and needs to know what they are looking at.
const String giuliaPurposeSentence =
    'GIULIA verwaltet Leistungsdiagnostik, Trainingsbereiche und Entwicklung '
    'von Athletinnen und Athleten.';
