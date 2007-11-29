module Domain.LinearAlgebra.LinearSystem where

import Domain.LinearAlgebra.Matrix (Matrix, makeMatrix, rows)
import Domain.LinearAlgebra.Equation
import Domain.LinearAlgebra.LinearExpr
import Data.List
import Data.Maybe
import Control.Monad
import Common.Utils

type LinearSystem a = Equations (LinearExpr a)

evalSystem :: Num a => (String -> a) -> LinearSystem a -> Bool
evalSystem = all . evalEquationWith . evalLinearExpr

invalidSystem :: Eq a => LinearSystem a -> Bool
invalidSystem = any invalidEquation

invalidEquation :: Eq a => Equation (LinearExpr a) -> Bool
invalidEquation eq@(lhs :==: rhs) = null (getVarEquation eq) && getConstant lhs /= getConstant rhs

getVarEquation :: Equation (LinearExpr a) -> [String]
getVarEquation (x :==: y) = getVars x `union` getVars y

getVarEquations :: LinearSystem a -> [String]
getVarEquations = foldr (union . getVarEquation) []

subVarEquation :: Num a => String -> LinearExpr a -> Equation (LinearExpr a) -> Equation (LinearExpr a)
subVarEquation var a = fmap (substVar var a)

subVarEquations :: Num a => String -> LinearExpr a -> Equations (LinearExpr a) -> Equations (LinearExpr a)
subVarEquations var a = map (subVarEquation var a)

getSolution :: Num a => LinearSystem a -> Maybe [(String, LinearExpr a)]
getSolution xs = do
   guard (distinct vars)
   guard (null (vars `intersect` frees))
   mapM make xs
 where
   vars  = concatMap (getVars . getLHS) xs
   frees = concatMap (getVars . getRHS) xs
   make (lhs :==: rhs) = do
      v <- isVar lhs
      return (v, rhs)
      
-- No constant on the left, no variables on the right
inStandardForm :: Num a => Equation (LinearExpr a) -> Bool
inStandardForm (lhs :==: rhs) = getConstant lhs == 0 && null (getVars rhs)

toStandardForm :: Num a => Equation (LinearExpr a) -> Equation (LinearExpr a)
toStandardForm (lhs :==: rhs) =
      let c = toLinearExpr (getConstant rhs - getConstant lhs)
      in (lhs - rhs + c) :==: c


inSolvedForm :: Num a => LinearSystem a -> Bool
inSolvedForm xs = invalidSystem xs || isJust (getSolution xs)

-- Conversions
systemToMatrix :: Num a => LinearSystem a -> Matrix a
systemToMatrix system = makeMatrix (map (makeRow . toStandardForm) system)
 where
   vars = sort (getVarEquations system)
   makeRow (lhs :==: rhs) =
      map (`coefficientOf` lhs) vars ++ [getConstant rhs]

matrixToSystem :: Num a => Matrix a -> LinearSystem a
matrixToSystem = map makeEquation . rows
 where
   makeEquation xs = 
      sum (zipWith (\v a -> toLinearExpr a * var v) variables (init xs)) :==: toLinearExpr (last xs)
      
variables :: [String]
variables = map (\n -> 'x' : [n]) ['a' .. 'z'] -- should be sorted!!