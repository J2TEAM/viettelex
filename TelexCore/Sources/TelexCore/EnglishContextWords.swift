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
        "a", "an", "the", "some", "any", "no", "every", "each",
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
        // common adverbs / adjectives / misc
        "not", "yes", "ok", "okay", "hi", "hello", "hey",
        "here", "there", "now", "just", "only", "also", "too", "very",
        "well", "back", "down", "new", "old", "good", "great", "big",
        "small", "little", "long", "high", "low", "right", "left",
        "next", "last", "first", "one", "two", "three",
        "again", "always", "never", "often", "still", "even", "much",
        "please", "thanks", "thank", "sorry", "really", "maybe",
        "day", "time", "way", "man", "men", "people", "thing", "things",
    ]

    /// Longest word in the set — lets the caller skip words that can't possibly match.
    static let maxLength = 12
}
