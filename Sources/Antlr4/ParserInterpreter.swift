/* Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */

/// A parser simulator that mimics what ANTLR's generated
/// parser code does. A ParserATNSimulator is used to make
/// predictions via adaptivePredict but this class moves a pointer through the
/// ATN to simulate parsing. ParserATNSimulator just
/// makes us efficient rather than having to backtrack, for example.
///
/// This properly creates parse trees even for left recursive rules.
///
/// We rely on the left recursive rule invocation and special predicate
/// transitions to make left recursive rules work.
///
/// See TestParserInterpreter for examples.
///

public class ParserInterpreter: Parser {
    internal final var grammarFileName: String
    internal final var atn: ATN
    /// This identifies StarLoopEntryState's that begin the (...)*
    /// precedence loops of left recursive rules.
    ///
    internal final var statesNeedingLeftRecursionContext: BitSet

    internal final var decisionToDFA: [DFA]
    // not shared like it is for generated parsers
    internal final var sharedContextCache: PredictionContextCache =
        PredictionContextCache()

    internal final var ruleNames: [String]

    private final var vocabulary: Vocabulary

    /// Tracks LR rules for adjusting the contexts
    internal final var _parentContextStack: [(ParserRuleContext?, Int)] = []

    /// We need a map from (decision,inputIndex)->forced alt for computing ambiguous
    /// parse trees. For now, we allow exactly one override.
    ///
    internal var overrideDecision: Int = -1
    internal var overrideDecisionInputIndex: Int = -1
    internal var overrideDecisionAlt: Int = -1

    /// A copy constructor that creates a new parser interpreter by reusing
    /// the fields of a previous interpreter.
    ///
    /// - Since: 4.5.1
    ///
    /// - Parameter old: The interpreter to copy
    ///
    public init(_ old: ParserInterpreter) throws {

        self.atn = old.atn
        self.grammarFileName = old.grammarFileName
        self.statesNeedingLeftRecursionContext = old.statesNeedingLeftRecursionContext
        self.decisionToDFA = old.decisionToDFA
        self.ruleNames = old.ruleNames
        self.vocabulary = old.vocabulary
        try  super.init(old.getTokenStream()!)
        setInterpreter(ParserATNSimulator(self, atn,
                                          decisionToDFA,
                                          sharedContextCache))
    }

    public init(_ grammarFileName: String, _ vocabulary: Vocabulary,
                _ ruleNames: [String], _ atn: ATN, _ input: TokenStream) throws {

        self.grammarFileName = grammarFileName
        self.atn = atn
        self.ruleNames = ruleNames
        self.vocabulary = vocabulary
        self.decisionToDFA = [DFA]()
        for i in 0 ..< atn.getNumberOfDecisions() {
            decisionToDFA[i] = DFA(atn.getDecisionState(i)!, i)
        }

        // identify the ATN states where pushNewRecursionContext() must be called
        self.statesNeedingLeftRecursionContext = BitSet(atn.states.count)
        for  state in atn.states {
            if let state = state as? StarLoopEntryState {
                if state.precedenceRuleDecision {
                    self.statesNeedingLeftRecursionContext.set(state.stateNumber)
                }
            }

        }
        try super.init(input)
        // get atn simulator that knows how to do predictions
        setInterpreter(ParserATNSimulator(self, atn,
                                          decisionToDFA,
                                          sharedContextCache))
    }

    override
    public func getATN() -> ATN {
        return atn
    }

    override
    public func getVocabulary() -> Vocabulary {
        return vocabulary
    }

    override
    public func getRuleNames() -> [String] {
        return ruleNames
    }

    override
    public func getGrammarFileName() -> String {
        return grammarFileName
    }

    /// Begin parsing at startRuleIndex
    public func parse(_ startRuleIndex: Int) throws -> ParserRuleContext {
        let startRuleStartState = atn.ruleToStartState[startRuleIndex]

        let rootContext = InterpreterRuleContext(nil, ATNState.INVALID_STATE_NUMBER, startRuleIndex)
        if startRuleStartState.isPrecedenceRule {
            try enterRecursionRule(rootContext, startRuleStartState.stateNumber, startRuleIndex, 0)
        } else {
            try enterRule(rootContext, startRuleStartState.stateNumber, startRuleIndex)
        }

        while true {
            let p = getATNState()!
            switch p.getStateType() {
            case ATNState.RULE_STOP:
                // pop; return from rule
                if _ctx!.isEmpty() {
                    if startRuleStartState.isPrecedenceRule {
                        let result: ParserRuleContext = _ctx!
                        let parentContext: (ParserRuleContext?, Int) = _parentContextStack.removeLast()
                        try unrollRecursionContexts(parentContext.0!)
                        return result
                    } else {
                        try exitRule()
                        return rootContext
                    }
                }

                try visitRuleStopState(p)

            default:
                do {
                    try self.visitState(p)
                } catch ANTLRException.recognition(let e) {
                    setState(self.atn.ruleToStopState[p.ruleIndex!].stateNumber)
                    getContext()!.exception = e
                    getErrorHandler().reportError(self, e)
                    try getErrorHandler().recover(self, e)
                }
            }
        }
    }

    override
    public func enterRecursionRule(_ localctx: ParserRuleContext, _ state: Int,
                                   _ ruleIndex: Int, _ precedence: Int) throws {
        let pair: (ParserRuleContext?, Int) = (_ctx, localctx.invokingState)
        _parentContextStack.append(pair)
        try super.enterRecursionRule(localctx, state, ruleIndex, precedence)
    }

