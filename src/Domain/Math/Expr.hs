module Domain.Math.Expr where

import Data.Char  (isDigit)
import Data.Ratio
import Test.QuickCheck
import Control.Monad
import Common.Uniplate
import Common.Rewriting
import Domain.Math.Expr.Symbolic
import Domain.Math.Expr.Symbols

-----------------------------------------------------------------------
-- Expression data type

data Expr = -- Num 
            Expr :+: Expr 
          | Expr :*: Expr 
          | Expr :-: Expr
          | Negate Expr
          | Nat Integer
            -- Fractional & Floating
          | Expr :/: Expr   -- NaN if rhs is zero
          | Sqrt Expr       -- NaN if expr is negative
            -- Symbolic
          | Var String
          | Sym Symbol [Expr]
   deriving (Eq, Ord)

-----------------------------------------------------------------------
-- Numeric instances (and symbolic)

instance Num Expr where
   (+) = (:+:) 
   (*) = (:*:)
   (-) = (:-:)
   fromInteger n 
      | n < 0     = negate $ Nat $ abs n
      | otherwise = Nat n
   negate = Negate 
   abs    = unary absSymbol
   signum = unary signumSymbol

instance Fractional Expr where
   (/) = (:/:)
   fromRational r
      | denominator r == 1 = 
           fromIntegral (numerator r)
      | numerator r < 0 =
           Negate (fromIntegral (abs (numerator r)) :/: fromIntegral (denominator r))
      | otherwise = 
           fromIntegral (numerator r) :/: fromIntegral (denominator r)

instance Floating Expr where
   pi      = symbol piSymbol
   sqrt    = Sqrt
   (**)    = binary powerSymbol
   logBase = binary logSymbol
   exp     = unary expSymbol
   log     = unary logSymbol
   sin     = unary sinSymbol
   tan     = unary tanSymbol
   cos     = unary cosSymbol
   asin    = unary asinSymbol
   atan    = unary atanSymbol
   acos    = unary acosSymbol
   sinh    = unary sinhSymbol
   tanh    = unary tanhSymbol
   cosh    = unary coshSymbol
   asinh   = unary asinhSymbol
   atanh   = unary atanhSymbol
   acosh   = unary acoshSymbol 
   
instance Symbolic Expr where
   variable = Var
   
   getVariable (Var s) = return s
   getVariable _       = mzero
   
   function s [a, b] 
      | s == plusSymbol   = a :+: b
      | s == timesSymbol  = a :*: b
      | s == minusSymbol  = a :-: b
      | s == divSymbol    = a :/: b
   function s [a]
      | s == negateSymbol = Negate a
      | s == sqrtSymbol   = Sqrt a
   function s as = 
      Sym s as
   
   getFunction expr =
      case expr of
         a :+: b  -> return (plusSymbol,   [a, b])
         a :*: b  -> return (timesSymbol,  [a, b])
         a :-: b  -> return (minusSymbol,  [a, b])
         Negate a -> return (negateSymbol, [a])
         a :/: b  -> return (divSymbol,    [a, b])
         Sqrt a   -> return (sqrtSymbol,   [a])
         Sym s as -> return (s, as)
         _ -> mzero

-----------------------------------------------------------------------
-- Uniplate instance

instance Uniplate Expr where 
   uniplate expr =
      case getFunction expr of
         Just (s, as) -> (as, \bs -> function s bs)
         _            -> ([], const expr)

-----------------------------------------------------------------------
-- Arbitrary instance

instance Arbitrary Expr where
   arbitrary = sized arbExpr
   coarbitrary expr =
      case expr of 
         a :+: b  -> variant 0 . coarbitrary a . coarbitrary b
         a :*: b  -> variant 1 . coarbitrary a . coarbitrary b
         a :-: b  -> variant 2 . coarbitrary a . coarbitrary b
         Negate a -> variant 3 . coarbitrary a
         Nat n    -> variant 4 . coarbitrary n
         a :/: b  -> variant 5 . coarbitrary a . coarbitrary b
         Sqrt a   -> variant 6 . coarbitrary a
         Var s    -> variant 7 . coarbitrary s
         Sym f xs -> variant 8 . coarbitrary (show f) . coarbitrary xs
   
arbExpr :: Int -> Gen Expr
arbExpr _ = liftM (Nat . abs) arbitrary
{-
arbExpr 0 = oneof [liftM (Nat . abs) arbitrary, oneof [ return (Var x) | x <- ["x", "y", "z"] ] {- , return pi -} ]
arbExpr n = oneof [bin (+), bin (*), bin (-), unop negate, bin (/), unop sqrt, arbExpr 0]
 where
   bin  f = liftM2 f rec rec
   unop f = liftM f rec
   rec    = arbExpr (n `div` 2) -}
       
-----------------------------------------------------------------------
-- Fold

