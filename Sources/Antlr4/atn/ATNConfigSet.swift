///
/// Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
/// Use of this file is governed by the BSD 3-clause license that
/// can be found in the LICENSE.txt file in the project root.
///

///
/// Specialized _java.util.Set_`<`_org.antlr.v4.runtime.atn.ATNConfig_`>` that can track
/// info about the set, with support for combining similar configurations using a
/// graph-structured stack.
///
public struct ATNConfigSet: Hashable, CustomStringConvertible {
    ///
    /// The reason that we need this is because we don't want the hash map to use
    /// the standard hash code and equals. We need all configurations with the same
    /// `(s,i,_,semctx)` to be equal. Unfortunately, this key effectively doubles
    /// the number of objects associated with ATNConfigs. The other solution is to
    /// use a hash table that lets us specify the equals/hashcode operation.
    ///
    
    ///
    /// All configs but hashed by (s, i, _, pi) not including context. Wiped out
    /// when we go readonly as this set becomes a DFA state.
    ///
    public var configLookup: LookupDictionary

    ///
    /// Track the elements as they are added to the set; supports get(i)
    ///
    public var configs = [ATNConfig]()

    // TODO: these fields make me pretty uncomfortable but nice to pack up info together, saves recomputation
    // TODO: can we track conflicts as they are added to save scanning configs later?
    public var uniqueAlt = 0
    //TODO no default
    ///
    /// Currently this is only used when we detect SLL conflict; this does
    /// not necessarily represent the ambiguous alternatives. In fact,
    /// I should also point out that this seems to include predicated alternatives
    /// that have predicates that evaluate to false. Computed in computeTargetState().
    ///
    internal var conflictingAlts: BitSet?

    // Used in parser and lexer. In lexer, it indicates we hit a pred
    // while computing a closure operation.  Don't make a DFA state from this.
    public var hasSemanticContext = false
    //TODO no default
    public var dipsIntoOuterContext = false
    //TODO no default

    ///
    /// Indicates that this configuration set is part of a full context
    /// LL prediction. It will be used to determine how to merge $. With SLL
    /// it's a wildcard whereas it is not for LL context merge.
    ///
    public var fullCtx: Bool

    private var cachedHashCode = -1

    public init(_ fullCtx: Bool = true, ordered: Bool = false) {
        if ordered {
            configLookup = LookupDictionary(type: LookupDictionaryType.ordered)
        } else {
            configLookup = LookupDictionary()
        }

        self.fullCtx = fullCtx
        
        cachedHashCode = configsHashValue
    }

    public init(_ old: ATNConfigSet) {
        if old.configLookup.type == .ordered {
            configLookup = LookupDictionary(type: LookupDictionaryType.ordered)
        } else {
            configLookup = LookupDictionary()
        }
        
        self.fullCtx = old.fullCtx
        
        addAll(old)
        self.uniqueAlt = old.uniqueAlt
        self.conflictingAlts = old.conflictingAlts
        self.hasSemanticContext = old.hasSemanticContext
        self.dipsIntoOuterContext = old.dipsIntoOuterContext
        
        cachedHashCode = configsHashValue
    }

    //override
    @discardableResult
    public mutating func add(_ config: ATNConfig) -> Bool {
        var mergeCache: [TuplePair<PredictionContext, PredictionContext>: PredictionContext]? = nil
        return add(config, &mergeCache)
    }

