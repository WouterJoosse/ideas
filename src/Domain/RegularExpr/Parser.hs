-----------------------------------------------------------------------------
-- Copyright 2009, Open Universiteit Nederland. This file is distributed 
-- under the terms of the GNU General Public License. For more information, 
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-----------------------------------------------------------------------------
module Domain.RegularExpr.Parser (parseRegExp) where

import Domain.RegularExpr.Expr
import Text.Parsing

logicScanner :: Scanner
logicScanner = (specialSymbols "+*?|" defaultScanner)
   { keywords = ["T", "F"]
   , keywordOperators = ["+", "*", "?", "|"]
   , isIdentifierCharacter = const False
   }

parseRegExp :: String -> Either SyntaxError RegExp
parseRegExp = parseWith logicScanner pRE

pRE :: TokenParser RegExp
pRE = pOr 
 where
   pOr   =  pChainl ((:|:) <$ pKey "|") pSeq
   pSeq  =  foldl1 (:*:) <$> pList1 pPost
   pPost =  foldl (flip ($)) <$> pAtom <*> pList pUnop
   pUnop =  Star <$ pKey "*" <|> Plus <$ pKey "+" <|> Option <$ pKey "?"
   pAtom =  Atom <$> pVarid
        <|> Epsilon  <$ pKey "T"
        <|> EmptySet <$ pKey "F"
        <|> pSpec '(' *> pRE <* pSpec ')'

-- testje = parseRegExp "P+*((QS?)?|R)"