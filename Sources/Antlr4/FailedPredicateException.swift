///
/// Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
/// Use of this file is governed by the BSD 3-clause license that
/// can be found in the LICENSE.txt file in the project root.
///

///
/// A semantic predicate failed during validation.  Validation of predicates
/// occurs when normally parsing the alternative just like matching a token.
/// Disambiguating predicate evaluation occurs when we test a predicate during
/// prediction.
///
public class FailedPredicateException: RecognitionException {
    private final var ruleIndex: Int
    private final var predicateIndex: Int
    private final var predicate: String?

    public init(_ recognizer: Parser, _ predicate: String? = nil, _ message: String? = nil) {
        let s = recognizer.getInterpreter().atn.states[recognizer.getState()]!

        switch s.transition(0) {
        case let .predicate(_, .predicate(ruleIndex, predIndex, _)):
            self.ruleIndex = ruleIndex
            self.predicateIndex = predIndex
        default:
            self.ruleIndex = 0
            self.predicateIndex = 0
        }
        
        self.predicate = predicate

        super.init(recognizer, recognizer.getInputStream()!, recognizer._ctx,
                   FailedPredicateException.formatMessage(predicate, message))
        if let token = try? recognizer.getCurrentToken() {
            setOffendingToken(token)
        }
    }

    public func getRuleIndex() -> Int {
        return ruleIndex
    }

    public func getPredIndex() -> Int {
        return predicateIndex
    }

    public func getPredicate() -> String? {
        return predicate
    }

    private static func formatMessage(_ predicate: String?, _ message: String?) -> String {
        if let message = message {
            return message
        }

        let predstr = predicate ?? "<unknown>"
        return "failed predicate: {\(predstr)}?"
    }
}