    internal func getATNState() -> ATNState? {
        return atn.states[getState()]
    }

    internal func visitState(_ p: ATNState) throws {
        var altNum: Int
        if p.getNumberOfTransitions() > 1 {
            try getErrorHandler().sync(self)
            let decision = (p as! DecisionState).decision
            if decision == overrideDecision && _input.index() == overrideDecisionInputIndex {
                altNum = overrideDecisionAlt
            } else {
                altNum = try getInterpreter().adaptivePredict(_input, decision, _ctx)
            }
        } else {
            altNum = 1
        }

        let transition = p.transition(altNum - 1)
        
        switch transition {
        case .epsilon:
            if statesNeedingLeftRecursionContext.get(p.stateNumber) &&
                !(transition.target is LoopEndState) {
                // We are at the start of a left recursive rule's (...)* loop
                // but it's not the exit branch of loop.
                let ctx: InterpreterRuleContext = InterpreterRuleContext(
                    _parentContextStack.last!.0, //peek()
                    _parentContextStack.last!.1, //peek()
                    
                    _ctx!.getRuleIndex())
                try pushNewRecursionContext(ctx,
                                            atn.ruleToStartState[p.ruleIndex!].stateNumber,
                                            _ctx!.getRuleIndex())
            }
            
        case .atom(_, let label):
            try match(label)
            
        case .range, .set, .notSet:
            if !transition.matches(try _input.LA(1), CommonToken.minUserTokenType, 65535) {
                try _errHandler.recoverInline(self)
            }
            try matchWildcard()
            
        case .wildcard:
            try matchWildcard()
            
        case .rule(_, _, let precedence, _):
            let ruleStartState = transition.target as! RuleStartState
            let ruleIndex = ruleStartState.ruleIndex!
            let ctx = InterpreterRuleContext(_ctx, p.stateNumber, ruleIndex)
            if ruleStartState.isPrecedenceRule {
                try enterRecursionRule(ctx, ruleStartState.stateNumber, ruleIndex,
                                       precedence)
            } else {
                try enterRule(ctx, transition.target.stateNumber, ruleIndex)
            }
            
        case .predicate(_, let .predicate(ruleIndex, predIndex, _)):
            if try !sempred(_ctx!, ruleIndex, predIndex) {
                throw ANTLRException.recognition(e: FailedPredicateException(self))
            }
            
        case .action(_, let ruleIndex, let actionIndex, _):
            try action(_ctx, ruleIndex, actionIndex)
            
        case .predicate(_, .precedence(let precedence)):
            if !precpred(_ctx!, precedence) {
                throw ANTLRException.recognition(e:
                    FailedPredicateException(self, "precpred(_ctx,\(precedence))"))
            }
        }
        
        setState(transition.target.stateNumber)
    }

    internal func visitRuleStopState(_ p: ATNState) throws {
        let ruleStartState = atn.ruleToStartState[p.ruleIndex!]
        if ruleStartState.isPrecedenceRule {
            let (parentContext, parentState) = _parentContextStack.removeLast()
            try unrollRecursionContexts(parentContext!)
            setState(parentState)
        } else {
            try exitRule()
        }
        
        switch atn.states[getState()]!.transition(0) {
        case .rule(_, _, _, let followState):
            setState(followState.stateNumber)
        default:
            fatalError("Expected .rule transition.")
        }
    }

    /// Override this parser interpreters normal decision-making process
    /// at a particular decision and input token index. Instead of
    /// allowing the adaptive prediction mechanism to choose the
    /// first alternative within a block that leads to a successful parse,
    /// force it to take the alternative, 1..n for n alternatives.
    ///
    /// As an implementation limitation right now, you can only specify one
    /// override. This is sufficient to allow construction of different
    /// parse trees for ambiguous input. It means re-parsing the entire input
    /// in general because you're never sure where an ambiguous sequence would
    /// live in the various parse trees. For example, in one interpretation,
    /// an ambiguous input sequence would be matched completely in expression
    /// but in another it could match all the way back to the root.
    ///
    /// s : e '!'? ;
    /// e : ID
    /// | ID '!'
    /// ;
    ///
    /// Here, x! can be matched as (s (e ID) !) or (s (e ID !)). In the first
    /// case, the ambiguous sequence is fully contained only by the root.
    /// In the second case, the ambiguous sequences fully contained within just
    /// e, as in: (e ID !).
    ///
    /// Rather than trying to optimize this and make
    /// some intelligent decisions for optimization purposes, I settled on
    /// just re-parsing the whole input and then using
    /// {link Trees#getRootOfSubtreeEnclosingRegion} to find the minimal
    /// subtree that contains the ambiguous sequence. I originally tried to
    /// record the call stack at the point the parser detected and ambiguity but
    /// left recursive rules create a parse tree stack that does not reflect
    /// the actual call stack. That impedance mismatch was enough to make
    /// it it challenging to restart the parser at a deeply nested rule
    /// invocation.
    ///
    /// Only parser interpreters can override decisions so as to avoid inserting
    /// override checking code in the critical ALL(*) prediction execution path.
    ///
    /// - Since: 4.5.1
    ///
    public func addDecisionOverride(_ decision: Int, _ tokenIndex: Int, _ forcedAlt: Int) {
        overrideDecision = decision
        overrideDecisionInputIndex = tokenIndex
        overrideDecisionAlt = forcedAlt
    }
}
