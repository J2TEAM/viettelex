// EnglishContextWords.swift — curated set of common English words used ONLY by the
// experimental context-based decision (engine.contextualEnglish). This is SEPARATE
// from EnglishCollisions (which force-restores Telex-colliding words regardless of
// context): this set answers "was the previous word English?" and "is this ambiguous
// word a plausible English word?" so that after an English word, an ambiguous next
// word (composed is valid Vietnamese but the raw keys spell an English word) is
// restored to English — "he is" → "he is" (not "he í"), while "sao í" stays Vietnamese.
//
// Deliberately weighted toward function words (pronouns, auxiliaries, articles,
// prepositions, conjunctions) plus the highest-frequency content words — enough to
// carry English context through a sentence. Curated by hand (not gen-english): most of
// these do NOT collide with Telex, so they never appear in EnglishCollisions, yet they
// are exactly the words that establish an English run. Lowercase, ascii.
enum EnglishContextWords {
    static let words: Set<String> = [
        // pronouns
        "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them",
        "my", "your", "his", "its", "our", "their",
        "mine", "yours", "hers", "ours", "theirs",
        "this", "that", "these", "those",
        "who", "whom", "whose", "which", "what",
        "myself", "yourself", "himself", "herself", "itself", "ourselves", "themselves",
        // be / auxiliaries / common verbs
        "is", "am", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "done", "doing",
        "have", "has", "had", "having",
        "will", "would", "shall", "should",
        "can", "could", "may", "might", "must",
        "get", "gets", "got", "go", "goes", "going",
        "make", "makes", "made", "take", "takes", "took",
        "see", "saw", "seen", "know", "knew", "want", "wants",
        "need", "needs", "like", "likes", "use", "uses", "used",
        "say", "says", "said", "come", "comes", "came",
        "think", "thinks", "look", "looks", "find", "found",
        "give", "gives", "tell", "work", "works", "call", "calls",
        // articles / determiners / quantifiers
        "a", "an", "the", "some", "any", "every", "each",
        "all", "both", "half", "few", "many", "much", "more", "most",
        "several", "enough", "such", "other", "another", "same",
        // prepositions
        "of", "to", "in", "on", "at", "by", "for", "with", "from",
        "into", "onto", "up", "out", "off", "over", "under", "about",
        "after", "before", "between", "through", "during", "without",
        "within", "along", "across", "behind", "beyond", "upon",
        // conjunctions
        "and", "or", "but", "nor", "so", "yet", "if", "then", "than",
        "because", "while", "when", "where", "why", "how", "though",
        "although", "unless", "until", "whether", "since", "as",
        // common adverbs / adjectives / misc.
        // NOTE: interjections / greetings / politeness markers (ok, okay, hi, hello, hey,
        // yes, no, sorry, thanks, thank, please, well, really, maybe) are DELIBERATELY
        // NOT here — Vietnamese speakers open sentences with them ("ok cám ơn", "hi mọi
        // người", "sorry nha"), so seeding an English run from them flips the next
        // Vietnamese word ("ok cám ơn" → "ok cams ơn"). Left out, they fall through to
        // neutral/Vietnamese and never open an English run.
        "not", "here", "there", "now", "just", "only", "also", "too", "very",
        "back", "down", "new", "old", "good", "great", "big",
        "small", "little", "long", "high", "low", "right", "left",
        "next", "last", "first", "one", "two", "three",
        "again", "always", "never", "often", "still", "even", "much",
        "day", "time", "way", "man", "men", "people", "thing", "things",
        // Hand-vetted ambiguous English words: each ALSO composes to a Vietnamese
        // syllable (runs→rún, songs→sóng, bans→bán, moms→móm, thus→thú), so they are
        // ONLY flipped to English inside an English run — after a Vietnamese/no-context
        // word they correctly stay Vietnamese. NOT bulk-imported: most collision words
        // hit COMMON Vietnamese (cos→có, sex→sẽ, max→mã) and would corrupt mixed text.
        "runs", "loans", "songs", "sons", "moms", "cams", "lens", "rays", "vans",
        "bans", "tins", "tans", "dams", "hams", "thus",
        // Broad expansion (user opt-in): the `degrades_vn` rows from telex_test_suite —
        // English words whose Telex reading is a valid (mostly less-common) Vietnamese
        // syllable. Recognized as ambiguous so context can flip them after an English
        // word; alone they stay Vietnamese. The `never` rows (cos→có, sex→sẽ, max→mã,
        // this→thí…) are DELIBERATELY excluded — they collide with COMMON Vietnamese.
        "air", "ais", "ams", "ans", "arm", "asn", "asp", "bangs", "barn",
        "beer", "beest", "bens", "best", "bins", "bits", "bons", "boost", "boots", "born",
        "burn", "cans", "caps", "cast", "cats", "chair", "chans", "chaos", "charm",
        "chens", "chest", "chips", "choes", "choir", "chose", "conf", "cons", "corn", "cost",
        "cums", "cups", "cuts", "dans", "days", "deer", "deest", "dims", "dist",
        "docs", "doms", "dons", "dust", "ems", "ens", "eos", "est", "gaps", "gary",
        "gays", "hair", "hangs", "hans", "harm", "hats", "hays", "heer", "heest",
        "here", "hero", "hist", "hits", "hoest", "hongs", "horn", "host", "hungs", "inf",
        "ins", "ira", "ist", "its", "keeps", "kens", "kits", "langs", "lans", "laos",
        "last", "lats", "lays", "leer", "leest", "leos", "lets", "lips", "lisa",
        "list", "loes", "loest", "longs", "loops", "lose", "lost", "lots", "luis",
        "mais", "mans", "mary", "mats", "mays", "meest", "meets", "mens", "mere", "mias",
        "most", "must", "nams", "neer", "neest", "neos", "nest", "nons", "norm",
        "nuts", "oer", "oes", "oops", "owns", "past", "pest", "pets", "pics", "queens",
        "queest", "quest", "taxi", "teest", "term", "test", "thais", "thats", "theer",
        "theest", "there", "these", "tims", "tips", "tits", "toer", "toes", "toest",
        "toms", "tops", "towns", "turn", "ums", "ups", "uri", "urw", "usa", "usc",
        "vary", "vast", "vees", "veest", "vias", "visa", "vons", "was",
    ]

    /// Longest word in the set — lets the caller skip words that can't possibly match.
    static let maxLength = 12
}