    ///
    /// Adding a new config means merging contexts with existing configs for
    /// `(s, i, pi, _)`, where `s` is the
    /// _org.antlr.v4.runtime.atn.ATNConfig#state_, `i` is the _org.antlr.v4.runtime.atn.ATNConfig#alt_, and
    /// `pi` is the _org.antlr.v4.runtime.atn.ATNConfig#semanticContext_. We use
    /// `(s,i,pi)` as key.
    ///
    /// This method updates _#dipsIntoOuterContext_ and
    /// _#hasSemanticContext_ when necessary.
    /// - precondition: This set is not readonly.
    ///
    @discardableResult
    public mutating func add(
        _ config: ATNConfig,
        _ mergeCache: inout [TuplePair<PredictionContext, PredictionContext>: PredictionContext]?) -> Bool {
        if config.semanticContext != SemanticContext.NONE {
            hasSemanticContext = true
        }
        if config.getOuterContextDepth() > 0 {
            dipsIntoOuterContext = true
        }
        let existing: ATNConfig = getOrAdd(config)
        if existing === config {
            // we added this new one
            cachedHashCode = -1
            configs.append(config)  // track order here
            return true
        }
        // a previous (s,i,pi,_), merge with it and save result
        let rootIsWildcard = !fullCtx

        let merged = PredictionContext.merge(existing.context!, config.context!, rootIsWildcard, &mergeCache)

        // no need to check for existing.context, config.context in cache
        // since only way to create new graphs is "call rule" and here. We
        // cache at both places.
        existing.reachesIntoOuterContext =
            max(existing.reachesIntoOuterContext, config.reachesIntoOuterContext)

        // make sure to preserve the precedence filter suppression during the merge
        if config.isPrecedenceFilterSuppressed() {
            existing.setPrecedenceFilterSuppressed(true)
        }

        existing.context = merged // replace context; no need to alt mapping
        return true
    }

    public mutating func getOrAdd(_ config: ATNConfig) -> ATNConfig {

        return configLookup.getOrAdd(config)
    }

    ///
    /// Return a List holding list of configs
    ///
    public func elements() -> [ATNConfig] {
        return configs
    }

    public func getStates() -> Set<ATNState> {
        var states = Set<ATNState>(minimumCapacity: configs.count)
        for config in configs {
            states.insert(config.state)
        }
        return states
    }

    ///
    /// Gets the complete set of represented alternatives for the configuration
    /// set.
    ///
    /// - returns: the set of represented alternatives in this configuration set
    ///
    /// - since: 4.3
    ///
    public func getAlts() -> BitSet {
        var alts = BitSet()
        for config in configs {
            alts.set(config.alt)
        }
        return alts
    }

    public func getPredicates() -> [SemanticContext] {
        var preds = [SemanticContext]()
        for config in configs where config.semanticContext != SemanticContext.NONE {
            preds.append(config.semanticContext)
        }
        return preds
    }

    public func get(_ i: Int) -> ATNConfig {
        return configs[i]
    }

    public func optimizeConfigs(_ interpreter: ATNSimulator) {
        if configLookup.isEmpty {
            return
        }
        for config in configs {
            config.context = interpreter.getCachedContext(config.context!)

        }
    }

    @discardableResult
    public mutating func addAll(_ coll: ATNConfigSet) -> Bool {
        for c in coll.configs {
            add(c)
        }
        return false
    }

    public var hashValue: Int {
        return configsHashValue
    }

    private var configsHashValue: Int {
        var hashCode = 1
        for item in configs {
            hashCode = hashCode &* 3 &+ item.hashValue
        }
        return hashCode
    }

    public var count: Int {
        return configs.count
    }

    public func size() -> Int {
        return configs.count
    }

    public func isEmpty() -> Bool {
        return configs.isEmpty
    }

    public func contains(_ o: ATNConfig) -> Bool {

        return configLookup.contains(o)
    }

    public mutating func clear() {
        configs.removeAll()
        cachedHashCode = -1
        configLookup.removeAll()
    }
    
    public var description: String {
        var buf = ""
        buf += String(describing: elements())
        if hasSemanticContext {
            buf += ",hasSemanticContext=true"
        }
        if uniqueAlt != ATN.INVALID_ALT_NUMBER {
            buf += ",uniqueAlt=\(uniqueAlt)"
        }
        if let conflictingAlts = conflictingAlts {
            buf += ",conflictingAlts=\(conflictingAlts)"
        }
        if dipsIntoOuterContext {
            buf += ",dipsIntoOuterContext"
        }
        return buf
    }

