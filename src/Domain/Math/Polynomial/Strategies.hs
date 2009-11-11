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
module Domain.Math.Polynomial.Strategies 
   ( linearStrategy, quadraticStrategy, quadraticStrategy2, thisView, switchView
   , higherDegreeStrategy 
   ) where

import Prelude hiding (repeat, replicate, fail)
import Common.Strategy
import Common.Transformation
import Common.Traversable
import Common.View
import Common.Context
import Domain.Math.Equation.CoverUpRules hiding (coverUpPlus)
import Domain.Math.Polynomial.Rules
import Domain.Math.Polynomial.Views
import Domain.Math.Polynomial.QuadraticFormula 
import Domain.Math.Data.OrList
import Domain.Math.Data.Relation
import Domain.Math.Expr
import Domain.Math.Polynomial.CleanUp

------------------------------------------------------------
-- Linear equations

linearStrategy :: LabeledStrategy (Equation Expr)
linearStrategy = cleanUpStrategy (fmap cleanUpSimple) $
   label "Linear Equation" 
    $  label "Phase 1" (repeat (
          removeDivision 
          <|> ruleMulti (ruleSomewhere distributeTimes)
          <|> ruleMulti merge))
   <*> label "Phase 2" (
          try varToLeft 
          <*> try (coverUpPlus id) 
          <*> try (coverUpTimes |> try coverUpNegate))

-- helper strategy
coverUpPlus :: (Rule (Equation Expr) -> Rule a) -> Strategy a
coverUpPlus f = alternatives $ map (f . ($ oneVar))
   [coverUpPlusWith, coverUpMinusLeftWith, coverUpMinusRightWith]

------------------------------------------------------------
-- Quadratic equations

quadraticStrategy2 :: LabeledStrategy (Context (OrList (Relation Expr)))
quadraticStrategy2 = label "Top" $
   mapRules (liftRule thisView) quadraticStrategy <*> 
   try (mapRules (ignoreContext) (hide (label "Approximate" (ruleMulti ruleApproximate))))

thisView :: View (Context (OrList (Relation Expr))) (Context (OrList (Equation Expr)))
thisView = switchView (switchView equationView)

switchView :: Switch f => View a b -> View (f a) (f b)
switchView v = makeView (switch . fmap (match v)) (fmap (build v))

quadraticStrategy :: LabeledStrategy (Context (OrList (Equation Expr)))
quadraticStrategy = cleanUpStrategy (fmap cleanUp) $ 
   label "Quadratic Equation Strategy" $ 
   repeat $  mapRules ignoreContext generalForm
          |> generalABCForm
          |> mapRules ignoreContext zeroForm 
          |> mapRules ignoreContext constantForm
          |> mapRules ignoreContext simplifyForm
          |> mapRules ignoreContext topForm 
 where
   generalForm = label "general form" $ 
      ruleOnce commonFactorVar <|> ruleOnce noLinFormula{- or coverup -}
      <|> ruleOnce niceFactors <|> ruleOnce simplerA 
      <|> coverUpPower -- to deal with special case x^2=0
      
   generalABCForm = label "abc form" $
      toStrategy (ignoreContext abcFormula) -- abcStrategy
 
   zeroForm = label "zero form" $
      toStrategy mulZero
         
   constantForm = label "constant form" $ 
      coverUpPower <|> ruleOnce coverUpTimes <|> coverUpPlus ruleOnce
      <|> ruleOnce coverUpNegate <|> ruleOnce coverUpNumerator 
      <|> squareBothSides <|> ruleOnce factorLeftAsSquare 
         
   simplifyForm = label "square root simplification" $ 
      toStrategy (ruleMulti2 (ruleSomewhere simplerSquareRoot))

   topForm = label "top form" $
      ( ruleOnce2 (ruleSomewhere merge) 
        <|> ruleOnce cancelTerms  
        <|> ruleMulti2 (ruleSomewhere distributionSquare)
        <|> ruleMulti2 (ruleSomewhere distributeTimes) 
        <|> ruleMulti2 (ruleSomewhere distributeDivision)
        <|> ruleOnce flipEquation)
      |> (ruleOnce moveToLeft <|> hide (ruleOnce prepareSplitSquare))
   -- to do: find a better location in the strategy for splitting the square
   
-----------------------------------------------------------
-- Higher degree equations

higherDegreeStrategy :: LabeledStrategy (Context (OrList (Equation Expr)))
higherDegreeStrategy = cleanUpStrategy (fmap cleanUp) $
   label "higher degree" $ 
      mapRules ignoreContext higherForm
      <*> mapRules ignoreContext (label "quadratic" (check isQ) )
      <*> quadraticStrategy
 where
   higherForm = label "higher degree form" $
      repeat (allPowerFactors |> (mulZero <|> ruleOnce2 powerFactor <|> sameFactor))

isQ :: OrList (Equation Expr) -> Bool
isQ = (`belongsTo` quadraticEquationsView)