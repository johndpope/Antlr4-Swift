/* Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */

///
/// This class provides a default implementation of the _org.antlr.v4.runtime.Vocabulary_
/// interface.
///
/// - Author: Sam Harwell
///

public struct Vocabulary {
    public static let EMPTY_NAMES: [String?] = [""]

    ///
    /// Gets an empty _org.antlr.v4.runtime.Vocabulary_ instance.
    ///
    ///
    /// No literal or symbol names are assigned to token types, so
    /// _#getDisplayName(int)_ returns the numeric value for all tokens
    /// except _org.antlr.v4.runtime.Token#EOF_.
    ///
    public static let EMPTY_VOCABULARY: Vocabulary = Vocabulary(EMPTY_NAMES, EMPTY_NAMES, EMPTY_NAMES)

    private var literalNames: [String?]

    private var symbolicNames: [String?]

    private var displayNames: [String?]
    
    ///
    /// Constructs a new instance of _org.antlr.v4.runtime.Vocabulary_ from the specified
    /// literal, symbolic, and display token names.
    ///
    /// - SeeAlso: #getLiteralName(int)
    /// - SeeAlso: #getSymbolicName(int)
    /// - SeeAlso: #getDisplayName(int)
    /// - Parameter literalNames: The literal names assigned to tokens, or `null`
    /// if no literal names are assigned.
    /// - Parameter symbolicNames: The symbolic names assigned to tokens, or
    /// `null` if no symbolic names are assigned.
    /// - Parameter displayNames: The display names assigned to tokens, or `null`
    /// to use the values in `literalNames` and `symbolicNames` as
    /// the source of display names, as described in
    /// _#getDisplayName(int)_.
    ///
    ///
    public init(_ literalNames: [String?] = EMPTY_NAMES,
                _ symbolicNames: [String?] = EMPTY_NAMES,
                _ displayNames: [String?] = EMPTY_NAMES) {
        self.literalNames = literalNames
        self.symbolicNames = symbolicNames
        self.displayNames = displayNames
    }
    
    public func getLiteralName(_ tokenType: Int) -> String? {
        if tokenType >= 0 && tokenType < literalNames.count {
            return literalNames[tokenType]
        }

        return nil
    }

    public func getSymbolicName(_ tokenType: Int) -> String? {
        if tokenType >= 0 && tokenType < symbolicNames.count {
            return symbolicNames[tokenType]
        }
        if tokenType == CommonToken.EOF {
            return "EOF"
        }
        
        return nil
    }
    
    public func getDisplayName(_ tokenType: Int) -> String {
        if tokenType >= 0 && tokenType < displayNames.count {
            if let displayName = displayNames[tokenType] {
                return displayName
            }
        }
        
        if let literalName = getLiteralName(tokenType) {
            return literalName
        }
        
        if let symbolicName = getSymbolicName(tokenType) {
            return symbolicName
        }
        
        return String(tokenType)
    }
}

public extension Vocabulary {
    
    ///
    /// Returns a _org.antlr.v4.runtime.Vocabulary_ instance from the specified set of token
    /// names. This method acts as a compatibility layer for the single
    /// `tokenNames` array generated by previous releases of ANTLR.
    ///
    /// The resulting vocabulary instance returns `null` for
    /// _#getLiteralName(int)_ and _#getSymbolicName(int)_, and the
    /// value from `tokenNames` for the display names.
    ///
    /// - Parameter tokenNames: The token names, or `null` if no token names are
    /// available.
    /// - Returns: A _org.antlr.v4.runtime.Vocabulary_ instance which uses `tokenNames` for
    /// the display names of tokens.
    ///
    public static func fromTokenNames(_ tokenNames: [String?]?) -> Vocabulary {
        guard let tokenNames = tokenNames, tokenNames.count > 0 else {
            return EMPTY_VOCABULARY
        }
        
        var literalNames = tokenNames
        var symbolicNames = tokenNames
        let length = tokenNames.count
        for i in 0..<length {
            guard let tokenName = tokenNames[i] else {
                continue
            }
            if let firstChar = tokenName.first {
                if firstChar == "\'" {
                    symbolicNames[i] = nil
                    continue
                } else if String(firstChar).uppercased() != String(firstChar) {
                    literalNames[i] = nil
                    continue
                }
            }
            
            // wasn't a literal or symbolic name
            literalNames[i] = nil
            symbolicNames[i] = nil
        }
        
        return Vocabulary(literalNames, symbolicNames, tokenNames)
    }
}
