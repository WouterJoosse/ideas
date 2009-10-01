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
module Domain.Math.Equation.Views 
   ( equationSolvedForm, solvedEquation, solvedEquations ) where

import Domain.Math.Expr
import Domain.Math.Data.OrList
import Domain.Math.Data.Equation
import Common.View
import Common.Traversable

-------------------------------------------------------------
-- Views on equations

solvedEquations :: OrList (Equation Expr) -> Bool
solvedEquations = all solvedEquation . crush

solvedEquation :: Equation Expr -> Bool
solvedEquation eq@(lhs :==: rhs) = 
   (eq `belongsTo` equationSolvedForm) || (noVars lhs && noVars rhs)

equationSolvedForm :: View (Equation Expr) (String, Expr)
equationSolvedForm = makeView f g
 where
   f (Var x :==: e) | x `notElem` collectVars e =
      return (x, e)
   f _ = Nothing
   g (s, e) = Var s :==: e