    ///
    /// override
    /// public <T> func toArray(a : [T]) -> [T] {
    /// return configLookup.toArray(a);
    ///
    private func configHash(_ stateNumber: Int, _ context: PredictionContext?) -> Int {
        var hashCode = MurmurHash.initialize(7)
        hashCode = MurmurHash.update(hashCode, stateNumber)
        hashCode = MurmurHash.update(hashCode, context)
        return MurmurHash.finish(hashCode, 2)
    }

    public func getConflictingAltSubsets() -> [BitSet] {
        let length = configs.count
        var configToAlts = [Int: BitSet]()

        for i in 0..<length {
            let hash = configHash(configs[i].state.stateNumber, configs[i].context)
            configToAlts[hash, default: BitSet()].set(configs[i].alt)
        }

        return Array(configToAlts.values)
    }

    public func getStateToAltMap() -> [ATNState: BitSet] {
        let length = configs.count
        var m = [ATNState: BitSet]()

        for i in 0..<length {
            m[configs[i].state, default: BitSet()].set(configs[i].alt)
        }
        return m
    }

    //for DFAState
    public func getAltSet() -> Set<Int>? {
        if configs.isEmpty {
            return nil
        }
        var alts = Set<Int>()
        for config in configs {
            alts.insert(config.alt)
        }
        return alts
    }

    //for DiagnosticErrorListener
    public func getAltBitSet() -> BitSet {
        var result = BitSet()
        for config in configs {
            result.set(config.alt)
        }
        return result
    }

    //LexerATNSimulator
    public var firstConfigWithRuleStopState: ATNConfig? {
        return configs.first(where: { $0.state is RuleStopState })
    }

    //ParserATNSimulator

    public func getUniqueAlt() -> Int {
        var alt = ATN.INVALID_ALT_NUMBER
        for config in configs {
            if alt == ATN.INVALID_ALT_NUMBER {
                alt = config.alt // found first alt
            } else if config.alt != alt {
                return ATN.INVALID_ALT_NUMBER
            }
        }
        return alt
    }

    public func removeAllConfigsNotInRuleStopState(
        _ mergeCache: inout [TuplePair<PredictionContext, PredictionContext>: PredictionContext]?,
        _ lookToEndOfRule: Bool,
        _ atn: ATN) -> ATNConfigSet {
        
        if PredictionMode.allConfigsInRuleStopStates(self) {
            return self
        }

        var result = ATNConfigSet(fullCtx)
        for config in configs {
            if config.state is RuleStopState {
                result.add(config, &mergeCache)
                continue
            }

            if lookToEndOfRule && config.state.onlyHasEpsilonTransitions() {
                let nextTokens = atn.nextTokens(config.state)
                if nextTokens.contains(CommonToken.epsilon) {
                    let endOfRuleState = atn.ruleToStopState[config.state.ruleIndex!]
                    result.add(ATNConfig(config, endOfRuleState), &mergeCache)
                }
            }
        }

        return result
    }

    public func applyPrecedenceFilter(
        _ mergeCache: inout [TuplePair<PredictionContext, PredictionContext>: PredictionContext]?,
        _ parser: Parser,
        _ _outerContext: ParserRuleContext!) throws -> ATNConfigSet {

        var configSet = ATNConfigSet(fullCtx)
        var statesFromAlt1 = [Int: PredictionContext]()
        for config in configs {
            // handle alt 1 first
            if config.alt != 1 {
                continue
            }

            let updatedContext = try config.semanticContext.evalPrecedence(parser, _outerContext)
            if updatedContext == nil {
                // the configuration was eliminated
                continue
            }

            statesFromAlt1[config.state.stateNumber] = config.context
            if updatedContext != config.semanticContext {
                configSet.add(ATNConfig(config, updatedContext!), &mergeCache)
            } else {
                configSet.add(config, &mergeCache)
            }
        }

        for config in configs {
            if config.alt == 1 {
                // already handled
                continue
            }

            if !config.isPrecedenceFilterSuppressed() {
                ///
                /// In the future, this elimination step could be updated to also
                /// filter the prediction context for alternatives predicting alt>1
                /// (basically a graph subtraction algorithm).
                ///
                let context = statesFromAlt1[config.state.stateNumber]
                if context != nil && context == config.context {
                    // eliminated
                    continue
                }
            }

            configSet.add(config, &mergeCache)
        }

        return configSet
    }