foldExpr (plus, times, minus, neg, nat, dv, sq, var, sym) = rec 
 where
   rec expr = 
      case expr of
         a :+: b  -> plus (rec a) (rec b)
         a :*: b  -> times (rec a) (rec b)
         a :-: b  -> minus (rec a) (rec b)
         Negate a -> neg (rec a)
         Nat n    -> nat n
         a :/: b  -> dv (rec a) (rec b)
         Sqrt a   -> sq (rec a)
         Var v    -> var v
         Sym f xs -> sym f (map rec xs)

exprToNum :: (Monad m, Num a) => Expr -> m a
exprToNum = foldExpr (liftM2 (+), liftM2 (*), liftM2 (-), liftM negate, return . fromInteger, \_ -> err, err, err, \_ -> err)
 where
   err _ = fail "exprToNum"

exprToFractional :: (Monad m, Fractional a) => Expr -> m a
exprToFractional = foldExpr (liftM2 (+), liftM2 (*), liftM2 (-), liftM negate, return . fromInteger, (/!), err, err, \_ -> err)
 where 
   mx /! my = join (liftM2 safeDivision mx my)
   err _ = fail "exprToFractional"
       
exprToFloating :: (Monad m, Floating a) => (Symbol -> [a] -> m a) -> Expr -> m a
exprToFloating f = foldExpr (liftM2 (+), liftM2 (*), liftM2 (-), liftM negate, return . fromInteger, (/!), liftM sqrt, err, sym)
 where 
   mx /! my = join (liftM2 safeDivision mx my)
   sym s = join . liftM (f s) . sequence 
   err _ = fail "Floating"

safeDivision :: (Monad m, Fractional a) => a -> a -> m a
safeDivision x y = if y==0 then fail "safeDivision" else return (x/y)

-----------------------------------------------------------------------
-- Pretty printer 

instance Show Expr where
   show = ppExprPrio False 0

parenthesizedExpr :: Expr -> String
parenthesizedExpr = ppExprPrio True 0

-- infixl 6 -, +
-- infixl 6.5 negate
-- infixl 7 *, /
-- infixr 8 ^
ppExprPrio :: Bool -> Double -> Expr -> String
ppExprPrio parens = flip $ foldExpr (binL "+" 6, binL "*" 7, binL "-" 6, neg, nat, binL "/" 7, sq, var, sym)
 where
   nat n _        = if n >= 0 then show n else "!" ++ show n
   var s _        = s
   neg x b        = parIf (b>6.5) ("-" ++ x 7)
   sq  x          = sym sqrtSymbol [x]
   sym s xs b
      | null xs   = show s
      | show s=="^" && length xs==2
                  = binR (show s) 8 (xs!!0) (xs!!1) b
      | otherwise = parIf (b>10) (unwords (show s : map ($ 15) xs))
   binL s i x y b = parIf (b>i) (x i ++ s ++ y (i+1))
   binR s i x y b = parIf (b>i) (x (i+1) ++ s ++ y i)
      
   parIf b = if b || parens then par else id
   par s   = "(" ++ s ++ ")"
    
instance MetaVar Expr where
   metaVar n = Var ("_" ++ show n)
   isMetaVar (Var ('_':is)) | not (null is) && all isDigit is = Just (read is)
   isMetaVar _ = Nothing

instance ShallowEq Expr where
   shallowEq expr1 expr2 =
      case (expr1, expr2) of
         (_ :+: _ , _ :+: _ ) -> True
         (_ :*: _ , _ :*: _ ) -> True
         (_ :-: _ , _ :-: _ ) -> True
         (Negate _, Negate _) -> True
         (Nat a   , Nat b   ) -> a==b
         (_ :/: _ , _ :/: _ ) -> True
         (Sqrt _  , Sqrt _  ) -> True
         (Var a   , Var b   ) -> a==b
         (Sym f _ , Sym g _ ) -> f==g
         _                    -> False
   
instance Rewrite Expr

-----------------------------------------------------------------------
-- AC Theory for expression

exprACs :: Operators Expr
exprACs = [plusOperator, timesOperator]

plusOperator :: Operator Expr
plusOperator = acOperator (+) isPlus
 where
   isPlus (a :+: b) = Just (a, b)
   isPlus _         = Nothing

timesOperator :: Operator Expr
timesOperator = acOperator (*) isTimes
 where
   isTimes (a :*: b) = Just (a, b)
   isTimes _         = Nothing

collectPlus, collectTimes :: Expr -> [Expr]
collectPlus  = collectWithOperator plusOperator
collectTimes = collectWithOperator timesOperator

size :: Expr -> Int
size e = 1 + compos 0 (+) size e

collectVars :: Expr -> [String]
collectVars e = [ s | Var s <- universe e ]

hasVars :: Expr -> Bool
hasVars = not . noVars

noVars :: Expr -> Bool
noVars = null . collectVars

substituteVars :: (String -> Expr) -> Expr -> Expr
substituteVars sub = rec 
 where
   rec (Var s) = sub s
   rec e = f (map rec cs)
    where (cs, f) = uniplate e