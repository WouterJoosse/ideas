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
module Domain.Math.Expr.Parser 
   ( scannerExpr, parseExpr, parseWith, pExpr
   , pEquations, pEquation, pOrList, pFractional
   , pRelation, pLogic, pLogicRelation
   ) where

import Prelude hiding ((^))
import Text.Parsing hiding (pParens)
import Control.Monad
import Data.List
import Data.Maybe
import Common.Transformation
import qualified Domain.Logic.Formula as Logic
import Domain.Logic.Formula (Logic)
import Domain.Math.Data.Relation
import Domain.Math.Expr.Data
import Domain.Math.Expr.Symbolic
import Domain.Math.Expr.Symbols
import Domain.Math.Data.OrList
import Test.QuickCheck (arbitrary)

import Text.OpenMath.Dictionary.Arith1
import Text.OpenMath.Dictionary.Logic1
import Text.OpenMath.Dictionary.Relation1
import Text.OpenMath.Dictionary.Calculus1
import Text.OpenMath.Dictionary.Fns1
import Text.OpenMath.Dictionary.Transc1

symbols :: [Symbol]
symbols = nubBy (\x y -> symbolName x == symbolName y) $ 
   concat dictionaries

dictionaries :: [[Symbol]]
dictionaries = 
   [ arith1List, logic1List, relation1List, calculus1List
   , fns1List, transc1List
   ]

dictionaryNames :: [String]
dictionaryNames = mapMaybe dictionary (concatMap (take 1) dictionaries)

scannerExpr :: Scanner
scannerExpr = defaultScanner 
   { keywords           = "sqrt" : map symbolName symbols ++ dictionaryNames
   , keywordOperators   = ["==", "<=", ">=", "<", ">", "~="]
   , operatorCharacters = "+-*/^.=<>~"
   }

parseWith :: TokenParser a -> String -> Either SyntaxError a
parseWith p = f . parse p . scanWith scannerExpr
 where 
   f (e, []) = Right e
   f (_, xs) = Left $ ErrorMessage $ unlines $ map show xs

parseExpr :: String -> Either SyntaxError Expr
parseExpr = parseWith pExpr

pExpr :: TokenParser Expr
pExpr = expr6

-- This expression could have a fraction at top-level: both the numerator
-- and denominator are atoms, optionally preceded by a (unary) minus
pFractional :: TokenParser Expr
pFractional = expr6u -- flip ($) <$> expr6u <*> optional (flip (/) <$ pKey "/" <*> expr6u) id

expr6, expr6u, expr7, expr8, term, atom :: TokenParser Expr
expr6  =  pChainl ((+) <$ pKey "+" <|> (-) <$ pKey "-") expr6u
expr6u =  optional (Negate <$ pKey "-") id <*> expr7
expr7  =  pChainl ((*) <$ pKey "*" <|> (/) <$ pKey "/") expr8
expr8  =  pChainr ((^) <$ pKey "^") term
term   =  symb <*> pList atom
      <|> atom
atom   =  fromInteger <$> pInteger
      <|> Number <$> pReal 
      <|> Var <$> pVarid
      <|> pParens pExpr

symb :: TokenParser ([Expr] -> Expr)
symb =  unqualifiedSymb
    <|> qualifiedSymb
    -- To fix: sqrt expects exactly one argument
    <|> (\xs -> function rootSymbol (xs ++ [2])) <$ pKey "sqrt" 

unqualifiedSymb :: TokenParser ([Expr] -> Expr)
unqualifiedSymb = pChoice (map (\s -> function s <$ pKey (symbolName s)) symbols)

qualifiedSymb :: TokenParser ([Expr] -> Expr)
qualifiedSymb = pChoice (map f dictionaries)
 where
   f xs = case map dictionary xs of
             Just d:_ -> pKey d <* pSpec '.' *> pChoice (map g xs)
             _        -> pFail
   g s  = function s <$ pKey (symbolName s)

pEquations :: TokenParser a -> TokenParser (Equations a)
pEquations = pLines True . pEquation

pEquation :: TokenParser a -> TokenParser (Equation a)
pEquation p = (:==:) <$> p <* pKey "==" <*> p

pRelation :: TokenParser a -> TokenParser (Relation a)
pRelation p = (\x f -> f x) <$> p <*> pRelationType <*> p

pRelationChain :: TokenParser a -> TokenParser [Relation a]
pRelationChain p = f <$> p <*> pList1 ((,) <$> pRelationType <*> p)
 where
   f _ [] = []
   f a ((op, b):xs) = op a b:f b xs

pRelationType :: TokenParser (a -> a -> Relation a)
pRelationType = pChoice (map make table)
 where 
   make (s, f) = f <$ pKey s
   table = 
      [ ("==", (.==.)), ("<=", (.<=.)), (">=", (.>=.))
      , ("<", (.<.)), (">", (.>.)), ("~=", (.~=.))
      ]
   
pOrList :: TokenParser a -> TokenParser (OrList a)
pOrList p = (join . orList) <$> pSepList pTerm (pKey "or")
 where 
   pTerm =  return <$> p 
        <|> true   <$  pKey "true" 
        <|> false  <$  pKey "false"
   pSepList p q = (:) <$> p <*> pList (q *> p)

pLogic :: TokenParser a -> TokenParser (Logic a)
pLogic p = levelOr
 where 
   levelOr    =  pChainr ((Logic.:||:) <$ pKey "or")  levelAnd
   levelAnd   =  pChainr ((Logic.:&&:) <$ pKey "and") levelAtom
   levelAtom  =  Logic.Var <$> p
             <|> Logic.F   <$  pKey "false"
             <|> Logic.T   <$  pKey "true" 
             <|> pParens levelOr

pLogicRelation :: TokenParser a -> TokenParser (Logic (Relation a))
pLogicRelation p = (Logic.catLogic . fmap f) <$> pLogic (pRelationChain p)
 where
   f xs = if null xs then Logic.T else foldr1 (Logic.:&&:) (map Logic.Var xs)

pParens :: TokenParser a -> TokenParser a
pParens p = pSpec '(' *> p <* pSpec ')'

-----------------------------------------------------------------------
-- Argument descriptor (for parameterized rules)

instance Argument Expr where
   makeArgDescr = exprArgDescr

exprArgDescr :: String -> ArgDescr Expr
exprArgDescr descr = ArgDescr descr Nothing (either (const Nothing) Just . parseExpr) show arbitrary