    internal func getPredsForAmbigAlts(_ ambigAlts: BitSet, _ nalts: Int) -> [SemanticContext?]? {
        var altToPred = [SemanticContext?](repeating: nil, count: nalts + 1)
        for config in configs {
            if ambigAlts.get(config.alt) {
                altToPred[config.alt] = SemanticContext.or(altToPred[config.alt], config.semanticContext)
            }
        }
        var nPredAlts = 0
        for i in 1...nalts {
            if altToPred[i] == nil {
                altToPred[i] = SemanticContext.NONE
            } else if altToPred[i] != SemanticContext.NONE {
                nPredAlts += 1
            }
        }

        //		// Optimize away p||p and p&&p TODO: optimize() was a no-op
        //		for (int i = 0; i < altToPred.length; i++) {
        //			altToPred[i] = altToPred[i].optimize();
        //		}

        // nonambig alts are null in altToPred
        return (nPredAlts == 0 ? nil : altToPred)
    }

    public func getAltThatFinishedDecisionEntryRule() -> Int {
        var alts = IntervalSet()
        for config in configs {
            if config.getOuterContextDepth() > 0 ||
                (config.state is RuleStopState &&
                    config.context!.hasEmptyPath()) {
                alts.add(config.alt)
            }
        }
        if alts.size() == 0 {
            return ATN.INVALID_ALT_NUMBER
        }
        return alts.getMinElement()
    }

    ///
    /// Walk the list of configurations and split them according to
    /// those that have preds evaluating to true/false.  If no pred, assume
    /// true pred and include in succeeded set.  Returns Pair of sets.
    ///
    /// Create a new set so as not to alter the incoming parameter.
    ///
    /// Assumption: the input stream has been restored to the starting point
    /// prediction, which is where predicates need to evaluate.
    ///
    public func splitAccordingToSemanticValidity(
        _ outerContext: ParserRuleContext,
        _ evalSemanticContext: (SemanticContext, ParserRuleContext, Int, Bool) throws -> Bool) rethrows -> (ATNConfigSet, ATNConfigSet) {
        var succeeded = ATNConfigSet(fullCtx)
        var failed = ATNConfigSet(fullCtx)
        for config in configs {
            if config.semanticContext != SemanticContext.NONE {
                let predicateEvaluationResult =
                    try evalSemanticContext(config.semanticContext, outerContext, config.alt, fullCtx)
                
                if predicateEvaluationResult {
                    succeeded.add(config)
                } else {
                    failed.add(config)
                }
            } else {
                succeeded.add(config)
            }
        }
        return (succeeded, failed)
    }

    public func dupConfigsWithoutSemanticPredicates() -> ATNConfigSet {
        var dup = ATNConfigSet()
        for config in configs {
            let c = ATNConfig(config, SemanticContext.NONE)
            dup.add(c)
        }
        return dup
    }

    public var hasConfigInRuleStopState: Bool {
        return configs.contains(where: { $0.state is RuleStopState })
    }

    public var allConfigsInRuleStopStates: Bool {
        return !configs.contains(where: { !($0.state is RuleStopState) })
    }
}

public func == (lhs: ATNConfigSet, rhs: ATNConfigSet) -> Bool {
    return
        lhs.configs == rhs.configs && // includes stack context
            lhs.fullCtx == rhs.fullCtx &&
            lhs.uniqueAlt == rhs.uniqueAlt &&
            lhs.conflictingAlts == rhs.conflictingAlts &&
            lhs.hasSemanticContext == rhs.hasSemanticContext &&
            lhs.dipsIntoOuterContext == rhs.dipsIntoOuterContext
}
