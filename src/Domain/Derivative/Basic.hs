-----------------------------------------------------------------------------
-- Copyright 2008, Open Universiteit Nederland. This file is distributed 
-- under the terms of the GNU General Public License. For more information, 
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-----------------------------------------------------------------------------
module Domain.Derivative.Basic where

import Common.Context
import Common.Unification
import Control.Monad
import Data.List
import qualified Data.Set as S
import Data.Maybe
import Data.Ratio
import Test.QuickCheck

data Expr
   = Con Rational 
   | Var String
   | Expr :+: Expr 
   | Expr :*: Expr 
   | Expr :-: Expr
   | Negate Expr
   | Expr :^: Expr 
   | Expr :/: Expr 
   | Special Sym Expr
   | Lambda String Expr
   | Diff Expr
 deriving (Show, Read, Eq)
 
data Sym = Sin | Cos | Ln
   deriving (Show, Read, Eq, Enum)
 
syms :: [Sym]
syms = [Sin .. Ln]
 
noDiff :: Expr -> Bool
noDiff f = null [ () | Diff _ <- universe f ]
  
instance Uniplate Expr where
   uniplate function =
      case function of
         Con r          -> ([], \_ -> Con r)
         Var s          -> ([], \_ -> Var s)
         f :+: g        -> ([f,g], \[x,y] -> x :+: y)
         f :*: g        -> ([f,g], \[x,y] -> x :*: y)
         f :-: g        -> ([f,g], \[x,y] -> x :-: y)
         Negate f       -> ([f], \[x] -> Negate x)
         f :^: g        -> ([f,g], \[x,y] -> x :^: y)
         f :/: g        -> ([f,g], \[x,y] -> x :/: y)
         Special s f    -> ([f], \[x] -> Special s x)
         Lambda s f     -> ([f], \[x] -> Lambda s x)
         Diff f     -> ([f],   \[x] -> Diff x)

instance Arbitrary Sym where
   arbitrary = oneof $ map return syms
   coarbitrary a = coarbitrary (elemIndex a syms)
 
instance Arbitrary Expr where
   arbitrary = sized arbFun
   coarbitrary function =
      case function of
         Con r       -> variant 0 . coarbitrary (numerator r) . coarbitrary (denominator r)
         Var s       -> variant 1 . coarbitrary s
         f :+: g     -> variant 2 . coarbitrary f . coarbitrary g
         f :*: g     -> variant 3 . coarbitrary f . coarbitrary g
         f :*: g     -> variant 4 . coarbitrary f . coarbitrary g
         Negate f    -> variant 5 . coarbitrary f
         f :^: g     -> variant 6 . coarbitrary f . coarbitrary g
         f :/: g     -> variant 7 . coarbitrary f . coarbitrary g
         Special s f -> variant 8 . coarbitrary s . coarbitrary f
         Lambda s f  -> variant 9 . coarbitrary s . coarbitrary f
         Diff f      -> variant 10 . coarbitrary f

arbFun :: Int -> Gen Expr
arbFun 0 = oneof [ liftM (Con . fromInteger) arbitrary, return (Var "x"), return (Var "y") ]
arbFun n = oneof [ arbFun 0, liftM Diff rec
                 , bin (:+:), bin (:*:), bin (:^:), bin (:/:), liftM2 Special arbitrary rec
                 , liftM (Lambda "x") rec
                 ]
 where
   rec    = arbFun (n `div` 2)
   bin op = liftM2 op rec rec
   
instance Num Expr where
   (+) = (:+:)
   (*) = (:*:)
   (-) = (:-:)
   negate = Negate
   fromInteger = Con . fromInteger
       
instance Fractional Expr where
   (/) = (:/:)
   fromRational = Con

instance HasVars Expr where
   getVarsList e = [ x | Var x <- universe e ]

instance MakeVar Expr where
   makeVar = Var
   
instance Substitutable Expr where 
   sub |-> e@(Var x) = fromMaybe e (lookupVar x sub)
   sub |-> e = let (as, f) = uniplate e 
               in f (map (sub |->) as)
       
instance Unifiable Expr where
   unify = unifyExpr
   
unifyExpr :: Expr -> Expr -> Maybe (Substitution Expr)
unifyExpr e1 e2 = 
   case (e1, e2) of
      (Var x, Var y) | x==y      -> return emptySubst
      (Var x, _) | not (x `S.member` getVars e2) -> return (singletonSubst x e2)
      (_, Var y) | not (y `S.member` getVars e1) -> return (singletonSubst y e1)
      (Con x, Con y) -> if x==y then return emptySubst else Nothing
      (Special f _, Special g _) | f /= g -> Nothing
--      (Lambda x e1, Lambda y e2) | x /= y ->
      _ -> if (exprToConNr e1 == exprToConNr e2) 
           then unifyList (children e1) (children e2)
           else Nothing

exprToConNr :: Expr -> Int
exprToConNr expr =
   case expr of
      Var _       -> 0
      Con _       -> 1
      _ :+: _     -> 2
      _ :*: _     -> 3
      _ :-: _     -> 4
      _ :^: _     -> 5
      _ :/: _     -> 6
      Lambda _ _  -> 7
      Negate _    -> 8
      Diff  _     -> 9
      Special _ _ -> 10